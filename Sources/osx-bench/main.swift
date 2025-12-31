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

    @Option(name: .long, help: "Run only specific benchmarks (cpu-single,cpu-multi,memory,disk)")
    var only: String?

    @Flag(name: .long, help: "Quick mode with reduced iterations (~3s per test)")
    var quick: Bool = false

    @Option(name: [.customShort("d"), .long], help: "Duration in seconds for each test (default: 10)")
    var duration: Int?

    @Flag(name: .long, help: "Stress test mode with extended duration (~60s per test)")
    var stress: Bool = false

    @Option(name: .long, help: "Export results to JSON file")
    var export: String?

    func run() async throws {
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

        systemInfo.printSummary()
        print()

        // Determine test duration
        let testDuration = calculateDuration()

        let runner = BenchmarkRunner(
            systemInfo: systemInfo,
            quickMode: quick,
            duration: testDuration,
            selectedBenchmarks: parseSelectedBenchmarks()
        )

        let results = try await runner.runAll()

        // Calculate scores
        let scorer = BenchmarkScorer()
        let scores = scorer.calculateScores(from: results)

        // Generate HTML report
        let reportGenerator = HTMLReportGenerator(systemInfo: systemInfo, results: results, scores: scores)
        let reportPath = try reportGenerator.generate()
        print("\n📊 Report saved to: \(reportPath)")

        // Export JSON if requested
        if let exportPath = export {
            try ResultsExporter.exportJSON(results: results, scores: scores, systemInfo: systemInfo, to: exportPath)
            print("📁 JSON exported to: \(exportPath)")
        }

        // Print final scores
        print("\n")
        scores.printSummary()
    }

    private func parseSelectedBenchmarks() -> Set<BenchmarkType>? {
        guard let only = only else { return nil }
        let types = only.split(separator: ",").compactMap { name -> BenchmarkType? in
            switch name.lowercased().trimmingCharacters(in: .whitespaces) {
            case "cpu-single", "cpusingle": return .cpuSingleCore
            case "cpu-multi", "cpumulti": return .cpuMultiCore
            case "memory", "ram": return .memory
            case "disk", "storage": return .disk
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
}

// MARK: - Info Command
struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show system information"
    )

    func run() throws {
        let systemInfo = try SystemInfo.gather()
        systemInfo.printDetailed()
    }
}
