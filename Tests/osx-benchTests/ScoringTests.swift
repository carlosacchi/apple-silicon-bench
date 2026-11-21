import Foundation
import Testing
@testable import osx_bench

@Suite("BenchmarkScorer")
struct ScoringTests {
    private let scorer = BenchmarkScorer()

    private func scores(for type: BenchmarkType, _ tests: [TestResult]) -> BenchmarkScores {
        let result = BenchmarkResult(type: type, tests: tests, duration: 1)
        return scorer.calculateScores(from: BenchmarkResults(benchmarks: [result]))
    }

    @Test func test_aiScore_ignoresInformationalTests() {
        let scored = [
            TestResult(name: "Accelerate Matmul", value: 1, unit: "GFLOPS")
        ]
        // "CPU" has a reference value, so it would change the score if it were not filtered out
        let withInfo = scored + [
            TestResult(name: "CPU", value: 999_999, unit: "IPS", informational: true),
            .skipped(name: "Other", unit: "GFLOPS", reason: "not supported", informational: true)
        ]
        let base = scores(for: .ai, scored).ai
        #expect(base.isFinite && base > 0)
        #expect(scores(for: .ai, withInfo).ai == base)
    }

    @Test func test_aiScore_skippedScoredTest_isIncomplete() {
        let tests = [
            TestResult(name: "Accelerate Matmul", value: 500, unit: "GFLOPS"),
            .skipped(name: "Neural Engine", unit: "IPS", reason: "Model failed to load")
        ]
        #expect(scores(for: .ai, tests).ai.isNaN)
    }

    @Test func test_gpuScore_informationalBandwidthDoesNotChangeScore() {
        let scored = [
            TestResult(name: "Compute", value: 148.52, unit: "GFLOPS"),
            TestResult(name: "Particles", value: 1260.12, unit: "Mparts/s"),
            TestResult(name: "Blur", value: 1970.70, unit: "MP/s"),
            TestResult(name: "Edge", value: 6164.56, unit: "MP/s")
        ]
        let withBandwidth = scored + [
            .skipped(name: "Memory Bandwidth", unit: "GB/s", reason: "unavailable", informational: true)
        ]
        // M1 baseline values score exactly 1000
        #expect(abs(scores(for: .gpu, scored).gpu - 1000) < 1e-6)
        #expect(abs(scores(for: .gpu, withBandwidth).gpu - 1000) < 1e-6)
        #expect(abs(scores(for: .gpu, withBandwidth).total - 1000) < 1e-6)
    }

    @Test func test_cpuSingleScore_m1BaselineScores1000() {
        // v2.6.0 baselines; SIMD is the NEON kernel shared with the multi-core test
        let tests = [
            TestResult(name: "Integer", value: 1570, unit: "Mops/s"),
            TestResult(name: "Float", value: 126.8, unit: "Mops/s"),
            TestResult(name: "SIMD", value: 21.50, unit: "GFLOPS"),
            TestResult(name: "Crypto", value: 1480, unit: "MB/s"),
            TestResult(name: "Compression", value: 498.57, unit: "MB/s")
        ]
        #expect(abs(scores(for: .cpuSingleCore, tests).cpuSingleCore - 1000) < 1e-6)
    }

    @Test func test_memoryScore_informationalDRAMLatencyDoesNotChangeScore() {
        let scored = [
            TestResult(name: "Read", value: 55.97, unit: "GB/s"),
            TestResult(name: "Write", value: 25.59, unit: "GB/s"),
            TestResult(name: "Copy", value: 27.84, unit: "GB/s"),
            TestResult(name: "Latency", value: 54.95, unit: "ns", higherIsBetter: false)
        ]
        let withDRAM = scored + [
            TestResult(name: MemoryBenchmark.dramLatencyTestName, value: 500, unit: "ns",
                       higherIsBetter: false, informational: true)
        ]
        #expect(abs(scores(for: .memory, scored).memory - 1000) < 1e-6)
        #expect(abs(scores(for: .memory, withDRAM).memory - 1000) < 1e-6)
    }

    @Test func test_benchmarkResult_isIncomplete_onlyForScoredTests() {
        let info = BenchmarkResult(type: .gpu, tests: [
            TestResult(name: "Compute", value: 100, unit: "GFLOPS"),
            .skipped(name: "Memory Bandwidth", unit: "GB/s", reason: "x", informational: true)
        ], duration: 1)
        #expect(!info.isIncomplete)
        #expect(info.scoredTests.count == 1)

        let failed = BenchmarkResult(type: .gpu, tests: [
            TestResult(name: "Compute", value: 0, unit: "GFLOPS")
        ], duration: 1)
        #expect(failed.isIncomplete)
    }
}

@Suite("TestResult Codable")
struct TestResultCodableTests {
    @Test func test_decode_legacyJSONWithoutNewFields() throws {
        let json = #"{"name":"BNNS","value":25,"unit":"GFLOPS","higherIsBetter":true}"#
        let result = try JSONDecoder().decode(TestResult.self, from: Data(json.utf8))
        #expect(result.name == "BNNS")
        #expect(result.informational == false)
        #expect(result.skipReason == nil)
        #expect(result.details == nil)
    }

    @Test func test_roundTrip_preservesDetailsAndSkipReason() throws {
        var details = TestDetails(latencies: [0.001, 0.002, 0.003])
        details.computePlan = ["Neural Engine": 98, "CPU": 2]
        details.validationPassed = true
        let original = TestResult(name: "Neural Engine", value: 1200, unit: "IPS", details: details)
        let skipped = TestResult.skipped(name: "Tensor Matmul", unit: "GFLOPS", reason: "Requires macOS 26", informational: true)

        let data = try JSONEncoder().encode([original, skipped])
        let decoded = try JSONDecoder().decode([TestResult].self, from: data)

        #expect(decoded[0].details == details)
        #expect(decoded[0].details?.samples == 3)
        #expect(decoded[1].skipReason == "Requires macOS 26")
        #expect(decoded[1].informational)
    }

    @Test func test_computePlanSummary_sortsByCount() {
        let details = TestDetails(computePlan: ["CPU": 2, "Neural Engine": 98])
        #expect(details.computePlanSummary == "Neural Engine 98/100, CPU 2/100")
    }
}
