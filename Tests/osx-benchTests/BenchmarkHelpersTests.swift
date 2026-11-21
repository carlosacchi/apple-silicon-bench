import Testing
@testable import osx_bench

/// Deterministic generator so permutation tests are reproducible
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Memory DRAM latency cycle")
struct RandomCycleTests {
    @Test(arguments: [1, 2, 3, 17, 4096])
    func test_randomCycle_visitsEveryElementOnceBeforeReturning(count: Int) {
        var generator = SplitMix64(state: UInt64(count))
        let next = MemoryBenchmark.randomCycle(count: count, using: &generator)
        #expect(next.count == count)

        var visited = Set<Int>()
        var index = 0
        for _ in 0..<count {
            #expect(visited.insert(index).inserted)
            index = next[index]
        }
        #expect(visited.count == count)
        #expect(index == 0)
    }

    @Test func test_randomCycle_hasNoFixedPoints() {
        var generator = SplitMix64(state: 42)
        let next = MemoryBenchmark.randomCycle(count: 1000, using: &generator)
        #expect(next.indices.allSatisfy { next[$0] != $0 })
    }
}

@Suite("GPU helpers")
struct GPUHelperTests {
    private typealias Tile = GPUTensorMatmul.Tile

    private func run(_ tile: Tile, _ gflops: Double, passed: Bool) -> GPUTensorMatmul.TileRun {
        GPUTensorMatmul.TileRun(tile: tile, gflops: gflops, samples: [0.001], validation: (passed, "check"))
    }

    @Test func test_tensorBest_picksFastestValidatedTile() throws {
        let small = Tile(rows: 64, columns: 32, simdgroups: 4)
        let large = Tile(rows: 64, columns: 64, simdgroups: 4)
        let wrong = Tile(rows: 128, columns: 64, simdgroups: 4)
        let best = try #require(GPUTensorMatmul.best(of: [
            run(small, 1000, passed: true),
            run(large, 2000, passed: true),
            run(wrong, 9000, passed: false)  // fast but wrong output: never reported over a valid tile
        ]))
        #expect(best.tile == large)
    }

    @Test func test_tensorBest_noneValidated_reportsFastestSoTheFailureIsVisible() throws {
        let small = Tile(rows: 64, columns: 32, simdgroups: 4)
        let large = Tile(rows: 64, columns: 64, simdgroups: 4)
        let best = try #require(GPUTensorMatmul.best(of: [
            run(small, 1000, passed: false),
            run(large, 2000, passed: false)
        ]))
        #expect(best.tile == large)
        #expect(!best.validation.passed)
        #expect(GPUTensorMatmul.best(of: []) == nil)
    }

    @Test func test_tensorShaderSource_usesTileSizes() {
        let source = GPUTensorMatmul.shaderSource(for: Tile(rows: 128, columns: 64, simdgroups: 8))
        #expect(source.contains("matmul2d_descriptor(128, 64"))
        #expect(source.contains("execution_simdgroups<8>"))
        #expect(source.contains("tgid.y * 128"))
        #expect(source.contains("tgid.x * 64"))
    }

    @Test func test_gpuTimingMean_isTotalOverCount() {
        #expect(abs(GPUTiming.mean([0.001, 0.002, 0.003]) - 0.002) < 1e-15)
        #expect(GPUTiming.mean([]) == 0)
    }
}
