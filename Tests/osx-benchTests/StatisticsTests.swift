import Testing
@testable import osx_bench

@Suite("LatencyStats")
struct LatencyStatsTests {
    @Test func test_latencyStats_emptySamples_returnsNil() {
        #expect(LatencyStats(samples: []) == nil)
    }

    @Test func test_latencyStats_singleSample_hasZeroStdDev() throws {
        let stats = try #require(LatencyStats(samples: [2.5]))
        #expect(stats.mean == 2.5)
        #expect(stats.p50 == 2.5)
        #expect(stats.p95 == 2.5)
        #expect(stats.stdDev == 0)
    }

    @Test func test_latencyStats_unsortedSamples_computesPercentilesWithInterpolation() throws {
        // 1...100 shuffled: p50 = 50.5, p95 = 95.05 with linear interpolation
        let samples = (1...100).map(Double.init).shuffled()
        let stats = try #require(LatencyStats(samples: samples))
        #expect(stats.mean == 50.5)
        #expect(abs(stats.p50 - 50.5) < 1e-9)
        #expect(abs(stats.p95 - 95.05) < 1e-9)
    }

    @Test func test_latencyStats_stdDev_usesSampleVariance() throws {
        let stats = try #require(LatencyStats(samples: [2, 4, 4, 4, 5, 5, 7, 9]))
        // Sample variance = 32 / 7
        #expect(abs(stats.stdDev - (32.0 / 7.0).squareRoot()) < 1e-12)
    }
}

@Suite("VectorComparison")
struct VectorComparisonTests {
    @Test func test_cosineSimilarity_identicalVectors_isOne() throws {
        let value = try #require(VectorComparison.cosineSimilarity([1, 2, 3], [1, 2, 3]))
        #expect(abs(value - 1) < 1e-12)
    }

    @Test func test_cosineSimilarity_mismatchedLengthsOrZeroVector_isNil() {
        #expect(VectorComparison.cosineSimilarity([1, 2], [1, 2, 3]) == nil)
        #expect(VectorComparison.cosineSimilarity([0, 0], [1, 2]) == nil)
        #expect(VectorComparison.cosineSimilarity([], []) == nil)
    }

    @Test func test_argmax_returnsFirstMaximum() {
        #expect(VectorComparison.argmax([0.1, 0.7, 0.7, 0.2]) == 1)
        #expect(VectorComparison.argmax([]) == nil)
    }

    @Test func test_aiValidation_closeOutput_passes() {
        let reference = [0.01, 0.9, 0.09]
        let check = AIBenchmark.validate(output: [0.011, 0.895, 0.094], reference: reference)
        #expect(check.passed == true)
        #expect(check.message.contains("same top-1"))
    }

    @Test func test_aiValidation_differentOutput_fails() {
        let check = AIBenchmark.validate(output: [0.9, 0.01, 0.09], reference: [0.01, 0.9, 0.09])
        #expect(check.passed == false)
        #expect(check.message.contains("different top-1"))
    }

    @Test func test_aiValidation_shapeMismatchOrMissingOutput() {
        #expect(AIBenchmark.validate(output: [1, 2], reference: [1, 2, 3]).passed == false)
        #expect(AIBenchmark.validate(output: nil, reference: [1, 2, 3]).passed == nil)
    }
}
