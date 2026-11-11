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

        // Matrix multiplication (compute)
        let computeResult = runComputeTest(
            device: device,
            commandQueue: commandQueue,
            library: library,
            duration: testDuration
        )
        results.append(TestResult(name: "Compute", value: computeResult, unit: "GFLOPS"))

        // Particle simulation
        let particleResult = runParticleTest(
            device: device,
            commandQueue: commandQueue,
            library: library,
            duration: testDuration
        )
        results.append(TestResult(name: "Particles", value: particleResult, unit: "Mparts/s"))

        // Gaussian blur
        let blurResult = runBlurTest(
            device: device,
            commandQueue: commandQueue,
            library: library,
            duration: testDuration
        )
        results.append(TestResult(name: "Blur", value: blurResult, unit: "MP/s"))

        // Edge detection
        let edgeResult = runEdgeTest(
            device: device,
            commandQueue: commandQueue,
            library: library,
            duration: testDuration
        )
        results.append(TestResult(name: "Edge", value: edgeResult, unit: "MP/s"))

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

        func encodeAndRun(dispatches: Int) -> Double? {
            autoreleasepool {
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(source, offset: 0, index: 0)
                encoder.setBuffer(destination, offset: 0, index: 1)
                var count = UInt32(vectorCount)
                encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)
                let width = pipeline.maxTotalThreadsPerThreadgroup
                for _ in 0..<dispatches {
                    encoder.dispatchThreads(
                        MTLSize(width: vectorCount, height: 1, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
                    )
                }
                encoder.endEncoding()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                guard commandBuffer.status == .completed, commandBuffer.error == nil else { return nil }
                let gpuTime = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
                return gpuTime > 0 ? gpuTime : nil
            }
        }

        // Warmup (also touches every page of both buffers)
        guard encodeAndRun(dispatches: 1) != nil else {
            return skipped("GPU command buffer failed")
        }

        var samples: [Double] = []
        var totalGPUTime = 0.0
        var totalDispatches = 0
        let endTime = CFAbsoluteTimeGetCurrent() + duration
        repeat {
            guard let gpuTime = encodeAndRun(dispatches: Self.bandwidthDispatchesPerCommandBuffer) else {
                return skipped("GPU command buffer failed during measurement")
            }
            totalGPUTime += gpuTime
            totalDispatches += Self.bandwidthDispatchesPerCommandBuffer
            samples.append(gpuTime / Double(Self.bandwidthDispatchesPerCommandBuffer))
        } while CFAbsoluteTimeGetCurrent() < endTime || samples.count < 3

        // Each dispatch reads and writes the whole buffer
        let bytesMoved = 2.0 * Double(bufferSize) * Double(totalDispatches)
        let gbps = bytesMoved / totalGPUTime / 1e9

        var details = TestDetails(latencies: samples)
        details.note = "GPU copy kernel, \(bufferSize / (1024 * 1024)) MB read + write per pass; experimental, not scored"
        return TestResult(name: Self.bandwidthTestName, value: gbps, unit: "GB/s", informational: true, details: details)
    }

    // MARK: - Matrix Multiplication Test

    private func runComputeTest(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary, duration: Double) -> Double {
        guard let function = library.makeFunction(name: "matrixMultiply") else {
            // Function not found in library
            return 0
        }
        guard let pipeline = try? device.makeComputePipelineState(function: function) else {
            // Pipeline creation failed
            return 0
        }

        let n = matrixSize
        let bufferSize = n * n * MemoryLayout<Float>.size

        guard let bufferA = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let bufferB = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let bufferC = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            return 0
        }

        // Initialize matrices with random data
        let ptrA = bufferA.contents().bindMemory(to: Float.self, capacity: n * n)
        let ptrB = bufferB.contents().bindMemory(to: Float.self, capacity: n * n)
        for i in 0..<(n * n) {
            ptrA[i] = Float.random(in: 0...1)
            ptrB[i] = Float.random(in: 0...1)
        }

        var totalOps = 0.0
        var iterations = 0
        let endTime = CFAbsoluteTimeGetCurrent() + duration

        // Warmup
        if !quickMode {
            autoreleasepool {
                if let commandBuffer = commandQueue.makeCommandBuffer(),
                   let encoder = commandBuffer.makeComputeCommandEncoder() {
                    encoder.setComputePipelineState(pipeline)
                    encoder.setBuffer(bufferA, offset: 0, index: 0)
                    encoder.setBuffer(bufferB, offset: 0, index: 1)
                    encoder.setBuffer(bufferC, offset: 0, index: 2)
                    var size = UInt32(n)
                    encoder.setBytes(&size, length: MemoryLayout<UInt32>.size, index: 3)

                    let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
                    let threadgroups = MTLSize(width: (n + 15) / 16, height: (n + 15) / 16, depth: 1)
                    encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
                    encoder.endEncoding()
                    commandBuffer.commit()
                    commandBuffer.waitUntilCompleted()
                }
            }
        }

        while CFAbsoluteTimeGetCurrent() < endTime {
            autoreleasepool {
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(bufferA, offset: 0, index: 0)
                encoder.setBuffer(bufferB, offset: 0, index: 1)
                encoder.setBuffer(bufferC, offset: 0, index: 2)
                var size = UInt32(n)
                encoder.setBytes(&size, length: MemoryLayout<UInt32>.size, index: 3)

                let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
                let threadgroups = MTLSize(width: (n + 15) / 16, height: (n + 15) / 16, depth: 1)
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
                encoder.endEncoding()

                let start = CFAbsoluteTimeGetCurrent()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                let elapsed = CFAbsoluteTimeGetCurrent() - start

                // Matrix multiply: 2*n^3 FLOPs (n^3 multiplies + n^3 adds)
                let flops = Double(2 * n * n * n)
                totalOps += flops / elapsed
                iterations += 1
            }
        }

        // Return average GFLOPS
        return iterations > 0 ? (totalOps / Double(iterations)) / 1_000_000_000 : 0
    }

    // MARK: - Particle Simulation Test

    private func runParticleTest(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary, duration: Double) -> Double {
        guard let function = library.makeFunction(name: "particleSimulation"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return 0
        }

        let count = particleCount
        // Each particle: position (x,y,z), velocity (x,y,z) = 6 floats
        let bufferSize = count * 6 * MemoryLayout<Float>.size

        guard let particleBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            return 0
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

        var totalParticles = 0.0
        var iterations = 0
        let endTime = CFAbsoluteTimeGetCurrent() + duration

        let threadgroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        let threadgroups = (count + threadgroupSize - 1) / threadgroupSize

        while CFAbsoluteTimeGetCurrent() < endTime {
            autoreleasepool {
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(particleBuffer, offset: 0, index: 0)
                var particleCount = UInt32(count)
                encoder.setBytes(&particleCount, length: MemoryLayout<UInt32>.size, index: 1)
                var dt: Float = 0.016  // 60 FPS timestep
                encoder.setBytes(&dt, length: MemoryLayout<Float>.size, index: 2)

                encoder.dispatchThreadgroups(
                    MTLSize(width: threadgroups, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: 1, depth: 1)
                )
                encoder.endEncoding()

                let start = CFAbsoluteTimeGetCurrent()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                let elapsed = CFAbsoluteTimeGetCurrent() - start

                totalParticles += Double(count) / elapsed
                iterations += 1
            }
        }

        // Return million particles per second
        return iterations > 0 ? (totalParticles / Double(iterations)) / 1_000_000 : 0
    }

    // MARK: - Blur Test

    private func runBlurTest(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary, duration: Double) -> Double {
        guard let function = library.makeFunction(name: "gaussianBlur"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return 0
        }

        let size = imageSize

        // Create textures
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let inputTexture = device.makeTexture(descriptor: descriptor),
              let outputTexture = device.makeTexture(descriptor: descriptor) else {
            return 0
        }

        // Fill input with procedural pattern
        fillTextureWithPattern(inputTexture)

        var totalPixels = 0.0
        var iterations = 0
        let endTime = CFAbsoluteTimeGetCurrent() + duration

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (size + 15) / 16,
            height: (size + 15) / 16,
            depth: 1
        )

        while CFAbsoluteTimeGetCurrent() < endTime {
            autoreleasepool {
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

                encoder.setComputePipelineState(pipeline)
                encoder.setTexture(inputTexture, index: 0)
                encoder.setTexture(outputTexture, index: 1)
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
                encoder.endEncoding()

                let start = CFAbsoluteTimeGetCurrent()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                let elapsed = CFAbsoluteTimeGetCurrent() - start

                totalPixels += Double(size * size) / elapsed
                iterations += 1
            }
        }

        // Return megapixels per second
        return iterations > 0 ? (totalPixels / Double(iterations)) / 1_000_000 : 0
    }

    // MARK: - Edge Detection Test

    private func runEdgeTest(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary, duration: Double) -> Double {
        guard let function = library.makeFunction(name: "sobelEdgeDetection"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return 0
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
            return 0
        }

        fillTextureWithPattern(inputTexture)

        var totalPixels = 0.0
        var iterations = 0
        let endTime = CFAbsoluteTimeGetCurrent() + duration

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (size + 15) / 16,
            height: (size + 15) / 16,
            depth: 1
        )

        while CFAbsoluteTimeGetCurrent() < endTime {
            autoreleasepool {
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

                encoder.setComputePipelineState(pipeline)
                encoder.setTexture(inputTexture, index: 0)
                encoder.setTexture(outputTexture, index: 1)
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
                encoder.endEncoding()

                let start = CFAbsoluteTimeGetCurrent()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                let elapsed = CFAbsoluteTimeGetCurrent() - start

                totalPixels += Double(size * size) / elapsed
                iterations += 1
            }
        }

        return iterations > 0 ? (totalPixels / Double(iterations)) / 1_000_000 : 0
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
