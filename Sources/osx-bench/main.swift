import ArgumentParser
import Foundation

@main
struct OSXBench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "osx-bench",
        abstract: "Benchmark tool for Apple Silicon Macs",
        version: AppInfo.versionString,
        subcommands: [Run.self, Info.self],
        defaultSubcommand: Run.self
    )
}

// MARK: - Run Command
struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run benchmarks"
    )

    @Option(name: .long, help: "Run only specific benchmarks, comma-separated (cpu,cpu-single,cpu-multi,memory,disk,gpu,ai)")
    var only: String?

    @Flag(name: .long, help: "Quick mode with reduced iterations (~3s per test)")
    var quick: Bool = false

    @Option(name: [.customShort("d"), .long], help: "Duration in seconds for each test (default: 10)")
    var duration: Int?

    @Flag(name: .long, help: "Stress test mode with extended duration (~60s per test)")
    var stress: Bool = false

    @Option(name: .long, help: "Export results to JSON file")
    var export: String?

    @Option(name: .long, help: "Path to custom CoreML model for AI benchmark")
    var modelPath: String?

    @Flag(name: .long, help: "Skip AI benchmark if model not cached (no download)")
    var offline: Bool = false

    @Flag(name: [.customLong("autoaccept"), .long], help: "Auto-accept privacy policy (CI/non-interactive)")
    var autoAccept: Bool = false

    @Flag(name: .long, help: "Run advanced profiling (memory stride/block sweep, disk QD matrix, CPU scaling)")
    var advanced: Bool = false

    @Option(name: .long, help: "Run N complete benchmark passes and report median scores (default: 1)")
    var repeats: Int?

    func validate() throws {
        // Reject unknown --only values up front instead of silently ignoring them
        _ = try parseSelectedBenchmarks()

        if let repeats = repeats, repeats < 1 {
            throw ValidationError("--repeats must be at least 1.")
        }
    }

    func run() async throws {
        let selectedBenchmarks = try parseSelectedBenchmarks()

        // Check privacy policy consent on first run
        guard ConsentManager.ensureConsent(autoAccept: autoAccept) else {
            throw ExitCode.failure
        }

        let systemInfo = try SystemInfo.gather()

        let title = "\(AppInfo.fullName.uppercased()) v\(AppInfo.version)"
        let subtitle = "Benchmark Tool for Apple Silicon"
        let line = String(repeating: "═", count: 44)

        print()
        print(line)
        print("  \(title)")
        print("  \(subtitle)")
        print(line)
        print()

        systemInfo.printBrief()
        print()

        // Determine test duration
        let testDuration = calculateDuration()

        // Create model manager for AI benchmark
        let modelManager = ModelManager(customModelPath: modelPath, offlineMode: offline)

        let totalPasses = max(1, repeats ?? 1)
        let scorer = BenchmarkScorer()
        var allRuns: [(results: BenchmarkResults, scores: BenchmarkScores)] = []

        for pass in 1...totalPasses {
            if totalPasses > 1 {
                print("\n━━━ Pass \(pass) of \(totalPasses) ━━━")
            }

            let runner = BenchmarkRunner(
                systemInfo: systemInfo,
                quickMode: quick,
                duration: testDuration,
                selectedBenchmarks: selectedBenchmarks,
                modelManager: modelManager
            )

            let results = try await runner.runAll()
            let scores = scorer.calculateScores(from: results, coreCount: systemInfo.totalCores)
            allRuns.append((results: results, scores: scores))

            if totalPasses > 1 {
                print("  Pass \(pass) total: \(Int(scores.total))")
            }
        }

        // Pick the median run by total score
        let sortedRuns = allRuns.sorted { $0.scores.total < $1.scores.total }
        let medianIndex = sortedRuns.count / 2
        let results = sortedRuns[medianIndex].results
        let scores = sortedRuns[medianIndex].scores

        if totalPasses > 1 {
            let allTotals = sortedRuns.map { Int($0.scores.total) }
            print("\n━━━ Repeat Summary ━━━")
            print("  Scores: \(allTotals.map(String.init).joined(separator: ", "))")
            print("  Min: \(allTotals.first!) | Median: \(Int(scores.total)) | Max: \(allTotals.last!)")
        }

        // Run advanced profiling if requested
        var advancedResults: AdvancedProfileResults? = nil
        if advanced {
            print("\n▶ Running Advanced Profiling...")
            advancedResults = try await runAdvancedProfiles(systemInfo: systemInfo, duration: testDuration)
        }

        // Generate HTML report (uses median run)
        let reportGenerator = HTMLReportGenerator(
            systemInfo: systemInfo,
            results: results,
            scores: scores,
            advancedResults: advancedResults
        )
        let reportPath = try reportGenerator.generate()
        print("\n📊 Report saved to: \(reportPath)")

        // Export JSON if requested
        if let exportPath = export {
            try ResultsExporter.exportJSON(results: results, scores: scores, systemInfo: systemInfo, to: exportPath)
            print("📁 JSON exported to: \(exportPath)")
            if let advancedResults = advancedResults {
                try ResultsExporter.exportAdvancedJSON(
                    advancedResults: advancedResults,
                    systemInfo: systemInfo,
                    timestamp: results.timestamp,
                    to: exportPath
                )
                let exportURL = URL(fileURLWithPath: exportPath)
                let advancedPath = exportURL.deletingLastPathComponent().appendingPathComponent("advanced_profiles.json").path
                print("📁 Advanced JSON exported to: \(advancedPath)")
            }
        }

        // Print final scores
        print("\n")
        let isPartialRun = selectedBenchmarks != nil
        scores.printSummary(quickMode: quick, partialRun: isPartialRun)
        if totalPasses > 1 {
            print("  ℹ️  Median of \(totalPasses) passes")
        }
    }

    /// Accepted --only values (including aliases) and the benchmarks each one selects
    private static let benchmarkAliases: [(names: [String], types: [BenchmarkType])] = [
        (["cpu"], [.cpuSingleCore, .cpuMultiCore]),
        (["cpu-single", "cpusingle"], [.cpuSingleCore]),
        (["cpu-multi", "cpumulti"], [.cpuMultiCore]),
        (["memory", "ram"], [.memory]),
        (["disk", "storage"], [.disk]),
        (["gpu", "metal"], [.gpu]),
        (["ai", "ml", "neural", "coreml"], [.ai]),
    ]

    private func parseSelectedBenchmarks() throws -> Set<BenchmarkType>? {
        guard let only = only else { return nil }

        var selected = Set<BenchmarkType>()
        var invalid: [String] = []

        let validNames = Self.benchmarkAliases.map { $0.names[0] }.joined(separator: ", ")
        let names = only.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        guard !names.isEmpty else {
            throw ValidationError("--only requires at least one benchmark. Valid values: \(validNames)")
        }

        for name in names {
            if let match = Self.benchmarkAliases.first(where: { $0.names.contains(name) }) {
                selected.formUnion(match.types)
            } else {
                invalid.append(name)
            }
        }

        guard invalid.isEmpty else {
            let label = invalid.count == 1 ? "Invalid benchmark" : "Invalid benchmarks"
            throw ValidationError("\(label) for --only: \(invalid.joined(separator: ", ")). Valid values: \(validNames)")
        }
        return selected
    }

    private func calculateDuration() -> Int {
        // Priority: explicit duration > stress > quick > default
        if let duration = duration {
            return max(1, duration)
        } else if stress {
            return 60  // 1 minute per test
        } else if quick {
            return 3   // 3 seconds per test
        } else {
            return 10  // Default: 10 seconds per test
        }
    }

    private func runAdvancedProfiles(systemInfo: SystemInfo, duration: Int) async throws -> AdvancedProfileResults {
        // Memory Profile
        print("\n  Memory Profile")
        let memoryProfile = MemoryProfile(duration: duration, quickMode: quick)
        let memoryResult = try await memoryProfile.run()

        // Disk Profile
        print("\n  Disk Profile")
        let diskProfile = DiskProfile(duration: duration, quickMode: quick)
        let diskResult = try await diskProfile.run()

        // CPU Scaling Profile
        print("\n  CPU Scaling Profile")
        let cpuProfile = CPUScalingProfile(duration: duration, maxCores: systemInfo.totalCores, quickMode: quick)
        let cpuResult = try await cpuProfile.run()

        // Print summary
        printAdvancedSummary(memory: memoryResult, disk: diskResult, cpu: cpuResult)

        return AdvancedProfileResults(
            memory: memoryResult,
            disk: diskResult,
            cpuScaling: cpuResult,
            quickMode: quick,
            duration: duration
        )
    }

    private func printAdvancedSummary(memory: MemoryProfileResult, disk: DiskProfileResult, cpu: CPUScalingResult) {
        let line = String(repeating: "─", count: 50)

        print()
        print(line)
        print("  ADVANCED PROFILE SUMMARY")
        print(line)

        // Memory
        print("  Memory:")
        if let best = memory.strideSweep.first {
            print("    Peak stride throughput .... \(String(format: "%.1f", best.gbps)) GB/s @ \(best.stride)B")
        }
        if !memory.detectedCacheBoundaries.isEmpty {
            print("    Cache boundaries detected:")
            for boundary in memory.detectedCacheBoundaries {
                print("      • \(boundary)")
            }
        }

        // Disk
        print("  Disk:")
        print("    Optimal Read QD ........... \(disk.optimalReadQD)")
        print("    Optimal Write QD .......... \(disk.optimalWriteQD)")
        print("    Peak Read IOPS ............ \(String(format: "%.0f", disk.peakReadIOPS))")
        print("    Peak Write IOPS ........... \(String(format: "%.0f", disk.peakWriteIOPS))")

        // CPU
        print("  CPU Scaling:")
        print("    Scaling Efficiency ........ \(String(format: "%.1f", cpu.scalingEfficiency))%")
        let cliffAnalysis = cpu.scalingCliffAnalysis
        if let cliff = cliffAnalysis.cliffThreads, let efficiencyAfter = cliffAnalysis.efficiencyAfter {
            print("    Scaling cliff near ........ \(cliff) threads")
            print("    Efficiency after .......... \(String(format: "%.1f", efficiencyAfter))%")
        } else {
            print("    Scaling cliff ............. No significant cliff (threshold=\(String(format: "%.0f", cliffAnalysis.threshold))%)")
        }

        print(line)
    }
}

// MARK: - Info Command
struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show system information"
    )

    @Flag(name: .long, help: "Show extended system information (includes GPU, battery, disk details)")
    var extended: Bool = false

    @Flag(name: .long, help: "Show sensitive system information (includes Machine ID)")
    var sensitive: Bool = false

    func run() throws {
        let systemInfo = try SystemInfo.gather()
        
        if sensitive {
            systemInfo.printSensitive()
        } else if extended {
            systemInfo.printExtended()
        } else {
            // Default to brief mode
            systemInfo.printBrief()
        }
    }
}
