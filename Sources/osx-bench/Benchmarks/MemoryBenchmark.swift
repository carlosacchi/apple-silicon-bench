import Foundation

struct MemoryBenchmark: Benchmark {
    let iterations: Int = 1  // Kept for protocol conformance
    let duration: Int  // Duration in seconds
    let quickMode: Bool

    static let dramLatencyTestName = "DRAM Latency"

    // Buffer size: 256 MB (larger than L3 cache to measure actual RAM)
    private let bufferSize = 256 * 1024 * 1024

    /// Maximum percentage of physical memory we're willing to use
    private let maxMemoryUsagePercent: Double = 0.25  // 25% of RAM

    init(duration: Int, quickMode: Bool = false) {
        self.duration = duration
        self.quickMode = quickMode
    }

    /// Check if we have enough memory for the benchmark
    private func validateMemoryAvailable(required: Int) -> Bool {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let maxAllowed = UInt64(Double(physicalMemory) * maxMemoryUsagePercent)
        return UInt64(required) <= maxAllowed
    }

    func run() async throws -> [TestResult] {
        var results: [TestResult] = []
        let testDuration = Double(duration) / 4.0  // Divide duration among 4 tests

        // Sequential Read
        let readResult = measureForDuration(seconds: testDuration) {
            runReadTest()
        }
        results.append(TestResult(name: "Read", value: readResult, unit: "GB/s"))

        // Sequential Write
        let writeResult = measureForDuration(seconds: testDuration) {
            runWriteTest()
        }
        results.append(TestResult(name: "Write", value: writeResult, unit: "GB/s"))

        // Copy
        let copyResult = measureForDuration(seconds: testDuration) {
            runCopyTest()
        }
        results.append(TestResult(name: "Copy", value: copyResult, unit: "GB/s"))

        // Latency
        let latencyResult = measureForDuration(seconds: testDuration) {
            runLatencyTest()
        }
        results.append(TestResult(name: "Latency", value: latencyResult, unit: "ns", higherIsBetter: false))

        // Informational: latency of a working set far larger than any cache (not scored yet).
        // Fixed passes instead of a share of the duration, so the scored tests keep their timing
        results.append(runDRAMLatencyTest(passes: quickMode ? 2 : 5))

        return results
    }

    /// Run operation repeatedly for the specified duration, returning averaged result
    private func measureForDuration(seconds: Double, operation: () -> Double) -> Double {
        // Warmup run
        _ = operation()

        var total = 0.0
        var count = 0
        let endTime = CFAbsoluteTimeGetCurrent() + seconds

        while CFAbsoluteTimeGetCurrent() < endTime {
            total += operation()
            count += 1
        }

        return count > 0 ? total / Double(count) : 0
    }

    // MARK: - Read Test
    private func runReadTest() -> Double {
        // Validate we have enough memory
        guard validateMemoryAvailable(required: bufferSize) else { return 0 }

        let count = bufferSize / MemoryLayout<UInt64>.size

        // Allocate page-aligned memory using UnsafeMutableRawPointer
        var rawBuffer: UnsafeMutableRawPointer?
        guard posix_memalign(&rawBuffer, 16384, bufferSize) == 0,
              let raw = rawBuffer else { return 0 }
        defer { free(raw) }

        let ptr = raw.bindMemory(to: UInt64.self, capacity: count)

        // Initialize to avoid copy-on-write
        memset(raw, 0x5A, bufferSize)

        // Force memory to be resident (continue even if mlock fails - just less accurate)
        let mlockSuccess = mlock(raw, bufferSize) == 0
        defer { if mlockSuccess { munlock(raw, bufferSize) } }

        var sum: UInt64 = 0

        let start = CFAbsoluteTimeGetCurrent()

        // Sequential read with unrolling for better throughput
        for i in stride(from: 0, to: count, by: 8) {
            sum = sum &+ ptr[i]
            sum = sum &+ ptr[i + 1]
            sum = sum &+ ptr[i + 2]
            sum = sum &+ ptr[i + 3]
            sum = sum &+ ptr[i + 4]
            sum = sum &+ ptr[i + 5]
            sum = sum &+ ptr[i + 6]
            sum = sum &+ ptr[i + 7]
        }

        let duration = CFAbsoluteTimeGetCurrent() - start

        // Prevent optimization
        if sum == UInt64.max { print("") }

        // GB/s
        return Double(bufferSize) / duration / (1024 * 1024 * 1024)
    }

    // MARK: - Write Test
    private func runWriteTest() -> Double {
        // Validate we have enough memory
        guard validateMemoryAvailable(required: bufferSize) else { return 0 }

        let count = bufferSize / MemoryLayout<UInt64>.size

        var rawBuffer: UnsafeMutableRawPointer?
        guard posix_memalign(&rawBuffer, 16384, bufferSize) == 0,
              let raw = rawBuffer else { return 0 }
        defer { free(raw) }

        let ptr = raw.bindMemory(to: UInt64.self, capacity: count)

        let mlockSuccess = mlock(raw, bufferSize) == 0
        defer { if mlockSuccess { munlock(raw, bufferSize) } }

        let start = CFAbsoluteTimeGetCurrent()

        // Sequential write with unrolling
        for i in stride(from: 0, to: count, by: 8) {
            ptr[i] = UInt64(i)
            ptr[i + 1] = UInt64(i + 1)
            ptr[i + 2] = UInt64(i + 2)
            ptr[i + 3] = UInt64(i + 3)
            ptr[i + 4] = UInt64(i + 4)
            ptr[i + 5] = UInt64(i + 5)
            ptr[i + 6] = UInt64(i + 6)
            ptr[i + 7] = UInt64(i + 7)
        }

        // Memory barrier to ensure writes complete
        OSMemoryBarrier()

        let duration = CFAbsoluteTimeGetCurrent() - start

        return Double(bufferSize) / duration / (1024 * 1024 * 1024)
    }

    // MARK: - Copy Test
    private func runCopyTest() -> Double {
        // Validate we have enough memory (need 2x buffer for src + dst)
        guard validateMemoryAvailable(required: bufferSize * 2) else { return 0 }

        var srcBuffer: UnsafeMutableRawPointer?
        var dstBuffer: UnsafeMutableRawPointer?

        guard posix_memalign(&srcBuffer, 16384, bufferSize) == 0,
              let src = srcBuffer else { return 0 }

        guard posix_memalign(&dstBuffer, 16384, bufferSize) == 0,
              let dst = dstBuffer else {
            free(src)
            return 0
        }

        defer {
            free(src)
            free(dst)
        }

        // Initialize source
        memset(src, 0x5A, bufferSize)

        let srcLocked = mlock(src, bufferSize) == 0
        let dstLocked = mlock(dst, bufferSize) == 0
        defer {
            if srcLocked { munlock(src, bufferSize) }
            if dstLocked { munlock(dst, bufferSize) }
        }

        let start = CFAbsoluteTimeGetCurrent()

        memcpy(dst, src, bufferSize)

        OSMemoryBarrier()

        let duration = CFAbsoluteTimeGetCurrent() - start

        // GB/s (counting both read and write)
        return Double(bufferSize) / duration / (1024 * 1024 * 1024)
    }

    // MARK: - Latency Test (Random Access)
    // Scored since v1.x. The 32 MB buffer with one pointer per 8 bytes lets 16 consecutive
    // slots share a 128-byte cache line, so many accesses hit L2/SLC: the result depends on cache
    // size (M1 ~55 ns, M6 ~22 ns). See runDRAMLatencyTest for DRAM latency.
    private func runLatencyTest() -> Double {
        // Use smaller buffer that fits in L3 cache for latency measurement
        let latencyBufferSize = 32 * 1024 * 1024  // 32 MB
        let count = latencyBufferSize / MemoryLayout<Int>.size
        let accessCount = 10_000_000

        // Validate we have enough memory
        guard validateMemoryAvailable(required: latencyBufferSize) else { return 0 }

        var rawBuffer: UnsafeMutableRawPointer?
        guard posix_memalign(&rawBuffer, 16384, latencyBufferSize) == 0,
              let raw = rawBuffer else { return 0 }
        defer { free(raw) }

        let ptr = raw.bindMemory(to: Int.self, capacity: count)

        // Create pointer chase (each element points to random next element)
        var indices = Array(0..<count)
        indices.shuffle()

        // Build linked list
        for i in 0..<count - 1 {
            ptr[indices[i]] = indices[i + 1]
        }
        ptr[indices[count - 1]] = indices[0]

        let mlockSuccess = mlock(raw, latencyBufferSize) == 0
        defer { if mlockSuccess { munlock(raw, latencyBufferSize) } }

        var index = 0

        let start = CFAbsoluteTimeGetCurrent()

        // Pointer chase to measure true memory latency
        for _ in 0..<accessCount {
            index = ptr[index]
        }

        let duration = CFAbsoluteTimeGetCurrent() - start

        // Prevent optimization
        if index == Int.max { print("") }

        // Nanoseconds per access
        return (duration / Double(accessCount)) * 1_000_000_000
    }

    // MARK: - DRAM Latency Test (informational)

    /// 256 MB: far above the system level cache of every current chip
    static let dramLatencyBufferSize = 256 * 1024 * 1024
    private static let dramLatencyAccesses = 2_000_000

    /// Pointer chase over one slot per cache line in a single random cycle (Sattolo), so no two
    /// consecutive accesses share a line and no stride or pattern is there for a prefetcher.
    /// With 16 KB pages the 256 MB buffer is also beyond TLB reach, so page walks are included,
    /// as for any large random working set. Reports the median of `passes` passes.
    private func runDRAMLatencyTest(passes: Int) -> TestResult {
        let name = Self.dramLatencyTestName
        let bufferSize = Self.dramLatencyBufferSize
        guard validateMemoryAvailable(required: bufferSize) else {
            return .skipped(name: name, unit: "ns", reason: "Not enough memory for a 256 MB buffer", informational: true)
        }

        let lineSize = max(Self.cacheLineSize(), MemoryLayout<Int>.stride)
        let step = lineSize / MemoryLayout<Int>.stride  // Int slots per cache line
        let lines = bufferSize / lineSize

        var rawBuffer: UnsafeMutableRawPointer?
        guard posix_memalign(&rawBuffer, 16384, bufferSize) == 0, let raw = rawBuffer else {
            return .skipped(name: name, unit: "ns", reason: "Buffer allocation failed", informational: true)
        }
        defer { free(raw) }
        let ptr = raw.bindMemory(to: Int.self, capacity: bufferSize / MemoryLayout<Int>.stride)

        // Each line's first slot holds the slot index of the next line in the cycle
        let next = Self.randomCycle(count: lines)
        for line in 0..<lines {
            ptr[line * step] = next[line] * step
        }

        let mlockSuccess = mlock(raw, bufferSize) == 0
        defer { if mlockSuccess { munlock(raw, bufferSize) } }

        var index = 0
        // Warmup: page in the buffer and settle the TLB state
        for _ in 0..<(Self.dramLatencyAccesses / 4) {
            index = ptr[index]
        }

        var perPass: [Double] = []
        for _ in 0..<max(passes, 1) {
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<Self.dramLatencyAccesses {
                index = ptr[index]
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            perPass.append(elapsed / Double(Self.dramLatencyAccesses) * 1_000_000_000)
        }

        // Prevent optimization
        if index == Int.max { print("") }

        let median = LatencyStats(samples: perPass)?.p50 ?? 0
        var details = TestDetails(samples: perPass.count)
        details.note = "\(bufferSize / (1024 * 1024)) MB buffer, one access per \(lineSize)-byte line, "
            + "random cycle, median of \(perPass.count) passes; experimental, not scored"
        return TestResult(name: name, value: median, unit: "ns", higherIsBetter: false,
                          informational: true, details: details)
    }

    /// A random permutation that forms a single cycle through all `count` elements (Sattolo's
    /// algorithm): following `next` from any element visits every element once before returning
    static func randomCycle<G: RandomNumberGenerator>(count: Int, using generator: inout G) -> [Int] {
        var order = Array(0..<count)
        if count > 1 {
            for i in stride(from: count - 1, to: 0, by: -1) {
                let j = Int.random(in: 0..<i, using: &generator)
                order.swapAt(i, j)
            }
        }
        // order is a cyclic permutation in "next" form: element i is followed by order[i]
        return order
    }

    static func randomCycle(count: Int) -> [Int] {
        var generator = SystemRandomNumberGenerator()
        return randomCycle(count: count, using: &generator)
    }

    /// L1 data cache line size (128 bytes on Apple Silicon)
    private static func cacheLineSize() -> Int {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname("hw.cachelinesize", &value, &size, nil, 0) == 0, value > 0 else { return 128 }
        return value
    }
}
