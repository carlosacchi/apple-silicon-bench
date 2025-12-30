import ArgumentParser
import Foundation

@main
struct OSXBench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "osx-bench",
        abstract: "Benchmark tool for Apple Silicon Macs",
        version: AppInfo.version,
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

    @Flag(name: .long, help: "Quick mode with reduced iterations")
    var quick: Bool = false

    @Option(name: .long, help: "Export results to JSON file")
    var export: String?

    func run() async throws {
        let systemInfo = try SystemInfo.gather()

        print("""

        ╔═══════════════════════════════════════════════════════════════╗
        ║                 \(AppInfo.fullName.uppercased()) v\(AppInfo.version)                   ║
        ║              Benchmark Tool for Apple Silicon                 ║
        ╚═══════════════════════════════════════════════════════════════╝

        """)

        systemInfo.printSummary()
        print()

        let runner = BenchmarkRunner(
            systemInfo: systemInfo,
            quickMode: quick,
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
