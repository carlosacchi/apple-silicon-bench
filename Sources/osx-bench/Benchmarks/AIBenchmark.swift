import Foundation
import CoreML
import Accelerate

struct AIBenchmark: Benchmark {
    let iterations: Int = 1  // Kept for protocol conformance
    let duration: Int
    let quickMode: Bool
    let modelManager: ModelManager

    init(duration: Int, quickMode: Bool = false, modelManager: ModelManager) {
        self.duration = duration
        self.quickMode = quickMode
        self.modelManager = modelManager
    }

    // Configuration based on mode
    private var warmupIterations: Int { quickMode ? 5 : 20 }
    private var minIterations: Int { quickMode ? 5 : 10 }
    private var maxIterations: Int { quickMode ? 1000 : 10000 }

    // BNNS matrix size
    private var matrixSize: Int { quickMode ? 512 : 1024 }

    func run() async throws -> [TestResult] {
        // Try to get the model
        guard let modelURL = try await modelManager.ensureModel() else {
            // Model not available (offline mode without cache)
            return createSkippedResults()
        }

        var results: [TestResult] = []
        let testDuration = Double(duration) / 4.0  // 4 sub-tests

        // Test 1: CoreML CPU-only inference
        print("    Running CPU inference...")
        let cpuResult = try runCoreMLInference(
            modelURL: modelURL,
            computeUnits: .cpuOnly,
            duration: testDuration
        )
        results.append(TestResult(name: "CPU", value: cpuResult.ips, unit: "IPS"))

        // Test 2: CoreML GPU inference
        print("    Running GPU inference...")
        let gpuResult = try runCoreMLInference(
            modelURL: modelURL,
            computeUnits: .cpuAndGPU,
            duration: testDuration
        )
        results.append(TestResult(name: "GPU", value: gpuResult.ips, unit: "IPS"))

        // Test 3: CoreML Neural Engine (all compute units)
        print("    Running Neural Engine inference...")
        let aneResult = try runCoreMLInference(
            modelURL: modelURL,
            computeUnits: .all,
            duration: testDuration
        )
        results.append(TestResult(name: "Neural Engine", value: aneResult.ips, unit: "IPS"))

        // Test 4: BNNS matrix operations
        print("    Running BNNS operations...")
        let bnnsResult = runBNNSMatmul(duration: testDuration)
        results.append(TestResult(name: "BNNS", value: bnnsResult, unit: "GFLOPS"))

        return results
    }

    private func createSkippedResults() -> [TestResult] {
        [
            TestResult(name: "CPU", value: 0, unit: "IPS"),
            TestResult(name: "GPU", value: 0, unit: "IPS"),
            TestResult(name: "Neural Engine", value: 0, unit: "IPS"),
            TestResult(name: "BNNS", value: 0, unit: "GFLOPS")
        ]
    }

    // MARK: - CoreML Inference

    private func runCoreMLInference(
        modelURL: URL,
        computeUnits: MLComputeUnits,
        duration: Double
    ) throws -> (ips: Double, latencyMs: Double) {
        // Configure model
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits

        // Load model
        let model: MLModel
        do {
            model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            // Model loading failed
            return (0, 0)
        }

        // Get model input description to create appropriate input
        guard let inputDescription = model.modelDescription.inputDescriptionsByName.first else {
            return (0, 0)
        }

        // Create synthetic input
        let input: MLFeatureProvider
        do {
            input = try createSyntheticInput(for: inputDescription.value)
        } catch {
            return (0, 0)
        }

        // Warmup
        for _ in 0..<warmupIterations {
            _ = try? model.prediction(from: input)
        }

        // Measure
        var iterations = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        let endTime = startTime + duration

        while CFAbsoluteTimeGetCurrent() < endTime || iterations < minIterations {
            _ = try? model.prediction(from: input)
            iterations += 1
            if iterations >= maxIterations { break }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let ips = Double(iterations) / elapsed
        let latencyMs = (elapsed / Double(iterations)) * 1000

        return (ips, latencyMs)
    }

    private func createSyntheticInput(for description: MLFeatureDescription) throws -> MLFeatureProvider {
        // Create a dictionary to hold our features
        var featureDict: [String: MLFeatureValue] = [:]

        // Handle image input (most common for MobileNet)
        if let imageConstraint = description.imageConstraint {
            let width = imageConstraint.pixelsWide
            let height = imageConstraint.pixelsHigh

            // Create a CVPixelBuffer with random data
            var pixelBuffer: CVPixelBuffer?
            let attrs: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ]

            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                attrs as CFDictionary,
                &pixelBuffer
            )

            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                throw AIBenchmarkError.failedToCreateInput
            }

            // Fill with deterministic pattern (for reproducibility)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
                for y in 0..<height {
                    for x in 0..<width {
                        let offset = y * bytesPerRow + x * 4
                        ptr[offset] = UInt8((x + y) % 256)     // B
                        ptr[offset + 1] = UInt8((x * 2) % 256) // G
                        ptr[offset + 2] = UInt8((y * 2) % 256) // R
                        ptr[offset + 3] = 255                   // A
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            featureDict[description.name] = MLFeatureValue(pixelBuffer: buffer)

        } else if let multiArrayConstraint = description.multiArrayConstraint {
            // Handle multi-array input
            let shape = multiArrayConstraint.shape.map { $0.intValue }
            let count = shape.reduce(1, *)

            guard let multiArray = try? MLMultiArray(shape: multiArrayConstraint.shape, dataType: .float32) else {
                throw AIBenchmarkError.failedToCreateInput
            }

            // Fill with deterministic values
            let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: count)
            for i in 0..<count {
                ptr[i] = Float(i % 256) / 255.0
            }

            featureDict[description.name] = MLFeatureValue(multiArray: multiArray)
        } else {
            throw AIBenchmarkError.unsupportedInputType
        }

        return try MLDictionaryFeatureProvider(dictionary: featureDict)
    }

    // MARK: - BNNS Matrix Multiplication

    private func runBNNSMatmul(duration: Double) -> Double {
        let n = matrixSize

        // Allocate matrices (row-major)
        let count = n * n
        var matrixA = [Float](repeating: 0, count: count)
        var matrixB = [Float](repeating: 0, count: count)
        var matrixC = [Float](repeating: 0, count: count)

        // Initialize with deterministic values
        for i in 0..<count {
            matrixA[i] = Float(i % 100) / 100.0
            matrixB[i] = Float((i * 7) % 100) / 100.0
        }

        // Warmup using vDSP (Accelerate)
        if !quickMode {
            performMatmul(a: &matrixA, b: &matrixB, c: &matrixC, n: n)
        }

        // Measure
        var totalOps = 0.0
        var iterations = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        let endTime = startTime + duration

        while CFAbsoluteTimeGetCurrent() < endTime || iterations < minIterations {
            let iterStart = CFAbsoluteTimeGetCurrent()
            performMatmul(a: &matrixA, b: &matrixB, c: &matrixC, n: n)
            let iterElapsed = CFAbsoluteTimeGetCurrent() - iterStart

            // Matrix multiply FLOPs: 2 * n^3 (n^3 multiplies + n^3 adds)
            let flops = Double(2 * n * n * n)
            totalOps += flops / iterElapsed
            iterations += 1

            if iterations >= maxIterations { break }
        }

        // Return average GFLOPS
        return iterations > 0 ? (totalOps / Double(iterations)) / 1_000_000_000 : 0
    }

    private func performMatmul(a: inout [Float], b: inout [Float], c: inout [Float], n: Int) {
        // Use vDSP for optimized matrix multiplication
        // C = A * B (both n x n matrices)
        vDSP_mmul(a, 1, b, 1, &c, 1, vDSP_Length(n), vDSP_Length(n), vDSP_Length(n))
    }
}

// MARK: - Errors

enum AIBenchmarkError: LocalizedError {
    case failedToCreateInput
    case unsupportedInputType
    case modelLoadFailed

    var errorDescription: String? {
        switch self {
        case .failedToCreateInput:
            return "Failed to create synthetic input for model"
        case .unsupportedInputType:
            return "Model has unsupported input type"
        case .modelLoadFailed:
            return "Failed to load CoreML model"
        }
    }
}
