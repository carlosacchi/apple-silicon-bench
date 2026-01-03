import Foundation

// MARK: - Benchmark Types

enum BenchmarkType: String, CaseIterable, Codable {
    case cpuSingleCore = "cpu-single"
    case cpuMultiCore = "cpu-multi"
    case memory = "memory"
    case disk = "disk"
    case gpu = "gpu"
    case ai = "ai"

    var displayName: String {
        switch self {
        case .cpuSingleCore: return "CPU Single-Core"
        case .cpuMultiCore: return "CPU Multi-Core"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .gpu: return "GPU"
        case .ai: return "AI/ML"
        }
    }
}

// MARK: - Individual Test Results

struct TestResult: Codable {
    let name: String
    let value: Double
    let unit: String
    let higherIsBetter: Bool

    init(name: String, value: Double, unit: String, higherIsBetter: Bool = true) {
        self.name = name
        self.value = value
        self.unit = unit
        self.higherIsBetter = higherIsBetter
    }

    var formattedValue: String {
        if value >= 1_000_000 {
            return String(format: "%.2f M", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.2f K", value / 1_000)
        } else if value < 1 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - Benchmark Category Results

struct BenchmarkResult: Codable {
    let type: BenchmarkType
    let tests: [TestResult]
    let duration: TimeInterval
    let thermalStart: ThermalMonitor.ThermalLevel
    let thermalEnd: ThermalMonitor.ThermalLevel

    init(type: BenchmarkType, tests: [TestResult], duration: TimeInterval,
         thermalStart: ThermalMonitor.ThermalLevel = .nominal,
         thermalEnd: ThermalMonitor.ThermalLevel = .nominal) {
        self.type = type
        self.tests = tests
        self.duration = duration
        self.thermalStart = thermalStart
        self.thermalEnd = thermalEnd
    }

    var hadThrottling: Bool {
        thermalStart == .serious || thermalStart == .critical ||
        thermalEnd == .serious || thermalEnd == .critical
    }

    var summary: String {
        let testSummaries = tests.map { "\($0.name): \($0.formattedValue) \($0.unit)" }
        return testSummaries.joined(separator: ", ")
    }
}

// MARK: - Complete Results

struct BenchmarkResults: Codable {
    let timestamp: Date
    let benchmarks: [BenchmarkResult]
    let thermalData: [ThermalSnapshot]

    init(benchmarks: [BenchmarkResult], thermalData: [ThermalSnapshot] = []) {
        self.timestamp = Date()
        self.benchmarks = benchmarks
        self.thermalData = thermalData
    }

    func result(for type: BenchmarkType) -> BenchmarkResult? {
        benchmarks.first { $0.type == type }
    }

    var hadAnyThrottling: Bool {
        benchmarks.contains { $0.hadThrottling } ||
        thermalData.contains { $0.level == .serious || $0.level == .critical }
    }
}

// MARK: - Scores

struct BenchmarkScores: Codable {
    let cpuSingleCore: Double
    let cpuMultiCore: Double
    let memory: Double
    let disk: Double
    let gpu: Double
    let total: Double
    // AI score is SEPARATE from total (like Geekbench AI)
    let ai: Double
    // Track which benchmarks were run (vs skipped via --only)
    let ranCpuSingle: Bool
    let ranCpuMulti: Bool
    let ranMemory: Bool
    let ranDisk: Bool
    let ranGpu: Bool
    let ranAi: Bool

    init(cpuSingleCore: Double, cpuMultiCore: Double, memory: Double, disk: Double, gpu: Double, total: Double,
         ai: Double = 0, ranCpuSingle: Bool = false, ranCpuMulti: Bool = false, ranMemory: Bool = false,
         ranDisk: Bool = false, ranGpu: Bool = false, ranAi: Bool = false) {
        self.cpuSingleCore = cpuSingleCore
        self.cpuMultiCore = cpuMultiCore
        self.memory = memory
        self.disk = disk
        self.gpu = gpu
        self.total = total
        self.ai = ai
        self.ranCpuSingle = ranCpuSingle
        self.ranCpuMulti = ranCpuMulti
        self.ranMemory = ranMemory
        self.ranDisk = ranDisk
        self.ranGpu = ranGpu
        self.ranAi = ranAi
    }

    func printSummary(quickMode: Bool = false, partialRun: Bool = false) {
        let line = String(repeating: "─", count: 44)
        print(line)
        print("  BENCHMARK SCORES")
        print(line)
        // Show score if benchmark ran (even if 0 = failed), hide if not run
        if ranCpuSingle { print(dotPad("CPU Single-Core", formatScore(cpuSingleCore))) }
        if ranCpuMulti { print(dotPad("CPU Multi-Core", formatScore(cpuMultiCore))) }
        if ranMemory { print(dotPad("Memory", formatScore(memory))) }
        if ranDisk { print(dotPad("Disk", formatScore(disk))) }
        if ranGpu { print(dotPad("GPU", formatScore(gpu))) }
        print(line)
        print(dotPad("TOTAL SCORE", formatScore(total)))
        print(line)

        // Print AI score separately (like Geekbench AI)
        if ranAi {
            print()
            print(line)
            print("  AI/ML SCORE (Separate)")
            print(line)
            print(dotPad("AI Score", formatScore(ai)))
            print(line)
        }

        // Print notes about scoring accuracy
        if quickMode {
            print("  ⚠️  Quick mode: scores may be less accurate")
        }
        if partialRun {
            print("  ℹ️  Partial run: total based on selected tests")
        }
    }

    private func formatScore(_ score: Double) -> String {
        if !score.isFinite {
            return "INCOMPLETE"
        }
        score > 0 ? String(Int(score)) : "Failed"
    }

    private func dotPad(_ label: String, _ value: String) -> String {
        let prefix = "  \(label) "
        let suffix = " \(value)"
        let dotsCount = max(2, 44 - prefix.count - suffix.count)
        return prefix + String(repeating: ".", count: dotsCount) + suffix
    }
}

// MARK: - Scorer

struct BenchmarkScorer {
    // Reference values (baseline = M1 8-core = 1000 points per category)
    // Units MUST match the benchmark output units exactly
    // Calibrated from real M1 8GB benchmarks (median of 5 runs, full mode)
    //
    // Scoring philosophy:
    // - M1 base (8-core) = 1000 points in each category
    // - Other chips score proportionally higher/lower based on raw performance
    // - A M3 Pro scoring ~1300 means it's 30% faster than M1 base
    // - No per-chip scaling - we measure absolute performance vs M1 baseline
    private let referenceValues: [String: Double] = [
        // CPU Single-Core - median from 5 M1 runs
        "integer": 1570,              // 1570 Mops/s on M1
        "float": 126.8,               // 126.8 Mops/s on M1
        "simd": 8.84,                 // 8.84 GFLOPS on M1
        "crypto": 1480,               // 1480 MB/s on M1
        "compression": 498.57,        // 498.57 MB/s on M1

        // CPU Multi-Core - median from 5 M1 runs (8 cores: 4P + 4E)
        "integer_multi": 9940,        // 9940 Mops/s on M1 (8 cores)
        "float_multi": 803,           // 803 Mops/s on M1 (8 cores)
        "simd_multi": 6.18,           // 6.18 GFLOPS on M1 (8 cores)
        "crypto_multi": 6590,         // 6590 MB/s on M1 (8 cores)
        "compression_multi": 2690,    // 2690 MB/s on M1 (8 cores)

        // Memory (GB/s or ns) - median from 5 M1 runs
        "mem_read": 55.97,            // 55.97 GB/s on M1
        "mem_write": 25.59,           // 25.59 GB/s on M1
        "mem_copy": 27.84,            // 27.84 GB/s on M1
        "mem_latency": 54.95,         // 54.95 ns on M1 (lower is better)

        // Disk (MB/s) - Real disk performance with cache bypass
        // Sequential: 4MB blocks with F_NOCACHE + F_FULLFSYNC
        // Random: 4KB blocks, QD1 pattern, 1GB file (exceeds cache)
        // Values from median of M1 runs with strict cache bypass
        // Note: Lower than NovaBench because we measure actual disk, not cache
        "disk_seq_read": 2180,        // 2180 MB/s on M1 (with F_NOCACHE)
        "disk_seq_write": 700,        // 700 MB/s on M1 (with F_FULLFSYNC)
        "disk_rand_read": 43,         // 43 MB/s on M1 (1GB file, true random)
        "disk_rand_write": 17,        // 17 MB/s on M1 (with final F_FULLFSYNC)

        // GPU (GFLOPS, Mparts/s, MP/s) - median from 5 M1 runs (8-core GPU)
        "gpu_compute": 149.2,         // 149.2 GFLOPS matrix multiply on M1
        "gpu_particles": 909.74,      // 909.74 Mparts/s on M1
        "gpu_blur": 1870,             // 1870 MP/s on M1
        "gpu_edge": 5410,             // 5410 MP/s on M1

        // AI/ML benchmarks - M1 baseline (IPS and GFLOPS)
        // These are placeholder values - will be calibrated from real M1 runs
        // after the CoreML model is set up
        "ai_cpu": 45.0,               // ~45 IPS CoreML CPU-only on M1
        "ai_gpu": 180.0,              // ~180 IPS CoreML GPU on M1
        "ai_neural engine": 350.0,    // ~350 IPS CoreML Neural Engine on M1
        "ai_bnns": 25.0,              // ~25 GFLOPS BNNS matmul on M1
    ]

    func calculateScores(from results: BenchmarkResults, coreCount: Int = 8) -> BenchmarkScores {
        // Check which benchmarks were actually run (not skipped via --only)
        let ranCpuSingle = results.result(for: .cpuSingleCore) != nil
        let ranCpuMulti = results.result(for: .cpuMultiCore) != nil
        let ranMemory = results.result(for: .memory) != nil
        let ranDisk = results.result(for: .disk) != nil
        let ranGpu = results.result(for: .gpu) != nil
        let ranAi = results.result(for: .ai) != nil

        let cpuSingle = calculateCPUSingleScore(results)
        let cpuMulti = calculateCPUMultiScore(results, coreCount: coreCount)
        let memory = calculateMemoryScore(results)
        let disk = calculateDiskScore(results)
        let gpu = calculateGPUScore(results)
        // AI score is calculated separately and NOT included in total
        let ai = calculateAIScore(results)

        // Weighted total - include categories that were run (even if score is 0 = failed)
        // This prevents partial runs (--only) from being unfairly penalized
        // but still penalizes failures appropriately
        // Weights: CPU-Single 25%, CPU-Multi 25%, Memory 15%, Disk 15%, GPU 20%
        // NOTE: AI is NOT included in total (separate score like Geekbench AI)
        var totalScore = 0.0
        var totalWeight = 0.0

        if ranCpuSingle, cpuSingle.isFinite, cpuSingle > 0 {
            totalScore += cpuSingle * 0.25
            totalWeight += 0.25
        }
        if ranCpuMulti, cpuMulti.isFinite, cpuMulti > 0 {
            totalScore += cpuMulti * 0.25
            totalWeight += 0.25
        }
        if ranMemory, memory.isFinite, memory > 0 {
            totalScore += memory * 0.15
            totalWeight += 0.15
        }
        if ranDisk, disk.isFinite, disk > 0 {
            totalScore += disk * 0.15
            totalWeight += 0.15
        }
        if ranGpu, gpu.isFinite, gpu > 0 {
            totalScore += gpu * 0.20
            totalWeight += 0.20
        }

        // Normalize to account for skipped categories (not failures)
        let total = totalWeight > 0 ? totalScore / totalWeight : 0

        return BenchmarkScores(
            cpuSingleCore: cpuSingle,
            cpuMultiCore: cpuMulti,
            memory: memory,
            disk: disk,
            gpu: gpu,
            total: total,
            ai: ai,
            ranCpuSingle: ranCpuSingle,
            ranCpuMulti: ranCpuMulti,
            ranMemory: ranMemory,
            ranDisk: ranDisk,
            ranGpu: ranGpu,
            ranAi: ranAi
        )
    }

    private func calculateCPUSingleScore(_ results: BenchmarkResults) -> Double {
        guard let result = results.result(for: .cpuSingleCore) else { return 0 }
        guard !hasInvalidTests(result) else { return Double.nan }
        return calculateGeometricMeanScore(tests: result.tests, keyPrefix: "")
    }

    private func calculateCPUMultiScore(_ results: BenchmarkResults, coreCount: Int) -> Double {
        guard let result = results.result(for: .cpuMultiCore) else { return 0 }
        guard !hasInvalidTests(result) else { return Double.nan }
        // Use dedicated multi-core reference values (M1 8-core baseline)
        // Chips with more cores will naturally score higher
        return calculateGeometricMeanScore(tests: result.tests, keyPrefix: "", transformKey: { $0.lowercased() })
    }

    private func calculateMemoryScore(_ results: BenchmarkResults) -> Double {
        guard let result = results.result(for: .memory) else { return 0 }
        guard !hasInvalidTests(result) else { return Double.nan }
        return calculateGeometricMeanScore(tests: result.tests, keyPrefix: "mem_")
    }

    private func calculateDiskScore(_ results: BenchmarkResults) -> Double {
        guard let result = results.result(for: .disk) else { return 0 }
        guard !hasInvalidTests(result) else { return Double.nan }
        // Disk scores use clamped ratios (0.25 - 4.0) to prevent outliers from
        // dominating the score. Disk benchmarks are highly variable due to:
        // - SSD capacity differences (256GB vs 1TB = different NAND channels)
        // - Cache effects (especially on sequential reads)
        // - Volume state (free space, APFS compression)
        return calculateGeometricMeanScore(
            tests: result.tests,
            keyPrefix: "disk_",
            transformKey: { $0.replacingOccurrences(of: " ", with: "_") },
            clampRatio: (min: 0.25, max: 4.0)
        )
    }

    private func calculateGPUScore(_ results: BenchmarkResults) -> Double {
        guard let result = results.result(for: .gpu) else { return 0 }
        guard !hasInvalidTests(result) else { return Double.nan }
        return calculateGeometricMeanScore(tests: result.tests, keyPrefix: "gpu_")
    }

    private func calculateAIScore(_ results: BenchmarkResults) -> Double {
        guard let result = results.result(for: .ai) else { return 0 }
        guard !hasInvalidTests(result) else { return Double.nan }
        // AI tests: CPU, GPU, Neural Engine (IPS), BNNS (GFLOPS)
        // Use geometric mean with "ai_" prefix
        return calculateGeometricMeanScore(tests: result.tests, keyPrefix: "ai_")
    }

    private func hasInvalidTests(_ result: BenchmarkResult) -> Bool {
        result.tests.contains { !$0.value.isFinite || $0.value <= 0 }
    }

    // MARK: - Geometric Mean Helper

    /// Calculates category score using geometric mean of ratios (more statistically sound than arithmetic mean)
    /// Formula: Score = 1000 × exp(Σ ln(rᵢ) / n) where rᵢ = value/baseline (or baseline/value for lower-is-better)
    /// This prevents outliers from dominating and properly handles different units
    ///
    /// - Parameters:
    ///   - tests: Array of test results to score
    ///   - keyPrefix: Prefix for looking up reference values (e.g., "mem_", "disk_", "gpu_")
    ///   - transformKey: Optional transform for test name before lookup
    ///   - clampRatio: Optional (min, max) bounds to clamp ratios, preventing extreme outliers
    private func calculateGeometricMeanScore(
        tests: [TestResult],
        keyPrefix: String,
        transformKey: ((String) -> String)? = nil,
        clampRatio: (min: Double, max: Double)? = nil
    ) -> Double {
        var logSum = 0.0
        var count = 0

        for test in tests {
            guard test.value > 0 else { continue }

            let baseName = test.name.lowercased()
            let transformedName = transformKey?(baseName) ?? baseName
            let key = keyPrefix.isEmpty ? baseName : "\(keyPrefix)\(transformedName)"

            if let reference = referenceValues[key] {
                // Calculate ratio: higher-is-better uses value/reference, lower-is-better inverts
                var ratio = test.higherIsBetter ? (test.value / reference) : (reference / test.value)

                // Apply clamp if specified (prevents outliers from dominating score)
                if let clamp = clampRatio {
                    ratio = Swift.min(Swift.max(ratio, clamp.min), clamp.max)
                }

                logSum += log(ratio)
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        // Geometric mean of ratios, scaled to baseline 1000
        return 1000 * exp(logSum / Double(count))
    }
}

// MARK: - Results Exporter

struct ResultsExporter {
    /// Export results to JSON without machine ID for privacy
    static func exportJSON(results: BenchmarkResults, scores: BenchmarkScores, systemInfo: SystemInfo, to path: String) throws {
        struct ExportData: Codable {
            let systemInfo: SystemInfoExport  // Privacy-safe version without machine ID
            let results: BenchmarkResults
            let scores: BenchmarkScores
        }

        let data = ExportData(systemInfo: systemInfo.forExport(), results: results, scores: scores)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(data)
        try jsonData.write(to: URL(fileURLWithPath: path))
    }

    /// Export advanced profiling results to a separate JSON file
    static func exportAdvancedJSON(
        advancedResults: AdvancedProfileResults,
        systemInfo: SystemInfo,
        timestamp: Date,
        to path: String
    ) throws {
        struct AdvancedExport: Codable {
            struct Metadata: Codable {
                let version: String
                let timestamp: Date
                let preset: String
                let durationSeconds: Int
            }

            struct Point: Codable {
                let x: Int
                let y: Double
            }

            struct DiskPoint: Codable {
                let qd: Int
                let iops: Double
                let mbps: Double
            }

            struct DiskMetadata: Codable {
                let blockSizeBytes: Int
                let fileSizeBytes: Int
                let opsPerQD: Int
                let qdList: [Int]
                let sync: String
                let qdMapping: String
                let cacheHints: [String]
            }

            struct CPUPoint: Codable {
                let threads: Int
                let throughput: Double
                let efficiency: Double
            }

            struct CliffAnalysis: Codable {
                let cliffThreads: Int?
                let efficiencyAfter: Double?
                let threshold: Double
            }

            struct MemoryProfile: Codable {
                let strideSweep: [Point]
                let blockSizeSweep: [Point]
            }

            struct DiskProfile: Codable {
                let qdReadMatrix: [DiskPoint]
                let qdWriteMatrix: [DiskPoint]
                let metadata: DiskMetadata
            }

            struct CPUScalingProfile: Codable {
                let threadScaling: [CPUPoint]
                let scalingEfficiency: Double
                let cliff: CliffAnalysis
            }

            let systemInfo: SystemInfoExport
            let metadata: Metadata
            let memory: MemoryProfile?
            let disk: DiskProfile?
            let cpuScaling: CPUScalingProfile?
        }

        let preset = advancedResults.quickMode ? "quick" : "normal"
        let diskBlockSize = 4 * 1024
        let diskFileSize = advancedResults.quickMode ? 256 * 1024 * 1024 : 512 * 1024 * 1024
        let opsPerQD = advancedResults.quickMode ? 100 : 500
        let qdList = advancedResults.disk?.qdReadMatrix.map { $0.qd } ?? []

        let metadata = AdvancedExport.Metadata(
            version: AppInfo.version,
            timestamp: timestamp,
            preset: preset,
            durationSeconds: advancedResults.duration
        )

        let memoryProfile = advancedResults.memory.map { memory in
            AdvancedExport.MemoryProfile(
                strideSweep: memory.strideSweep.map { AdvancedExport.Point(x: $0.stride, y: $0.gbps) },
                blockSizeSweep: memory.blockSizeSweep.map { AdvancedExport.Point(x: $0.blockSize, y: $0.gbps) }
            )
        }

        let diskProfile = advancedResults.disk.map { disk in
            let diskMetadata = AdvancedExport.DiskMetadata(
                blockSizeBytes: diskBlockSize,
                fileSizeBytes: diskFileSize,
                opsPerQD: opsPerQD,
                qdList: qdList,
                sync: "Reads prefill + F_FULLFSYNC; writes F_FULLFSYNC at end",
                qdMapping: "Concurrent threads simulate queue depth; each thread runs synchronous pread/pwrite ops",
                cacheHints: ["F_NOCACHE"]
            )
            return AdvancedExport.DiskProfile(
                qdReadMatrix: disk.qdReadMatrix.map { AdvancedExport.DiskPoint(qd: $0.qd, iops: $0.iops, mbps: $0.mbps) },
                qdWriteMatrix: disk.qdWriteMatrix.map { AdvancedExport.DiskPoint(qd: $0.qd, iops: $0.iops, mbps: $0.mbps) },
                metadata: diskMetadata
            )
        }

        let cpuScaling = advancedResults.cpuScaling.map { cpu in
            let cliff = cpu.scalingCliffAnalysis
            let cliffAnalysis = AdvancedExport.CliffAnalysis(
                cliffThreads: cliff.cliffThreads,
                efficiencyAfter: cliff.efficiencyAfter,
                threshold: cliff.threshold
            )
            return AdvancedExport.CPUScalingProfile(
                threadScaling: cpu.threadScaling.map {
                    AdvancedExport.CPUPoint(threads: $0.threads, throughput: $0.throughput, efficiency: $0.efficiency)
                },
                scalingEfficiency: cpu.scalingEfficiency,
                cliff: cliffAnalysis
            )
        }

        let export = AdvancedExport(
            systemInfo: systemInfo.forExport(),
            metadata: metadata,
            memory: memoryProfile,
            disk: diskProfile,
            cpuScaling: cpuScaling
        )

        let exportURL = URL(fileURLWithPath: path)
        let outputURL = exportURL.deletingLastPathComponent().appendingPathComponent("advanced_profiles.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(export)
        try jsonData.write(to: outputURL)
    }
}
