import Foundation
import Metal

struct GPUBenchmark: Benchmark {
    let iterations: Int = 1  // Kept for protocol conformance
    let duration: Int
    let quickMode: Bool
    let gpuCores: Int

    init(duration: Int, quickMode: Bool = false, gpuCores: Int = 8) {
        self.duration = duration
        self.quickMode = quickMode
        self.gpuCores = gpuCores
    }

    // Test sizes based on mode
    private var matrixSize: Int { quickMode ? 1024 : 2048 }
    private var particleCount: Int { quickMode ? 100_000 : 1_000_000 }
    private var imageSize: Int { quickMode ? 2048 : 4096 }

    func run() async throws -> [TestResult] {
        guard let device = MTLCreateSystemDefaultDevice() else {
            // Metal not available - return zeros for all tests
            return createFailedResults(reason: "Metal is not available")
        }

        guard let commandQueue = device.makeCommandQueue() else {
            return createFailedResults(reason: "Could not create a Metal command queue")
        }

        // Compile shaders
        let library: MTLLibrary
        do {
            library = try await device.makeLibrary(source: metalShaderSource, options: nil)
        } catch {
            return createFailedResults(reason: "Shader compilation failed: \(error.localizedDescription)")
        }

        var results: [TestResult] = []
        let testDuration = Double(duration) / 4.0  // Divide among 4 tests

        func scored(_ name: String, _ unit: String, _ value: Double?) -> TestResult {
            guard let value = value else {
                return .skipped(name: name, unit: unit, reason: "GPU kernel or command buffer failed")
            }
            return TestResult(name: name, value: value, unit: unit)
        }

        // Matrix multiplication (compute)
        results.append(scored("Compute", "GFLOPS", runComputeTest(
            device: device, commandQueue: commandQueue, library: library, duration: testDuration
        )))

        // Particle simulation
        results.append(scored("Particles", "Mparts/s", runParticleTest(
            device: device, commandQueue: commandQueue, library: library, duration: testDuration
        )))

        // Gaussian blur
        results.append(scored("Blur", "MP/s", runBlurTest(
            device: device, commandQueue: commandQueue, library: library, duration: testDuration
        )))

        // Edge detection
        results.append(scored("Edge", "MP/s", runEdgeTest(
            device: device, commandQueue: commandQueue, library: library, duration: testDuration
        )))

        // Informational: GPU-side memory bandwidth (not scored yet)
        results.append(runBandwidthTest(
            device: device,
            commandQueue: commandQueue,
            library: library,
            duration: quickMode ? 0.5 : 1.5
        ))

        return results
    }

    private func createFailedResults(reason: String) -> [TestResult] {
        [
            .skipped(name: "Compute", unit: "GFLOPS", reason: reason),
            .skipped(name: "Particles", unit: "Mparts/s", reason: reason),
            .skipped(name: "Blur", unit: "MP/s", reason: reason),
            .skipped(name: "Edge", unit: "MP/s", reason: reason),
            .skipped(name: Self.bandwidthTestName, unit: "GB/s", reason: reason, informational: true)
        ]
    }

    // MARK: - Memory Bandwidth Test

    static let bandwidthTestName = "Memory Bandwidth"
    /// Dispatches per command buffer, to keep launch overhead out of the GPU time
    private static let bandwidthDispatchesPerCommandBuffer = 8

    /// Streams a large buffer through the GPU (read + write) and reports bytes moved per second
    /// of GPU time. Buffers are larger than the system level cache, so this measures DRAM bandwidth
    /// as seen by the GPU, which bounds LLM token generation speed.
    private func runBandwidthTest(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary, duration: Double) -> TestResult {
        func skipped(_ reason: String) -> TestResult {
            .skipped(name: Self.bandwidthTestName, unit: "GB/s", reason: reason, informational: true)
        }
        guard let function = library.makeFunction(name: "streamCopy"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return skipped("Bandwidth kernel unavailable")
        }

        // 256 MB per buffer (128 MB in quick mode): well above the SLC of every current chip
        let bufferSize = (quickMode ? 128 : 256) * 1024 * 1024
        let vectorCount = bufferSize / MemoryLayout<SIMD4<Float>>.stride
        guard let source = device.makeBuffer(length: bufferSize, options: .storageModePrivate),
              let destination = device.makeBuffer(length: bufferSize, options: .storageModePrivate) else {
            return skipped("Could not allocate GPU buffers")
        }

        let width = pipeline.maxTotalThreadsPerThreadgroup
        var count = UInt32(vectorCount)
        guard let samples = GPUTiming.measure(
            commandQueue: commandQueue,
            duration: duration,
            dispatchesPerCommandBuffer: Self.bandwidthDispatchesPerCommandBuffer,
            encode: { encoder in
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(source, offset: 0, index: 0)
                encoder.setBuffer(destination, offset: 0, index: 1)
                encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)
                encoder.dispatchThreads(
                    MTLSize(width: vectorCount, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
                )
            }
        ) else {
            return skipped("GPU command buffer failed")
        }

        // Each dispatch reads and writes the whole buffer
        let gbps = 2.0 * Double(bufferSize) / GPUTiming.mean(samples) / 1e9

        var details = TestDetails(latencies: samples)
        details.note = "GPU copy kernel, \(bufferSize / (1024 * 1024)) MB read + write per pass; experimental, not scored"
        return TestResult(name: Self.bandwidthTestName, value: gbps, unit: "GB/s", informational: true, details: details)
    }

    // MARK: - Matrix Multiplication Test

    /// GFLOPS of a naive matmul kernel (one thread per output element, no tiling).
    /// It is limited by the cache hierarchy, not by ALU throughput.
    private func runComputeTest(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary, duration: Double) -> Double? {
        guard let function = library.makeFunction(name: "matrixMultiply"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return nil
        }

        let n = matrixSize
        let bufferSize = n * n * MemoryLayout<Float>.size

        guard let bufferA = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let bufferB = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let bufferC = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            return nil
        }

        // Initialize matrices with random data
        let ptrA = bufferA.contents().bindMemory(to: Float.self, capacity: n * n)
        let ptrB = bufferB.contents().bindMemory(to: Float.self, capacity: n * n)
        for i in 0..<(n * n) {
            ptrA[i] = Float.random(in: 0...1)
            ptrB[i] = Float.random(in: 0...1)
        }

        var size = UInt32(n)
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(width: (n + 15) / 16, height: (n + 15) / 16, depth: 1)
        guard let samples = GPUTiming.measure(commandQueue: commandQueue, duration: duration, encode: { encoder in
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(bufferA, offset: 0, index: 0)
            encoder.setBuffer(bufferB, offset: 0, index: 1)
            encoder.setBuffer(bufferC, offset: 0, index: 2)
            encoder.setBytes(&size, length: MemoryLayout<UInt32>.size, index: 3)
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        }) else { return nil }

        // Matrix multiply: 2*n^3 FLOPs (n^3 multiplies + n^3 adds)
        return 2.0 * Double(n) * Double(n) * Double(n) / GPUTiming.mean(samples) / 1e9
    }

    // MARK: - Particle Simulation Test

    private func runParticleTest(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary, duration: Double) -> Double? {
        guard let function = library.makeFunction(name: "particleSimulation"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return nil
        }

        let count = particleCount
        // Each particle: position (x,y,z), velocity (x,y,z) = 6 floats
        let bufferSize = count * 6 * MemoryLayout<Float>.size

        guard let particleBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            return nil
        }

        // Initialize particles
        let ptr = particleBuffer.contents().bindMemory(to: Float.self, capacity: count * 6)
        for i in 0..<count {
            ptr[i * 6 + 0] = Float.random(in: -100...100)  // pos.x
            ptr[i * 6 + 1] = Float.random(in: -100...100)  // pos.y
            ptr[i * 6 + 2] = Float.random(in: -100...100)  // pos.z
            ptr[i * 6 + 3] = Float.random(in: -1...1)      // vel.x
            ptr[i * 6 + 4] = Float.random(in: -1...1)      // vel.y
            ptr[i * 6 + 5] = Float.random(in: -1...1)      // vel.z
        }

        let threadgroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        let threadgroups = (count + threadgroupSize - 1) / threadgroupSize
        var particleCount = UInt32(count)
        var dt: Float = 0.016  // 60 FPS timestep

        guard let samples = GPUTiming.measure(commandQueue: commandQueue, duration: duration, encode: { encoder in
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(particleBuffer, offset: 0, index: 0)
            encoder.setBytes(&particleCount, length: MemoryLayout<UInt32>.size, index: 1)
            encoder.setBytes(&dt, length: MemoryLayout<Float>.size, index: 2)
            encoder.dispatchThreadgroups(
                MTLSize(width: threadgroups, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: 1, depth: 1)
            )
        }) else { return nil }

        // Million particles per second
        return Double(count) / GPUTiming.mean(samples) / 1_000_000
    }

    // MARK: - Blur Test

    private func runBlurTest(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary, duration: Double) -> Double? {
        runImageFilterTest(kernel: "gaussianBlur", device: device, commandQueue: commandQueue, library: library, duration: duration)
    }

    // MARK: - Edge Detection Test

    private func runEdgeTest(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary, duration: Double) -> Double? {
        runImageFilterTest(kernel: "sobelEdgeDetection", device: device, commandQueue: commandQueue, library: library, duration: duration)
    }

    /// Megapixels per second of a texture-to-texture filter kernel over a square RGBA8 image
    private func runImageFilterTest(kernel: String, device: MTLDevice, commandQueue: MTLCommandQueue,
                                    library: MTLLibrary, duration: Double) -> Double? {
        guard let function = library.makeFunction(name: kernel),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return nil
        }

        let size = imageSize
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let inputTexture = device.makeTexture(descriptor: descriptor),
              let outputTexture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        // Fill input with procedural pattern
        fillTextureWithPattern(inputTexture)

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(width: (size + 15) / 16, height: (size + 15) / 16, depth: 1)

        guard let samples = GPUTiming.measure(commandQueue: commandQueue, duration: duration, encode: { encoder in
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(inputTexture, index: 0)
            encoder.setTexture(outputTexture, index: 1)
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        }) else { return nil }

        return Double(size * size) / GPUTiming.mean(samples) / 1_000_000
    }

    // MARK: - Helpers

    private func fillTextureWithPattern(_ texture: MTLTexture) {
        let size = texture.width
        let rowBytes = size * 4

        // Allocate on heap instead of stack to avoid stack overflow for large textures
        let pixelData = UnsafeMutablePointer<UInt8>.allocate(capacity: size * size * 4)
        defer { pixelData.deallocate() }

        // Fill row by row to be more cache-friendly
        for y in 0..<size {
            for x in 0..<size {
                let idx = (y * size + x) * 4
                // Gradient + noise pattern for realistic workload
                let gradient = UInt8((x + y) % 256)
                // Use deterministic "noise" for reproducibility (avoid random per-pixel)
                let noise = UInt8((x * 7 + y * 13) % 50)
                pixelData[idx + 0] = gradient &+ noise        // R
                pixelData[idx + 1] = UInt8(truncatingIfNeeded: 255 - Int(gradient))  // G
                pixelData[idx + 2] = UInt8((x * y) % 256)     // B
                pixelData[idx + 3] = 255                       // A
            }
        }

        texture.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                             size: MTLSize(width: size, height: size, depth: 1)),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: rowBytes
        )
    }
}

// MARK: - GPU Timing

/// GPU-side timing shared by the GPU tests and Tensor Matmul.
///
/// Each sample is the GPU execution time of one command buffer (`gpuEndTime - gpuStartTime`)
/// divided by its dispatches. This leaves out CPU-side submission and completion latency
/// (~0.14 ms per command buffer on M1), which until v2.5.0 was part of every scored GPU test
/// and made up a large share of short dispatches on fast GPUs (e.g. Particles, ~0.3 ms on M5 Pro).
enum GPUTiming {
    /// Runs one warmup command buffer, then measures until `duration` has passed and at least
    /// `minSamples` samples exist. Returns seconds per dispatch, or nil if the GPU reported an error.
    static func measure(
        commandQueue: MTLCommandQueue,
        duration: Double,
        dispatchesPerCommandBuffer: Int = 1,
        minSamples: Int = 3,
        encode: (MTLComputeCommandEncoder) -> Void
    ) -> [Double]? {
        func runOnce() -> Double? {
            autoreleasepool {
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
                for _ in 0..<dispatchesPerCommandBuffer {
                    encode(encoder)
                }
                encoder.endEncoding()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                guard commandBuffer.status == .completed, commandBuffer.error == nil else { return nil }
                let gpuTime = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
                return gpuTime > 0 ? gpuTime / Double(dispatchesPerCommandBuffer) : nil
            }
        }

        // Warmup (also touches every page of the buffers)
        guard runOnce() != nil else { return nil }

        var samples: [Double] = []
        let endTime = CFAbsoluteTimeGetCurrent() + duration
        repeat {
            guard let sample = runOnce() else { return nil }
            samples.append(sample)
        } while CFAbsoluteTimeGetCurrent() < endTime || samples.count < minSamples
        return samples
    }

    /// Mean seconds per dispatch: total work over total GPU time, not the mean of per-sample rates
    static func mean(_ samples: [Double]) -> Double {
        samples.reduce(0, +) / Double(max(samples.count, 1))
    }
}

// MARK: - Metal Shaders

private let metalShaderSource = """
#include <metal_stdlib>
using namespace metal;

// Memory bandwidth kernel: one float4 read and one float4 write per thread
kernel void streamCopy(
    device const float4* source [[buffer(0)]],
    device float4* destination [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;
    destination[gid] = source[gid];
}

// Matrix multiplication kernel
// Each thread computes one element of the result matrix
kernel void matrixMultiply(
    device const float* A [[buffer(0)]],
    device const float* B [[buffer(1)]],
    device float* C [[buffer(2)]],
    constant uint& n [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= n || gid.y >= n) return;

    float sum = 0.0;
    for (uint k = 0; k < n; k++) {
        sum += A[gid.y * n + k] * B[k * n + gid.x];
    }
    C[gid.y * n + gid.x] = sum;
}

// Particle simulation kernel
// Each particle has: pos.xyz, vel.xyz (6 floats)
kernel void particleSimulation(
    device float* particles [[buffer(0)]],
    constant uint& count [[buffer(1)]],
    constant float& dt [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    uint idx = gid * 6;

    // Load particle data
    float3 pos = float3(particles[idx], particles[idx + 1], particles[idx + 2]);
    float3 vel = float3(particles[idx + 3], particles[idx + 4], particles[idx + 5]);

    // Simple gravity toward origin
    float3 toOrigin = -pos;
    float dist = length(toOrigin);
    if (dist > 0.1) {
        float3 gravity = normalize(toOrigin) * 10.0;
        vel += gravity * dt;
    }

    // Damping
    vel *= 0.999;

    // Update position
    pos += vel * dt;

    // Store back
    particles[idx] = pos.x;
    particles[idx + 1] = pos.y;
    particles[idx + 2] = pos.z;
    particles[idx + 3] = vel.x;
    particles[idx + 4] = vel.y;
    particles[idx + 5] = vel.z;
}

// Gaussian blur (5x5)
kernel void gaussianBlur(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) return;

    // 5x5 Gaussian weights (sigma ~= 1.0)
    const float weights[25] = {
        0.003, 0.013, 0.022, 0.013, 0.003,
        0.013, 0.059, 0.097, 0.059, 0.013,
        0.022, 0.097, 0.159, 0.097, 0.022,
        0.013, 0.059, 0.097, 0.059, 0.013,
        0.003, 0.013, 0.022, 0.013, 0.003
    };

    float4 sum = float4(0.0);
    int w = input.get_width();
    int h = input.get_height();

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            int x = clamp(int(gid.x) + dx, 0, w - 1);
            int y = clamp(int(gid.y) + dy, 0, h - 1);
            int idx = (dy + 2) * 5 + (dx + 2);
            sum += input.read(uint2(x, y)) * weights[idx];
        }
    }

    output.write(sum, gid);
}

// Sobel edge detection kernel
kernel void sobelEdgeDetection(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) return;

    int w = input.get_width();
    int h = input.get_height();

    // Sample 3x3 neighborhood (grayscale)
    float samples[3][3];
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int x = clamp(int(gid.x) + dx, 0, w - 1);
            int y = clamp(int(gid.y) + dy, 0, h - 1);
            float4 color = input.read(uint2(x, y));
            samples[dy + 1][dx + 1] = dot(color.rgb, float3(0.299, 0.587, 0.114));
        }
    }

    // Sobel X and Y
    float gx = samples[0][2] - samples[0][0]
             + 2.0 * (samples[1][2] - samples[1][0])
             + samples[2][2] - samples[2][0];

    float gy = samples[2][0] - samples[0][0]
             + 2.0 * (samples[2][1] - samples[0][1])
             + samples[2][2] - samples[0][2];

    float edge = sqrt(gx * gx + gy * gy);
    edge = clamp(edge, 0.0, 1.0);

    output.write(float4(edge, edge, edge, 1.0), gid);
}
"""
