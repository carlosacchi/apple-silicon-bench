import Foundation

// MARK: - Benchmark Types

enum BenchmarkType: String, CaseIterable, Codable {
    case cpuSingleCore = "cpu-single"
    case cpuMultiCore = "cpu-multi"
    case memory = "memory"
    case disk = "disk"

    var displayName: String {
        switch self {
        case .cpuSingleCore: return "CPU Single-Core"
        case .cpuMultiCore: return "CPU Multi-Core"
        case .memory: return "Memory"
        case .disk: return "Disk"
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
    let total: Double

    func printSummary(quickMode: Bool = false, partialRun: Bool = false) {
        let line = String(repeating: "─", count: 44)
        print(line)
        print("  BENCHMARK SCORES")
        print(line)
        if cpuSingleCore > 0 { print(dotPad("CPU Single-Core", Int(cpuSingleCore))) }
        if cpuMultiCore > 0 { print(dotPad("CPU Multi-Core", Int(cpuMultiCore))) }
        if memory > 0 { print(dotPad("Memory", Int(memory))) }
        if disk > 0 { print(dotPad("Disk", Int(disk))) }
        print(line)
        print(dotPad("TOTAL SCORE", Int(total)))
        print(line)

        // Print notes about scoring accuracy
        if quickMode {
            print("  ⚠️  Quick mode: scores may be less accurate")
        }
        if partialRun {
            print("  ℹ️  Partial run: total based on selected tests")
        }
    }

    private func dotPad(_ label: String, _ value: Int) -> String {
        let valueStr = String(value)
        let prefix = "  \(label) "
        let suffix = " \(valueStr)"
        let dotsCount = max(2, 44 - prefix.count - suffix.count)
        return prefix + String(repeating: ".", count: dotsCount) + suffix
    }
}

// MARK: - Scorer

struct BenchmarkScorer {
    // Reference values (baseline = M1 base chip = 1000 points per category)
    // Units MUST match the benchmark output units exactly
    private let referenceValues: [String: Double] = [
        // CPU Single - units match benchmark output
        "integer": 500,               // 500 Mops/s
        "float": 200,                 // 200 Mops/s
        "simd": 50,                   // 50 GFLOPS
        "crypto": 2000,               // 2000 MB/s (~2 GB/s)
        "compression": 500,           // 500 MB/s

        // Memory (GB/s or ns)
        "mem_read": 60,               // 60 GB/s
        "mem_write": 50,              // 50 GB/s
        "mem_copy": 40,               // 40 GB/s
        "mem_latency": 100,           // 100 ns (lower is better)

        // Disk (MB/s or IOPS)
        "disk_seq_read": 3000,        // 3000 MB/s
        "disk_seq_write": 2500,       // 2500 MB/s
        "disk_rand_read": 300000,     // 300K IOPS
        "disk_rand_write": 250000,    // 250K IOPS
    ]

    func calculateScores(from results: BenchmarkResults) -> BenchmarkScores {
        let cpuSingle = calculateCPUSingleScore(results)
        let cpuMulti = calculateCPUMultiScore(results)
        let memory = calculateMemoryScore(results)
        let disk = calculateDiskScore(results)

        // Weighted total - only include categories that were actually run
        // This prevents partial runs (--only) from being unfairly penalized
        var totalScore = 0.0
        var totalWeight = 0.0

        if cpuSingle > 0 {
            totalScore += cpuSingle * 0.3
            totalWeight += 0.3
        }
        if cpuMulti > 0 {
            totalScore += cpuMulti * 0.3
            totalWeight += 0.3
        }
        if memory > 0 {
            totalScore += memory * 0.2
            totalWeight += 0.2
        }
        if disk > 0 {
            totalScore += disk * 0.2
            totalWeight += 0.2
        }

        // Normalize to account for missing categories
        let total = totalWeight > 0 ? totalScore / totalWeight : 0

        return BenchmarkScores(
            cpuSingleCore: cpuSingle,
            cpuMultiCore: cpuMulti,
            memory: memory,
            disk: disk,
            total: total
        )
    }

    private func calculateCPUSingleScore(_ results: BenchmarkResults) -> Double {
        guard let result = results.result(for: .cpuSingleCore) else { return 0 }

        var score = 0.0
        var count = 0

        for test in result.tests {
            // Skip failed tests (value <= 0) to avoid dragging down the average
            guard test.value > 0 else { continue }
            if let reference = referenceValues[test.name.lowercased()] {
                score += (test.value / reference) * 1000
                count += 1
            }
        }

        return count > 0 ? score / Double(count) : 0
    }

    private func calculateCPUMultiScore(_ results: BenchmarkResults) -> Double {
        guard let result = results.result(for: .cpuMultiCore) else { return 0 }

        var score = 0.0
        var count = 0

        for test in result.tests {
            // Skip failed tests (value <= 0) to avoid dragging down the average
            guard test.value > 0 else { continue }
            let baseName = test.name.lowercased().replacingOccurrences(of: "_multi", with: "")
            if let reference = referenceValues[baseName] {
                // Multi-core reference is 8x single-core (for M1 8-core)
                score += (test.value / (reference * 8)) * 1000
                count += 1
            }
        }

        return count > 0 ? score / Double(count) : 0
    }

    private func calculateMemoryScore(_ results: BenchmarkResults) -> Double {
        guard let result = results.result(for: .memory) else { return 0 }

        var score = 0.0
        var count = 0

        for test in result.tests {
            // Skip failed tests (value <= 0) to avoid dragging down the average
            guard test.value > 0 else { continue }
            let key = "mem_\(test.name.lowercased())"
            if let reference = referenceValues[key] {
                if test.higherIsBetter {
                    score += (test.value / reference) * 1000
                } else {
                    // Lower is better (latency)
                    score += (reference / test.value) * 1000
                }
                count += 1
            }
        }

        return count > 0 ? score / Double(count) : 0
    }

    private func calculateDiskScore(_ results: BenchmarkResults) -> Double {
        guard let result = results.result(for: .disk) else { return 0 }

        var score = 0.0
        var count = 0

        for test in result.tests {
            // Skip failed tests (value <= 0) to avoid dragging down the average
            guard test.value > 0 else { continue }
            let key = "disk_\(test.name.lowercased().replacingOccurrences(of: " ", with: "_"))"
            if let reference = referenceValues[key] {
                score += (test.value / reference) * 1000
                count += 1
            }
        }

        return count > 0 ? score / Double(count) : 0
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
}
