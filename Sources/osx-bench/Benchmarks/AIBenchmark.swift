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

    // MARK: - Test Names (also the scoring keys, see BenchmarkScorer)

    static let cpuTestName = "CPU"
    static let gpuTestName = "GPU"
    static let neuralEngineTestName = "Neural Engine"
    static let matmulTestName = "Accelerate Matmul"

    // Configuration based on mode
    private var warmupIterations: Int { quickMode ? 5 : 20 }
    private var minIterations: Int { quickMode ? 5 : 10 }
    private var maxIterations: Int { quickMode ? 1000 : 10000 }

    /// Same size in quick and full mode so both are comparable with the M1 baseline
    private let matrixSize = 2048

    /// Core ML output vectors must match the CPU reference at least this closely
    private static let minCosineSimilarity = 0.99

    func run() async throws -> [TestResult] {
        guard let modelURL = try await modelManager.ensureModel() else {
            return skippedResults(reason: "AI model not cached and --offline specified")
        }

        var results: [TestResult] = []
        let testDuration = Double(duration) / 4.0  // 4 scored sub-tests

        // Test 1: Core ML CPU-only inference (also provides the reference output)
        print("    Running CPU inference...")
        let cpu = await runCoreMLInference(
            name: Self.cpuTestName, modelURL: modelURL, computeUnits: .cpuOnly,
            duration: testDuration, reference: nil
        )
        results.append(cpu.result)

        // Test 2: Core ML GPU inference
        print("    Running GPU inference...")
        let gpu = await runCoreMLInference(
            name: Self.gpuTestName, modelURL: modelURL, computeUnits: .cpuAndGPU,
            duration: testDuration, reference: cpu.output
        )
        results.append(gpu.result)

        // Test 3: Core ML Neural Engine inference (CPU fallback only, never GPU)
        print("    Running Neural Engine inference...")
        let ane = await runCoreMLInference(
            name: Self.neuralEngineTestName, modelURL: modelURL, computeUnits: .cpuAndNeuralEngine,
            duration: testDuration, reference: cpu.output
        )
        results.append(ane.result)

        // Test 4: Accelerate FP32 matrix multiply (runs on the CPU matrix unit)
        print("    Running Accelerate matmul...")
        results.append(runAccelerateMatmul(duration: testDuration))

        // Informational: GPU FP16 matmul through Metal 4 tensor ops
        print("    Running GPU tensor matmul (experimental)...")
        results.append(GPUTensorMatmul(duration: quickMode ? 0.5 : 1.5).run())

        return results
    }

    private func skippedResults(reason: String) -> [TestResult] {
        [
            .skipped(name: Self.cpuTestName, unit: "IPS", reason: reason),
            .skipped(name: Self.gpuTestName, unit: "IPS", reason: reason),
            .skipped(name: Self.neuralEngineTestName, unit: "IPS", reason: reason),
            .skipped(name: Self.matmulTestName, unit: "GFLOPS", reason: reason),
            .skipped(name: GPUTensorMatmul.testName, unit: GPUTensorMatmul.unit, reason: reason, informational: true)
        ]
    }

    // MARK: - Core ML Inference

    private struct InferenceRun {
        let result: TestResult
        /// Flattened numeric output of the first prediction, used to validate other compute units
        let output: [Double]?

        static func skipped(_ name: String, _ reason: String) -> InferenceRun {
            InferenceRun(result: .skipped(name: name, unit: "IPS", reason: reason), output: nil)
        }
    }

    private func runCoreMLInference(
        name: String,
        modelURL: URL,
        computeUnits: MLComputeUnits,
        duration: Double,
        reference: [Double]?
    ) async -> InferenceRun {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits

        // Load model (timed: includes device-specific compilation when not cached by the OS)
        let loadStart = CFAbsoluteTimeGetCurrent()
        let model: MLModel
        do {
            model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            return .skipped(name, "Model failed to load: \(error.localizedDescription)")
        }
        let loadTimeMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000

        guard let inputDescription = model.modelDescription.inputDescriptionsByName.first else {
            return .skipped(name, "Model has no inputs")
        }

        let input: MLFeatureProvider
        do {
            input = try createSyntheticInput(for: inputDescription.value)
        } catch {
            return .skipped(name, error.localizedDescription)
        }

        // Warmup; the first output is kept for validation
        let firstOutput: MLFeatureProvider
        do {
            firstOutput = try model.prediction(from: input)
            for _ in 1..<warmupIterations {
                _ = try model.prediction(from: input)
            }
        } catch {
            return .skipped(name, "Prediction failed: \(error.localizedDescription)")
        }

        // Measure: only successful predictions are counted; any error invalidates the test
        var latencies: [Double] = []
        latencies.reserveCapacity(min(maxIterations, 4096))
        let startTime = CFAbsoluteTimeGetCurrent()
        let endTime = startTime + duration
        do {
            while (CFAbsoluteTimeGetCurrent() < endTime || latencies.count < minIterations)
                    && latencies.count < maxIterations {
                let iterationStart = CFAbsoluteTimeGetCurrent()
                _ = try model.prediction(from: input)
                latencies.append(CFAbsoluteTimeGetCurrent() - iterationStart)
            }
        } catch {
            return .skipped(name, "Prediction failed after \(latencies.count) iterations: \(error.localizedDescription)")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let ips = Double(latencies.count) / elapsed

        let output = Self.outputVector(firstOutput)
        var details = TestDetails(latencies: latencies)
        details.loadTimeMs = loadTimeMs
        if let reference = reference {
            let check = Self.validate(output: output, reference: reference)
            details.validationPassed = check.passed
            details.validation = check.message
        } else {
            details.validation = output == nil ? "no numeric output to compare" : "reference output"
        }
        if computeUnits == .cpuAndNeuralEngine {
            details.computePlan = await Self.computePlan(modelURL: modelURL, configuration: config)
        }

        return InferenceRun(
            result: TestResult(name: name, value: ips, unit: "IPS", details: details),
            output: output
        )
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

    // MARK: - Output Validation

    /// Flattens numeric outputs (multi-arrays, dictionaries, scalars) in a stable order
    static func outputVector(_ provider: MLFeatureProvider) -> [Double]? {
        var values: [Double] = []
        for name in provider.featureNames.sorted() {
            guard let feature = provider.featureValue(for: name) else { continue }
            switch feature.type {
            case .multiArray:
                if let array = feature.multiArrayValue {
                    values.reserveCapacity(values.count + array.count)
                    for i in 0..<array.count {
                        values.append(array[i].doubleValue)
                    }
                }
            case .dictionary:
                let entries = feature.dictionaryValue.sorted { "\($0.key)" < "\($1.key)" }
                values.append(contentsOf: entries.map { $0.value.doubleValue })
            case .double:
                values.append(feature.doubleValue)
            case .int64:
                values.append(Double(feature.int64Value))
            default:
                continue  // Strings and images are not compared
            }
        }
        return values.isEmpty ? nil : values
    }

    /// Passes when the output is close to the CPU reference (FP16 on GPU/ANE causes small differences)
    static func validate(output: [Double]?, reference: [Double]) -> (passed: Bool?, message: String) {
        guard let output = output else {
            return (nil, "no numeric output to compare")
        }
        guard let cosine = VectorComparison.cosineSimilarity(output, reference) else {
            return (false, "output shape differs from CPU reference")
        }
        let sameTop1 = VectorComparison.argmax(output) == VectorComparison.argmax(reference)
        let passed = cosine >= minCosineSimilarity
        let top1 = sameTop1 ? "same top-1" : "different top-1"
        return (passed, String(format: "cosine %.4f vs CPU, %@", cosine, top1))
    }

    // MARK: - Compute Plan

    /// Counts model operations by the device Core ML plans to run them on (macOS 14.4+).
    /// This is the planned placement, not a runtime trace.
    static func computePlan(modelURL: URL, configuration: MLModelConfiguration) async -> [String: Int]? {
        guard #available(macOS 14.4, *) else { return nil }
        guard let plan = try? await MLComputePlan.load(contentsOf: modelURL, configuration: configuration) else {
            return nil
        }

        var counts: [String: Int] = [:]
        func record(_ usage: MLComputePlan.DeviceUsage?) {
            guard let usage = usage else { return }
            counts[deviceName(usage.preferred), default: 0] += 1
        }
        func walk(_ block: MLModelStructure.Program.Block) {
            for operation in block.operations {
                record(plan.deviceUsage(for: operation))
                operation.blocks.forEach(walk)
            }
        }

        switch plan.modelStructure {
        case .neuralNetwork(let network):
            network.layers.forEach { record(plan.deviceUsage(for: $0)) }
        case .program(let program):
            program.functions.values.forEach { walk($0.block) }
        default:
            return nil  // Pipelines and unknown structures are not summarized
        }
        return counts.isEmpty ? nil : counts
    }

    @available(macOS 14.0, *)
    private static func deviceName(_ device: MLComputeDevice) -> String {
        switch device {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .neuralEngine: return "Neural Engine"
        @unknown default: return "Other"
        }
    }

    // MARK: - Accelerate Matrix Multiplication

    /// FP32 matrix multiply with vDSP_mmul. On Apple Silicon, Accelerate runs this on the
    /// CPU matrix unit (AMX, SME on M4 and later), not on plain NEON cores.
    private func runAccelerateMatmul(duration: Double) -> TestResult {
        let n = matrixSize
        let count = n * n
        let byteCount = count * MemoryLayout<Float>.stride

        func allocate() -> UnsafeMutablePointer<Float>? {
            var raw: UnsafeMutableRawPointer?
            guard posix_memalign(&raw, Int(getpagesize()), byteCount) == 0, let raw = raw else { return nil }
            return raw.bindMemory(to: Float.self, capacity: count)
        }
        guard let a = allocate() else {
            return .skipped(name: Self.matmulTestName, unit: "GFLOPS", reason: "Matrix allocation failed")
        }
        defer { free(a) }
        guard let b = allocate() else {
            return .skipped(name: Self.matmulTestName, unit: "GFLOPS", reason: "Matrix allocation failed")
        }
        defer { free(b) }
        guard let c = allocate() else {
            return .skipped(name: Self.matmulTestName, unit: "GFLOPS", reason: "Matrix allocation failed")
        }
        defer { free(c) }

        // Deterministic values
        for i in 0..<count {
            a[i] = Float(i % 100) / 100.0
            b[i] = Float((i * 7) % 100) / 100.0
        }

        func multiply() {
            vDSP_mmul(a, 1, b, 1, c, 1, vDSP_Length(n), vDSP_Length(n), vDSP_Length(n))
        }

        // Warmup
        multiply()

        var latencies: [Double] = []
        let startTime = CFAbsoluteTimeGetCurrent()
        let endTime = startTime + duration
        while (CFAbsoluteTimeGetCurrent() < endTime || latencies.count < minIterations)
                && latencies.count < maxIterations {
            let iterationStart = CFAbsoluteTimeGetCurrent()
            multiply()
            latencies.append(CFAbsoluteTimeGetCurrent() - iterationStart)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // 2 * n^3 FLOPs per multiply (n^3 multiplies + n^3 adds); total work over total time
        let flops = 2.0 * Double(n) * Double(n) * Double(n) * Double(latencies.count)
        let gflops = flops / elapsed / 1e9

        var details = TestDetails(latencies: latencies)
        details.note = "FP32, \(n)x\(n), vDSP_mmul"
        return TestResult(name: Self.matmulTestName, value: gflops, unit: "GFLOPS", details: details)
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
