import Foundation

struct DiskBenchmark: Benchmark {
    let iterations: Int = 1  // Kept for protocol conformance
    let duration: Int  // Duration in seconds
    let quickMode: Bool

    private let testDir: URL
    // NovaBench-compatible parameters:
    // - Sequential: 4MB blocks
    // - Random: 4KB blocks, QD1 (single operation)
    private let sequentialBlockSize = 4 * 1024 * 1024  // 4 MB (NovaBench standard)
    private var sequentialSize: Int { quickMode ? 256 * 1024 * 1024 : 512 * 1024 * 1024 }
    private let randomBlockSize = 4096  // 4 KB (NovaBench standard)
    // Random file size: must be larger than unified memory cache to avoid cache hits
    // M1 has 8-16GB RAM, so 1GB file in full mode should exceed typical cache
    private var randomFileSize: Int { quickMode ? 512 * 1024 * 1024 : 1024 * 1024 * 1024 }
    private var randomOperations: Int { quickMode ? 500 : 2000 }

    init(duration: Int, quickMode: Bool = false) {
        self.duration = duration
        self.quickMode = quickMode
        // Use unique UUID directory per run to prevent symlink attacks
        self.testDir = FileManager.default.temporaryDirectory.appendingPathComponent("osx-bench-disk-\(UUID().uuidString)")
    }

    func run() async throws -> [TestResult] {
        // Setup test directory - create fresh (never remove pre-existing paths)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        var results: [TestResult] = []
        let testDuration = Double(duration) / 4.0  // Divide duration among 4 tests

        // Sequential Write (4MB blocks)
        let seqWriteResult = try measureForDuration(seconds: testDuration) {
            try runSequentialWriteTest()
        }
        results.append(TestResult(name: "Seq_Write", value: seqWriteResult, unit: "MB/s"))

        // Sequential Read (4MB blocks)
        let seqReadResult = try measureForDuration(seconds: testDuration) {
            try runSequentialReadTest()
        }
        results.append(TestResult(name: "Seq_Read", value: seqReadResult, unit: "MB/s"))

        // Random Write (4KB blocks, QD1) - NovaBench style (no per-op sync)
        let randWriteResult = try measureForDuration(seconds: testDuration) {
            try runRandomWriteTest()
        }
        // Output MB/s for consistency with NovaBench
        let randWriteMBps = (randWriteResult * Double(randomBlockSize)) / (1024 * 1024)
        results.append(TestResult(name: "Rand_Write", value: randWriteMBps, unit: "MB/s"))

        // Random Read (4KB blocks, QD1)
        let randReadResult = try measureForDuration(seconds: testDuration) {
            try runRandomReadTest()
        }
        let randReadMBps = (randReadResult * Double(randomBlockSize)) / (1024 * 1024)
        results.append(TestResult(name: "Rand_Read", value: randReadMBps, unit: "MB/s"))

        return results
    }

    /// Run operation repeatedly for the specified duration, returning averaged result
    private func measureForDuration(seconds: Double, operation: () throws -> Double) rethrows -> Double {
        // Warmup run
        _ = try operation()

        var total = 0.0
        var count = 0
        let endTime = CFAbsoluteTimeGetCurrent() + seconds

        while CFAbsoluteTimeGetCurrent() < endTime {
            total += try operation()
            count += 1
        }

        return count > 0 ? total / Double(count) : 0
    }

    // MARK: - Sequential Write Test
    /// NovaBench-compatible: 4MB blocks, cache bypass
    private func runSequentialWriteTest() throws -> Double {
        let filePath = testDir.appendingPathComponent("seq_write_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: filePath) }

        // Prepare random data (4MB chunk)
        var chunk = Data(count: sequentialBlockSize)
        chunk.withUnsafeMutableBytes { ptr in
            arc4random_buf(ptr.baseAddress!, sequentialBlockSize)
        }

        // Use O_NOFOLLOW to prevent symlink attacks, 0o600 for owner-only access
        let fd = open(filePath.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw DiskBenchmarkError.fileOpenFailed }
        defer { close(fd) }

        // Bypass filesystem cache for accurate measurement
        _ = fcntl(fd, F_NOCACHE, 1)

        let start = CFAbsoluteTimeGetCurrent()

        var bytesWritten = 0
        while bytesWritten < sequentialSize {
            let result = chunk.withUnsafeBytes { ptr in
                write(fd, ptr.baseAddress!, sequentialBlockSize)
            }
            if result < 0 { break }
            bytesWritten += result
        }

        // Force sync to disk
        _ = fcntl(fd, F_FULLFSYNC)

        let duration = CFAbsoluteTimeGetCurrent() - start

        return Double(bytesWritten) / duration / (1024 * 1024)
    }

    // MARK: - Sequential Read Test
    /// NovaBench-compatible: 4MB blocks, cache bypass
    private func runSequentialReadTest() throws -> Double {
        let filePath = testDir.appendingPathComponent("seq_read_test_\(UUID().uuidString)")

        // First, create the test file WITH F_NOCACHE to avoid populating cache
        var chunk = Data(count: sequentialBlockSize)
        chunk.withUnsafeMutableBytes { ptr in
            arc4random_buf(ptr.baseAddress!, sequentialBlockSize)
        }

        let writefd = open(filePath.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
        guard writefd >= 0 else { throw DiskBenchmarkError.fileOpenFailed }

        // Set F_NOCACHE BEFORE writing to prevent cache population
        _ = fcntl(writefd, F_NOCACHE, 1)

        var written = 0
        while written < sequentialSize {
            let result = chunk.withUnsafeBytes { ptr in
                write(writefd, ptr.baseAddress!, sequentialBlockSize)
            }
            if result < 0 { break }
            written += result
        }
        // Sync and close write fd
        _ = fcntl(writefd, F_FULLFSYNC)
        close(writefd)

        defer { try? FileManager.default.removeItem(at: filePath) }

        // Open for reading with cache bypass
        let fd = open(filePath.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw DiskBenchmarkError.fileOpenFailed }
        defer { close(fd) }

        _ = fcntl(fd, F_NOCACHE, 1)

        var readBuffer = [UInt8](repeating: 0, count: sequentialBlockSize)

        let start = CFAbsoluteTimeGetCurrent()

        var bytesRead = 0
        while bytesRead < sequentialSize {
            let result = read(fd, &readBuffer, sequentialBlockSize)
            if result <= 0 { break }
            bytesRead += result
        }

        let duration = CFAbsoluteTimeGetCurrent() - start

        return Double(bytesRead) / duration / (1024 * 1024)
    }

    // MARK: - Random Write (QD1)
    /// NovaBench-compatible: 4KB blocks, one operation at a time
    /// Note: NovaBench does NOT sync per-operation, only final sync
    private func runRandomWriteTest() throws -> Double {
        let filePath = testDir.appendingPathComponent("rand_write_test_\(UUID().uuidString)")

        let fd = open(filePath.path, O_RDWR | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw DiskBenchmarkError.fileOpenFailed }
        defer {
            close(fd)
            try? FileManager.default.removeItem(at: filePath)
        }

        // Pre-allocate file and set nocache BEFORE any I/O
        _ = ftruncate(fd, off_t(randomFileSize))
        _ = fcntl(fd, F_NOCACHE, 1)

        var block = [UInt8](repeating: 0, count: randomBlockSize)
        arc4random_buf(&block, randomBlockSize)

        let maxOffset = randomFileSize - randomBlockSize
        let blockAlignedMax = maxOffset / randomBlockSize

        let start = CFAbsoluteTimeGetCurrent()

        // QD1: One operation at a time, NO per-op sync (NovaBench style)
        for _ in 0..<randomOperations {
            let blockIndex = Int(arc4random_uniform(UInt32(blockAlignedMax)))
            let offset = off_t(blockIndex * randomBlockSize)
            lseek(fd, offset, SEEK_SET)
            _ = write(fd, &block, randomBlockSize)
        }

        // Single final sync (NovaBench style)
        _ = fcntl(fd, F_FULLFSYNC)

        let duration = CFAbsoluteTimeGetCurrent() - start

        return Double(randomOperations) / duration  // Returns IOPS, converted to MB/s in caller
    }

    // MARK: - Random Read (QD1)
    /// NovaBench-compatible: 4KB blocks, one operation at a time
    private func runRandomReadTest() throws -> Double {
        let filePath = testDir.appendingPathComponent("rand_read_test_\(UUID().uuidString)")

        let chunkSize = 4 * 1024 * 1024

        // Create file WITH F_NOCACHE to prevent cache population
        let writefd = open(filePath.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
        guard writefd >= 0 else { throw DiskBenchmarkError.fileOpenFailed }

        // Set F_NOCACHE BEFORE writing - critical for cold reads
        _ = fcntl(writefd, F_NOCACHE, 1)

        var chunk = [UInt8](repeating: 0x5A, count: chunkSize)
        var written = 0
        while written < randomFileSize {
            let result = write(writefd, &chunk, chunkSize)
            if result < 0 { break }
            written += result
        }
        _ = fcntl(writefd, F_FULLFSYNC)
        close(writefd)

        defer { try? FileManager.default.removeItem(at: filePath) }

        // Open for reading with cache bypass
        let fd = open(filePath.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw DiskBenchmarkError.fileOpenFailed }
        defer { close(fd) }

        _ = fcntl(fd, F_NOCACHE, 1)

        var readBuffer = [UInt8](repeating: 0, count: randomBlockSize)
        let maxOffset = randomFileSize - randomBlockSize
        let blockAlignedMax = maxOffset / randomBlockSize

        let start = CFAbsoluteTimeGetCurrent()

        // QD1: One operation at a time
        for _ in 0..<randomOperations {
            let blockIndex = Int(arc4random_uniform(UInt32(blockAlignedMax)))
            let offset = off_t(blockIndex * randomBlockSize)
            lseek(fd, offset, SEEK_SET)
            _ = read(fd, &readBuffer, randomBlockSize)
        }

        let duration = CFAbsoluteTimeGetCurrent() - start

        return Double(randomOperations) / duration  // Returns IOPS, converted to MB/s in caller
    }
}

enum DiskBenchmarkError: Error, LocalizedError {
    case fileOpenFailed
    case writeFailed
    case readFailed

    var errorDescription: String? {
        switch self {
        case .fileOpenFailed: return "Failed to open test file"
        case .writeFailed: return "Write operation failed"
        case .readFailed: return "Read operation failed"
        }
    }
}
