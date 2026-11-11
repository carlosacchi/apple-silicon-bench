import Foundation
import Metal

// MARK: - GPU Tensor Matmul (Metal 4 tensor ops)

/// FP16 matrix multiply through Metal 4 tensor ops (MetalPerformancePrimitives `matmul2d`).
///
/// The tensor ops API lets the driver pick the fastest hardware path, including the
/// GPU Neural Accelerators on chips that have them (M5 and later). On earlier chips it
/// runs on the regular GPU shader cores, so the same test works from M1 onwards and the
/// M1 result can serve as a baseline.
///
/// Reported as informational: not part of the AI score until results from chips with
/// Neural Accelerators confirm the test behaves as expected.
struct GPUTensorMatmul {
    static let testName = "Tensor Matmul"
    static let unit = "GFLOPS"

    /// Square matrix size; must be a multiple of the tile sizes below (64 and 32)
    let matrixSize: Int
    let duration: Double

    // Tile computed by one threadgroup (rows of C x columns of C)
    private static let tileRows = 64
    private static let tileColumns = 32
    private static let simdgroupsPerThreadgroup = 4
    /// Dispatches per command buffer, to keep launch overhead out of the GPU time
    private static let dispatchesPerCommandBuffer = 10

    init(matrixSize: Int = 2048, duration: Double) {
        self.matrixSize = matrixSize
        self.duration = duration
    }

    func run() -> TestResult {
        #if compiler(>=6.2) && arch(arm64)
        guard #available(macOS 26.0, *) else {
            return skipped("Requires macOS 26 or later (Metal 4)")
        }
        return runMetal4()
        #else
        // Metal 4 APIs need the macOS 26 SDK (Xcode 26, Swift 6.2) at build time,
        // and Float16 is only available when targeting arm64
        return skipped("This binary was built without the macOS 26 SDK (Metal 4) or not for arm64")
        #endif
    }

    private func skipped(_ reason: String) -> TestResult {
        .skipped(name: Self.testName, unit: Self.unit, reason: reason, informational: true)
    }

    #if compiler(>=6.2) && arch(arm64)
    @available(macOS 26.0, *)
    private func runMetal4() -> TestResult {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return skipped("Metal is not available")
        }
        guard device.supportsFamily(.metal4) else {
            return skipped("GPU does not support Metal 4")
        }
        guard let queue = device.makeCommandQueue() else {
            return skipped("Could not create a Metal command queue")
        }

        let options = MTLCompileOptions()
        options.languageVersion = .version4_0
        let pipeline: MTLComputePipelineState
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: options)
            guard let function = library.makeFunction(name: "tensorMatmulFP16") else {
                return skipped("Tensor matmul kernel not found")
            }
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            return skipped("Metal 4 tensor ops unavailable: \(error.localizedDescription)")
        }

        let n = matrixSize
        let elements = n * n
        guard let bufferA = device.makeBuffer(length: elements * MemoryLayout<Float16>.stride, options: .storageModeShared),
              let bufferB = device.makeBuffer(length: elements * MemoryLayout<Float16>.stride, options: .storageModeShared),
              let bufferC = device.makeBuffer(length: elements * MemoryLayout<Float>.stride, options: .storageModeShared) else {
            return skipped("Could not allocate GPU buffers")
        }

        // Small exact values keep the FP16 inputs deterministic and the check meaningful
        let a = bufferA.contents().bindMemory(to: Float16.self, capacity: elements)
        let b = bufferB.contents().bindMemory(to: Float16.self, capacity: elements)
        for i in 0..<elements {
            a[i] = Float16(Float(i % 7) * 0.125)
            b[i] = Float16(Float(i % 5) * 0.25)
        }

        let threadgroupWidth = pipeline.threadExecutionWidth * Self.simdgroupsPerThreadgroup
        guard threadgroupWidth <= pipeline.maxTotalThreadsPerThreadgroup else {
            return skipped("Threadgroup size not supported by this GPU")
        }

        func encodeAndRun(dispatches: Int) -> Double? {
            autoreleasepool {
                guard let commandBuffer = queue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(bufferA, offset: 0, index: 0)
                encoder.setBuffer(bufferB, offset: 0, index: 1)
                encoder.setBuffer(bufferC, offset: 0, index: 2)
                var size = Int32(n)
                encoder.setBytes(&size, length: MemoryLayout<Int32>.size, index: 3)
                let groups = MTLSize(width: n / Self.tileColumns, height: n / Self.tileRows, depth: 1)
                let threads = MTLSize(width: threadgroupWidth, height: 1, depth: 1)
                for _ in 0..<dispatches {
                    encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
                }
                encoder.endEncoding()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                guard commandBuffer.status == .completed, commandBuffer.error == nil else { return nil }
                let gpuTime = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
                return gpuTime > 0 ? gpuTime : nil
            }
        }

        // Warmup (also produces the output used for validation)
        guard encodeAndRun(dispatches: 1) != nil else {
            return skipped("GPU command buffer failed")
        }
        let validation = validate(a: a, b: b, c: bufferC.contents().bindMemory(to: Float.self, capacity: elements), n: n)

        // Measure: GPU time only, several dispatches per command buffer
        var gpuTimes: [Double] = []
        var totalGPUTime = 0.0
        var totalDispatches = 0
        let endTime = CFAbsoluteTimeGetCurrent() + duration
        repeat {
            guard let gpuTime = encodeAndRun(dispatches: Self.dispatchesPerCommandBuffer) else {
                return skipped("GPU command buffer failed during measurement")
            }
            totalGPUTime += gpuTime
            totalDispatches += Self.dispatchesPerCommandBuffer
            gpuTimes.append(gpuTime / Double(Self.dispatchesPerCommandBuffer))
        } while CFAbsoluteTimeGetCurrent() < endTime || gpuTimes.count < 3

        let flopsPerMatmul = 2.0 * Double(n) * Double(n) * Double(n)
        let gflops = flopsPerMatmul * Double(totalDispatches) / totalGPUTime / 1e9

        var details = TestDetails(latencies: gpuTimes)
        details.validationPassed = validation.passed
        details.validation = validation.message
        details.note = "FP16 inputs, FP32 output, \(n)x\(n), Metal 4 matmul2d; experimental, not scored"
        return TestResult(name: Self.testName, value: gflops, unit: Self.unit, informational: true, details: details)
    }

    /// Compares sampled elements of C with a CPU dot product using the same FP16 inputs
    private func validate(a: UnsafePointer<Float16>, b: UnsafePointer<Float16>, c: UnsafePointer<Float>, n: Int) -> (passed: Bool, message: String) {
        let samples = [(0, 0), (1, 7), (n / 2, n / 3), (17, n - 5), (n - 1, n - 1), (n / 3, 1)]
        var maxRelativeError: Float = 0
        for (row, column) in samples {
            var expected: Float = 0
            for k in 0..<n {
                expected += Float(a[row * n + k]) * Float(b[k * n + column])
            }
            let actual = c[row * n + column]
            maxRelativeError = max(maxRelativeError, abs(expected - actual) / max(abs(expected), 1e-6))
        }
        let passed = maxRelativeError < 1e-3
        return (passed, String(format: "max relative error %.2e vs CPU on %d samples", maxRelativeError, samples.count))
    }
    #endif

    // Tensors are built inline from plain buffers so a classic compute encoder can bind them.
    // Tensor extents are (columns, rows): A is n x n, B is n x n, C = A * B.
    private static let shaderSource = """
    #include <metal_stdlib>
    #include <metal_tensor>
    #include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
    using namespace metal;
    using namespace mpp::tensor_ops;

    kernel void tensorMatmulFP16(device half* a [[buffer(0)]],
                                 device half* b [[buffer(1)]],
                                 device float* c [[buffer(2)]],
                                 constant int& n [[buffer(3)]],
                                 uint2 tgid [[threadgroup_position_in_grid]])
    {
        auto A = tensor<device half, dextents<int32_t, 2>, tensor_inline>(a, dextents<int32_t, 2>(n, n));
        auto B = tensor<device half, dextents<int32_t, 2>, tensor_inline>(b, dextents<int32_t, 2>(n, n));
        auto C = tensor<device float, dextents<int32_t, 2>, tensor_inline>(c, dextents<int32_t, 2>(n, n));

        constexpr auto desc = matmul2d_descriptor(\(tileRows), \(tileColumns), dynamic_length_v<int>,
                                                  false, false, false,
                                                  matmul2d_descriptor::mode::multiply);
        matmul2d<desc, execution_simdgroups<\(simdgroupsPerThreadgroup)>> op;

        auto mA = A.slice(0, tgid.y * \(tileRows));
        auto mB = B.slice(tgid.x * \(tileColumns), 0);
        auto mC = C.slice(tgid.x * \(tileColumns), tgid.y * \(tileRows));
        op.run(mA, mB, mC);
    }
    """
}
