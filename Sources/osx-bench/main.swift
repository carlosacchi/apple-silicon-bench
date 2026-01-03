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

    @Option(name: .long, help: "Run only specific benchmarks (cpu-single,cpu-multi,memory,disk,gpu,ai)")
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

    @Flag(name: .long, help: "Run advanced profiling (memory stride/block sweep, disk QD matrix, CPU scaling)")
    var advanced: Bool = false

    func run() async throws {
        // Check privacy policy consent on first run
        guard ConsentManager.ensureConsent() else {
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

        let runner = BenchmarkRunner(
            systemInfo: systemInfo,
            quickMode: quick,
            duration: testDuration,
            selectedBenchmarks: parseSelectedBenchmarks(),
            modelManager: modelManager
        )

        let results = try await runner.runAll()

        // Run advanced profiling if requested
        var advancedResults: AdvancedProfileResults? = nil
        if advanced {
            print("\n▶ Running Advanced Profiling...")
            advancedResults = try await runAdvancedProfiles(systemInfo: systemInfo, duration: testDuration)
        }

        // Calculate scores (pass core count for proper multi-core normalization)
        let scorer = BenchmarkScorer()
        let scores = scorer.calculateScores(from: results, coreCount: systemInfo.totalCores)

        // Generate HTML report
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
        }

        // Print final scores
        print("\n")
        let isPartialRun = parseSelectedBenchmarks() != nil
        scores.printSummary(quickMode: quick, partialRun: isPartialRun)
    }

    private func parseSelectedBenchmarks() -> Set<BenchmarkType>? {
        guard let only = only else { return nil }
        let types = only.split(separator: ",").compactMap { name -> BenchmarkType? in
            switch name.lowercased().trimmingCharacters(in: .whitespaces) {
            case "cpu-single", "cpusingle": return .cpuSingleCore
            case "cpu-multi", "cpumulti": return .cpuMultiCore
            case "memory", "ram": return .memory
            case "disk", "storage": return .disk
            case "gpu", "metal": return .gpu
            case "ai", "ml", "neural", "coreml": return .ai
            default: return nil
            }
        }
        return types.isEmpty ? nil : Set(types)
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
            cpuScaling: cpuResult
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
        if let cliff = cpu.scalingCliff {
            print("    Scaling cliff at .......... \(cliff) threads")
        } else {
            print("    Scaling cliff ............. None detected")
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
