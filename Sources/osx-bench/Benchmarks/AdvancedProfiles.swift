import Foundation
import Accelerate

// MARK: - Advanced Profiling Benchmarks
// These provide deeper analysis beyond standard benchmarks:
// - Memory Profile: stride sweep + block-size sweep (cache boundary detection)
// - Disk Profile: Queue Depth matrix (parallelism analysis)
// - CPU Scaling: thread sweep (scaling efficiency metric)

// MARK: - Memory Profile

struct MemoryProfile {
    let duration: Int
    let quickMode: Bool

    // Buffer size for sweep tests
    private var bufferSize: Int { quickMode ? 64 * 1024 * 1024 : 256 * 1024 * 1024 }

    init(duration: Int, quickMode: Bool = false) {
        self.duration = duration
        self.quickMode = quickMode
    }

    /// Run memory profiling tests
    func run() async throws -> MemoryProfileResult {
        print("    Running stride sweep...")
        let strideSweep = runStrideSweep()

        print("    Running block-size sweep...")
        let blockSweep = runBlockSizeSweep()

        return MemoryProfileResult(
            strideSweep: strideSweep,
            blockSizeSweep: blockSweep
        )
    }

    // MARK: - Stride Sweep
    /// Tests memory access with different strides to stress spatial locality
    /// Larger strides defeat cache prefetching
    private func runStrideSweep() -> [(stride: Int, gbps: Double)] {
        var results: [(stride: Int, gbps: Double)] = []

        // Strides: 8B (cache-friendly) to 4KB (page-crossing)
        let strides = quickMode
            ? [8, 64, 256, 1024, 4096]
            : [8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]

        let count = bufferSize / MemoryLayout<UInt64>.size

        for stride in strides {
            var rawBuffer: UnsafeMutableRawPointer?
            guard posix_memalign(&rawBuffer, 16384, bufferSize) == 0,
                  let raw = rawBuffer else { continue }
            defer { free(raw) }

            let ptr = raw.bindMemory(to: UInt64.self, capacity: count)
            memset(raw, 0x5A, bufferSize)

            let strideCount = stride / MemoryLayout<UInt64>.size
            let iterations = quickMode ? 5 : 10
            var totalGbps = 0.0

            for _ in 0..<iterations {
                var sum: UInt64 = 0
                let start = CFAbsoluteTimeGetCurrent()

                // Access with stride
                var i = 0
                var accessCount = 0
                while i < count {
                    sum = sum &+ ptr[i]
                    i += strideCount
                    accessCount += 1
                }

                let duration = CFAbsoluteTimeGetCurrent() - start
                let bytesAccessed = accessCount * MemoryLayout<UInt64>.size
                totalGbps += Double(bytesAccessed) / duration / (1024 * 1024 * 1024)

                // Prevent optimization
                if sum == UInt64.max { print("") }
            }

            results.append((stride: stride, gbps: totalGbps / Double(iterations)))
        }

        return results
    }

    // MARK: - Block-Size Sweep
    /// Tests memory copy with different block sizes to detect cache boundaries
    /// Performance cliff at L1→L2→L3→DRAM transitions
    private func runBlockSizeSweep() -> [(blockSize: Int, gbps: Double)] {
        var results: [(blockSize: Int, gbps: Double)] = []

        // Block sizes: 4KB to 128MB (covers L1/L2/L3/DRAM)
        let blockSizes = quickMode
            ? [4 * 1024, 32 * 1024, 256 * 1024, 4 * 1024 * 1024, 64 * 1024 * 1024]
            : [4 * 1024, 8 * 1024, 16 * 1024, 32 * 1024, 64 * 1024,
               128 * 1024, 256 * 1024, 512 * 1024, 1024 * 1024,
               4 * 1024 * 1024, 16 * 1024 * 1024, 64 * 1024 * 1024, 128 * 1024 * 1024]

        let minStepTime: Double = quickMode ? 0.2 : 0.3
        let minBytes: Int = quickMode ? 512 * 1024 * 1024 : 1024 * 1024 * 1024
        let measuredPasses = quickMode ? 3 : 5

        for blockSize in blockSizes {
            var srcBuffer: UnsafeMutableRawPointer?
            var dstBuffer: UnsafeMutableRawPointer?

            guard posix_memalign(&srcBuffer, 16384, blockSize) == 0,
                  let src = srcBuffer else { continue }
            guard posix_memalign(&dstBuffer, 16384, blockSize) == 0,
                  let dst = dstBuffer else {
                free(src)
                continue
            }
            defer {
                free(src)
                free(dst)
            }

            memset(src, 0x5A, blockSize)

            var totalGbps = 0.0

            // Warm-up (not measured) to stabilize caches/timing
            memcpy(dst, src, blockSize)
            OSMemoryBarrier()

            for _ in 0..<measuredPasses {
                let (bytesCopied, elapsed) = measureAdaptiveCopy(
                    src: src,
                    dst: dst,
                    blockSize: blockSize,
                    minStepTime: minStepTime,
                    minBytes: minBytes
                )
                guard elapsed > 0 else { continue }
                totalGbps += Double(bytesCopied) / elapsed / (1024 * 1024 * 1024)
            }

            results.append((blockSize: blockSize, gbps: totalGbps / Double(measuredPasses)))
        }

        return results
    }

    private func measureAdaptiveCopy(
        src: UnsafeMutableRawPointer,
        dst: UnsafeMutableRawPointer,
        blockSize: Int,
        minStepTime: Double,
        minBytes: Int
    ) -> (bytesCopied: Int, elapsed: Double) {
        var bytesCopied = 0
        let start = CFAbsoluteTimeGetCurrent()
        var elapsed = 0.0

        repeat {
            memcpy(dst, src, blockSize)
            OSMemoryBarrier()
            bytesCopied += blockSize
            elapsed = CFAbsoluteTimeGetCurrent() - start
        } while elapsed < minStepTime || bytesCopied < minBytes

        return (bytesCopied, elapsed)
    }
}

// MARK: - Disk Profile

struct DiskProfile {
    let duration: Int
    let quickMode: Bool
    private let testDir: URL

    init(duration: Int, quickMode: Bool = false) {
        self.duration = duration
        self.quickMode = quickMode
        self.testDir = FileManager.default.temporaryDirectory.appendingPathComponent("osx-bench-disk-profile-\(UUID().uuidString)")
    }

    /// Run disk profiling tests (Queue Depth matrix)
    func run() async throws -> DiskProfileResult {
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        print("    Running QD matrix (read)...")
        let readMatrix = try runQDMatrix(isRead: true)

        print("    Running QD matrix (write)...")
        let writeMatrix = try runQDMatrix(isRead: false)

        return DiskProfileResult(
            qdReadMatrix: readMatrix,
            qdWriteMatrix: writeMatrix
        )
    }

    // MARK: - Queue Depth Matrix
    /// Tests random I/O at different queue depths
    /// QD1 = single operation, QD32 = high parallelism (NVMe sweet spot)
    private func runQDMatrix(isRead: Bool) throws -> [(qd: Int, iops: Double, mbps: Double)] {
        var results: [(qd: Int, iops: Double, mbps: Double)] = []

        let queueDepths = quickMode ? [1, 4, 16] : [1, 2, 4, 8, 16, 32]
        let blockSize = 4096  // 4KB blocks
        let fileSize = quickMode ? 256 * 1024 * 1024 : 512 * 1024 * 1024

        for qd in queueDepths {
            let iops = try runQDTest(queueDepth: qd, blockSize: blockSize, fileSize: fileSize, isRead: isRead)
            let mbps = iops * Double(blockSize) / (1024 * 1024)
            results.append((qd: qd, iops: iops, mbps: mbps))
        }

        return results
    }

    private func runQDTest(queueDepth: Int, blockSize: Int, fileSize: Int, isRead: Bool) throws -> Double {
        let filePath = testDir.appendingPathComponent("qd_test_\(UUID().uuidString)")

        // Create test file
        let fd = open(filePath.path, O_RDWR | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw DiskProfileError.fileOpenFailed }
        defer {
            close(fd)
            try? FileManager.default.removeItem(at: filePath)
        }

        _ = fcntl(fd, F_NOCACHE, 1)
        _ = ftruncate(fd, off_t(fileSize))

        // Pre-fill for reads
        if isRead {
            var chunk = [UInt8](repeating: 0x5A, count: 4 * 1024 * 1024)
            var written = 0
            while written < fileSize {
                let toWrite = min(chunk.count, fileSize - written)
                _ = write(fd, &chunk, toWrite)
                written += toWrite
            }
            _ = fcntl(fd, F_FULLFSYNC)
            lseek(fd, 0, SEEK_SET)
        }

        let block = [UInt8](repeating: 0, count: blockSize)
        let maxOffset = fileSize - blockSize
        let blockAlignedMax = maxOffset / blockSize
        let operationsPerQD = quickMode ? 100 : 500

        let start = CFAbsoluteTimeGetCurrent()

        // Simulate queue depth with concurrent dispatch
        let totalOperations = operationsPerQD * queueDepth
        let queue = DispatchQueue(label: "diskprofile", attributes: .concurrent)
        let group = DispatchGroup()
        let opsCompleted = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        opsCompleted.pointee = 0
        defer { opsCompleted.deallocate() }

        for _ in 0..<queueDepth {
            group.enter()
            queue.async {
                for _ in 0..<operationsPerQD {
                    let blockIndex = Int(arc4random_uniform(UInt32(blockAlignedMax)))
                    let offset = off_t(blockIndex * blockSize)

                    var localBlock = block
                    if isRead {
                        pread(fd, &localBlock, blockSize, offset)
                    } else {
                        pwrite(fd, &localBlock, blockSize, offset)
                    }
                }
                group.leave()
            }
        }
        group.wait()

        if !isRead {
            _ = fcntl(fd, F_FULLFSYNC)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        return Double(totalOperations) / elapsed
    }
}

// MARK: - CPU Scaling Profile

struct CPUScalingProfile {
    let duration: Int
    let maxCores: Int
    let quickMode: Bool

    init(duration: Int, maxCores: Int, quickMode: Bool = false) {
        self.duration = duration
        self.maxCores = maxCores
        self.quickMode = quickMode
    }

    /// Run CPU thread scaling test
    func run() async throws -> CPUScalingResult {
        print("    Running thread sweep...")
        let scalingData = await runThreadSweep()

        // Calculate efficiency metric
        let efficiency = calculateScalingEfficiency(scalingData)

        return CPUScalingResult(
            threadScaling: scalingData,
            scalingEfficiency: efficiency
        )
    }

    // MARK: - Thread Sweep
    /// Tests throughput at different thread counts to measure scaling efficiency
    private func runThreadSweep() async -> [(threads: Int, throughput: Double, efficiency: Double)] {
        var results: [(threads: Int, throughput: Double, efficiency: Double)] = []

        let threadCounts = quickMode
            ? [1, maxCores / 2, maxCores]
            : Array(1...min(maxCores, 16))

        var singleThreadThroughput: Double = 0

        for threadCount in threadCounts {
            let throughput = await measureThroughput(threads: threadCount)

            if threadCount == 1 {
                singleThreadThroughput = throughput
            }

            // Efficiency = actual / (single * threads)
            let idealThroughput = singleThreadThroughput * Double(threadCount)
            let efficiency = idealThroughput > 0 ? (throughput / idealThroughput) * 100 : 0

            results.append((threads: threadCount, throughput: throughput, efficiency: efficiency))
        }

        return results
    }

    private func measureThroughput(threads: Int) async -> Double {
        let operations = quickMode ? 10_000_000 : 50_000_000
        let testDuration = Double(duration) / Double(quickMode ? 3 : min(maxCores, 16))

        return await withTaskGroup(of: Double.self, returning: Double.self) { group in
            for _ in 0..<threads {
                group.addTask {
                    var accumulator: Int64 = 0
                    var totalOps = 0

                    let endTime = CFAbsoluteTimeGetCurrent() + testDuration
                    while CFAbsoluteTimeGetCurrent() < endTime {
                        for i in 0..<operations {
                            let value = Int64(i)
                            accumulator = accumulator &+ value
                            accumulator = accumulator &* 3
                            accumulator = accumulator ^ (accumulator >> 7)
                        }
                        totalOps += operations
                    }

                    if accumulator == Int64.min { print("") }
                    return Double(totalOps)
                }
            }

            var total = 0.0
            for await ops in group {
                total += ops
            }

            return total / testDuration / 1_000_000  // Mops/s
        }
    }

    private func calculateScalingEfficiency(_ data: [(threads: Int, throughput: Double, efficiency: Double)]) -> Double {
        // Average efficiency across all thread counts
        guard !data.isEmpty else { return 0 }
        let sumEfficiency = data.map { $0.efficiency }.reduce(0, +)
        return sumEfficiency / Double(data.count)
    }
}

// MARK: - Result Types

struct MemoryProfileResult {
    let strideSweep: [(stride: Int, gbps: Double)]
    let blockSizeSweep: [(blockSize: Int, gbps: Double)]

    /// Detected L1/L2/L3 cache sizes based on performance cliffs
    var detectedCacheBoundaries: [String] {
        var boundaries: [String] = []

        // Find significant drops in block-size sweep
        for i in 1..<blockSizeSweep.count {
            let prev = blockSizeSweep[i - 1]
            let curr = blockSizeSweep[i]
            let dropPercent = (prev.gbps - curr.gbps) / prev.gbps * 100

            if dropPercent > 20 {
                boundaries.append("\(formatBytes(prev.blockSize)) → \(formatBytes(curr.blockSize)): -\(String(format: "%.0f", dropPercent))%")
            }
        }

        return boundaries
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 {
            return "\(bytes / (1024 * 1024))MB"
        } else if bytes >= 1024 {
            return "\(bytes / 1024)KB"
        }
        return "\(bytes)B"
    }
}

struct DiskProfileResult {
    let qdReadMatrix: [(qd: Int, iops: Double, mbps: Double)]
    let qdWriteMatrix: [(qd: Int, iops: Double, mbps: Double)]

    /// Optimal queue depth for this drive
    var optimalReadQD: Int {
        qdReadMatrix.max(by: { $0.iops < $1.iops })?.qd ?? 1
    }

    var optimalWriteQD: Int {
        qdWriteMatrix.max(by: { $0.iops < $1.iops })?.qd ?? 1
    }

    /// Peak IOPS achieved
    var peakReadIOPS: Double {
        qdReadMatrix.map { $0.iops }.max() ?? 0
    }

    var peakWriteIOPS: Double {
        qdWriteMatrix.map { $0.iops }.max() ?? 0
    }
}

struct CPUScalingResult {
    let threadScaling: [(threads: Int, throughput: Double, efficiency: Double)]
    let scalingEfficiency: Double  // Average efficiency (0-100%)

    struct ScalingCliffAnalysis {
        let cliffThreads: Int?
        let efficiencyAfter: Double?
        let threshold: Double
        let baselineThreads: Int?
        let comparisonThreads: Int?
    }

    /// Detects a scaling cliff by comparing efficiency before/after a thread count step.
    var scalingCliffAnalysis: ScalingCliffAnalysis {
        let threshold = 20.0
        let dataByThreads = Dictionary(uniqueKeysWithValues: threadScaling.map { ($0.threads, $0.efficiency) })

        let baselineCandidates = [4, 2, 1]
        let baselineThreads = baselineCandidates.first { dataByThreads[$0] != nil }
        guard let baseline = baselineThreads, let baselineEfficiency = dataByThreads[baseline] else {
            return ScalingCliffAnalysis(
                cliffThreads: nil,
                efficiencyAfter: nil,
                threshold: threshold,
                baselineThreads: nil,
                comparisonThreads: nil
            )
        }

        let comparisonThreads = threadScaling
            .map { $0.threads }
            .filter { $0 > baseline }
            .sorted()
            .first

        guard let comparison = comparisonThreads, let comparisonEfficiency = dataByThreads[comparison] else {
            return ScalingCliffAnalysis(
                cliffThreads: nil,
                efficiencyAfter: nil,
                threshold: threshold,
                baselineThreads: baseline,
                comparisonThreads: nil
            )
        }

        let efficiencyDrop = baselineEfficiency - comparisonEfficiency
        let cliffDetected = efficiencyDrop >= threshold

        return ScalingCliffAnalysis(
            cliffThreads: cliffDetected ? baseline : nil,
            efficiencyAfter: cliffDetected ? comparisonEfficiency : nil,
            threshold: threshold,
            baselineThreads: baseline,
            comparisonThreads: comparison
        )
    }
}

// MARK: - Combined Advanced Profile Result

struct AdvancedProfileResults {
    let memory: MemoryProfileResult?
    let disk: DiskProfileResult?
    let cpuScaling: CPUScalingResult?
    let quickMode: Bool
    let duration: Int
}

// MARK: - Errors

enum DiskProfileError: Error, LocalizedError {
    case fileOpenFailed

    var errorDescription: String? {
        switch self {
        case .fileOpenFailed:
            return "Failed to open test file for disk profiling"
        }
    }
}
