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
/// Two variants, both informational (not part of the AI score until results from chips
/// with Neural Accelerators confirm the test behaves as expected):
/// - `Tensor Matmul`: 2048x2048 with one 64x32 tile, unchanged since v2.5.0 so results stay comparable;
/// - `Tensor Matmul 4096`: 4096x4096, tries several tile sizes and reports the fastest, to see
///   whether the 2048 test leaves Neural Accelerator throughput unused.
struct GPUTensorMatmul {
    static let testName = "Tensor Matmul"
    static let largeTestName = "Tensor Matmul 4096"
    static let unit = "GFLOPS"

    /// Tile of C computed by one threadgroup (rows x columns) and the simdgroups that share it.
    /// Rows and columns must divide the matrix size.
    struct Tile: Equatable {
        let rows: Int
        let columns: Int
        let simdgroups: Int

        var label: String { "\(rows)x\(columns)" }
    }

    static let defaultTile = Tile(rows: 64, columns: 32, simdgroups: 4)
    /// Larger tiles load each input element once for more multiply-adds
    static let sweepTiles = [
        defaultTile,
        Tile(rows: 64, columns: 64, simdgroups: 4),
        Tile(rows: 128, columns: 64, simdgroups: 4)
    ]

    let name: String
    let matrixSize: Int
    let tiles: [Tile]
    /// Measurement time per tile
    let duration: Double
    /// Dispatches per command buffer, to keep launch overhead out of the GPU time
    let dispatchesPerCommandBuffer: Int

    /// The v2.5.0 test: 2048x2048, 64x32 tile, 10 dispatches per command buffer
    static func standard(duration: Double) -> GPUTensorMatmul {
        GPUTensorMatmul(name: testName, matrixSize: 2048, tiles: [defaultTile],
                        duration: duration, dispatchesPerCommandBuffer: 10)
    }

    /// 4096x4096 over `sweepTiles`. One 4096 matmul is 8x the work of a 2048 one
    /// (~90 ms on M1), so fewer dispatches per command buffer are needed
    static func large(durationPerTile: Double) -> GPUTensorMatmul {
        GPUTensorMatmul(name: largeTestName, matrixSize: 4096, tiles: sweepTiles,
                        duration: durationPerTile, dispatchesPerCommandBuffer: 2)
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
        .skipped(name: name, unit: Self.unit, reason: reason, informational: true)
    }

    /// Outcome for one tile size
    struct TileRun {
        let tile: Tile
        let gflops: Double
        let samples: [Double]
        let validation: (passed: Bool, message: String)
    }

    /// The fastest validated tile, or the fastest of all if none passed (so the failed check is shown)
    static func best(of runs: [TileRun]) -> TileRun? {
        let passed = runs.filter { $0.validation.passed }
        return (passed.isEmpty ? runs : passed).max { $0.gflops < $1.gflops }
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

        let n = matrixSize
        let elements = n * n
        let outputBytes = elements * MemoryLayout<Float>.stride
        guard let bufferA = device.makeBuffer(length: elements * MemoryLayout<Float16>.stride, options: .storageModeShared),
              let bufferB = device.makeBuffer(length: elements * MemoryLayout<Float16>.stride, options: .storageModeShared),
              let bufferC = device.makeBuffer(length: outputBytes, options: .storageModeShared) else {
            return skipped("Could not allocate GPU buffers")
        }

        // Small exact values keep the FP16 inputs deterministic and the check meaningful:
        // every product is a multiple of 1/32 and every sum stays below 2^19, so FP32
        // accumulation is exact (the check reports 0 error) while FP16 accumulation would fail it
        let a = bufferA.contents().bindMemory(to: Float16.self, capacity: elements)
        let b = bufferB.contents().bindMemory(to: Float16.self, capacity: elements)
        for i in 0..<elements {
            a[i] = Float16(Float(i % 7) * 0.125)
            b[i] = Float16(Float(i % 5) * 0.25)
        }
        let c = bufferC.contents().bindMemory(to: Float.self, capacity: elements)

        var runs: [TileRun] = []
        var failures: [(tile: Tile, reason: String)] = []
        for tile in tiles {
            switch runTile(tile, device: device, queue: queue, buffers: (bufferA, bufferB, bufferC)) {
            case .success(let samples):
                let validation = validate(a: a, b: b, c: c, n: n)
                let gflops = 2.0 * Double(n) * Double(n) * Double(n) / GPUTiming.mean(samples) / 1e9
                runs.append(TileRun(tile: tile, gflops: gflops, samples: samples, validation: validation))
            case .failure(let reason):
                failures.append((tile, reason))
            }
            // Clear C so a later tile cannot pass the check with an earlier tile's output
            memset(bufferC.contents(), 0, outputBytes)
        }

        guard let best = Self.best(of: runs) else {
            let reason = failures.first.map { "\($0.tile.label): \($0.reason)" } ?? "no tile size ran"
            return skipped("Metal 4 tensor ops unavailable (\(reason))")
        }

        var details = TestDetails(latencies: best.samples)
        details.validationPassed = best.validation.passed
        details.validation = best.validation.message
        var note = "FP16 inputs, FP32 output, \(n)x\(n), Metal 4 matmul2d"
        if tiles.count > 1 {
            let perTile = runs.map { String(format: "%@ %.0f", $0.tile.label, $0.gflops) }
                + failures.map { "\($0.tile.label) failed" }
            note += ", best tile \(best.tile.label) (\(perTile.joined(separator: ", ")) GFLOPS)"
        }
        details.note = note + "; experimental, not scored"
        return TestResult(name: name, value: best.gflops, unit: Self.unit, informational: true, details: details)
    }

    private enum TileOutcome {
        case success([Double])
        case failure(String)
    }

    @available(macOS 26.0, *)
    private func runTile(_ tile: Tile, device: MTLDevice, queue: MTLCommandQueue,
                         buffers: (a: MTLBuffer, b: MTLBuffer, c: MTLBuffer)) -> TileOutcome {
        let n = matrixSize
        guard n % tile.rows == 0, n % tile.columns == 0 else {
            return .failure("tile does not divide \(n)")
        }

        let options = MTLCompileOptions()
        options.languageVersion = .version4_0
        let pipeline: MTLComputePipelineState
        do {
            let library = try device.makeLibrary(source: Self.shaderSource(for: tile), options: options)
            guard let function = library.makeFunction(name: "tensorMatmulFP16") else {
                return .failure("kernel not found")
            }
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            return .failure(error.localizedDescription)
        }

        let threadgroupWidth = pipeline.threadExecutionWidth * tile.simdgroups
        guard threadgroupWidth <= pipeline.maxTotalThreadsPerThreadgroup else {
            return .failure("threadgroup size not supported by this GPU")
        }

        var size = Int32(n)
        let groups = MTLSize(width: n / tile.columns, height: n / tile.rows, depth: 1)
        let threads = MTLSize(width: threadgroupWidth, height: 1, depth: 1)
        guard let samples = GPUTiming.measure(
            commandQueue: queue,
            duration: duration,
            dispatchesPerCommandBuffer: dispatchesPerCommandBuffer,
            encode: { encoder in
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(buffers.a, offset: 0, index: 0)
                encoder.setBuffer(buffers.b, offset: 0, index: 1)
                encoder.setBuffer(buffers.c, offset: 0, index: 2)
                encoder.setBytes(&size, length: MemoryLayout<Int32>.size, index: 3)
                encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
            }
        ) else {
            return .failure("GPU command buffer failed")
        }
        return .success(samples)
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
    static func shaderSource(for tile: Tile) -> String {
        """
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

            constexpr auto desc = matmul2d_descriptor(\(tile.rows), \(tile.columns), dynamic_length_v<int>,
                                                      false, false, false,
                                                      matmul2d_descriptor::mode::multiply);
            matmul2d<desc, execution_simdgroups<\(tile.simdgroups)>> op;

            auto mA = A.slice(0, tgid.y * \(tile.rows));
            auto mB = B.slice(tgid.x * \(tile.columns), 0);
            auto mC = C.slice(tgid.x * \(tile.columns), tgid.y * \(tile.rows));
            op.run(mA, mB, mC);
        }
        """
    }
}
