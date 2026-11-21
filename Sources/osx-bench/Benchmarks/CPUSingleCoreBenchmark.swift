import Foundation
import CryptoKit
import Compression

struct CPUSingleCoreBenchmark: Benchmark {
    let iterations: Int = 1  // Kept for protocol conformance
    let duration: Int  // Duration in seconds
    let quickMode: Bool

    init(duration: Int, quickMode: Bool = false) {
        self.duration = duration
        self.quickMode = quickMode
    }

    // Scaled parameters based on mode - these are per-iteration sizes
    private var integerOperations: Int { quickMode ? 10_000_000 : 100_000_000 }
    private var floatOperations: Int { quickMode ? 5_000_000 : 50_000_000 }
    private var cryptoDataSize: Int { quickMode ? 8 * 1024 * 1024 : 64 * 1024 * 1024 }
    private var compressionDataSize: Int { quickMode ? 4 * 1024 * 1024 : 32 * 1024 * 1024 }

    func run() async throws -> [TestResult] {
        var results: [TestResult] = []
        let testDuration = Double(duration) / 5.0  // Divide duration among 5 tests

        // Integer operations
        let intResult = measureForDuration(seconds: testDuration, warmup: !quickMode) {
            runIntegerTest()
        }
        results.append(TestResult(name: "Integer", value: intResult, unit: "Mops/s"))

        // Floating point operations
        let floatResult = measureForDuration(seconds: testDuration, warmup: !quickMode) {
            runFloatTest()
        }
        results.append(TestResult(name: "Float", value: floatResult, unit: "Mops/s"))

        // SIMD operations (NEON)
        let simdResult = measureForDuration(seconds: testDuration, warmup: !quickMode) {
            runSIMDTest()
        }
        results.append(TestResult(name: "SIMD", value: simdResult, unit: "GFLOPS"))

        // Cryptography (AES + SHA)
        let cryptoResult = measureForDuration(seconds: testDuration, warmup: !quickMode) {
            runCryptoTest()
        }
        results.append(TestResult(name: "Crypto", value: cryptoResult, unit: "MB/s"))

        // Compression
        let compressionResult = measureForDuration(seconds: testDuration, warmup: !quickMode) {
            runCompressionTest()
        }
        results.append(TestResult(name: "Compression", value: compressionResult, unit: "MB/s"))

        return results
    }

    /// Run operation repeatedly for the specified duration, returning averaged result
    private func measureForDuration(seconds: Double, warmup: Bool, operation: () -> Double) -> Double {
        // Optional warmup run
        if warmup {
            _ = operation()
        }

        var total = 0.0
        var count = 0
        let endTime = CFAbsoluteTimeGetCurrent() + seconds

        while CFAbsoluteTimeGetCurrent() < endTime {
            total += operation()
            count += 1
        }

        return count > 0 ? total / Double(count) : 0
    }

    // MARK: - Integer Test
    private func runIntegerTest() -> Double {
        var accumulator: Int64 = 0

        let start = CFAbsoluteTimeGetCurrent()

        for i in 0..<integerOperations {
            let value = Int64(i)
            accumulator = accumulator &+ value
            accumulator = accumulator &* 3
            accumulator = accumulator ^ (accumulator >> 7)
            accumulator = accumulator &+ (value &* value)
        }

        let duration = CFAbsoluteTimeGetCurrent() - start

        // Prevent optimization
        if accumulator == Int64.min { print("") }

        // Operations per second (4 ops per iteration)
        return Double(integerOperations * 4) / duration / 1_000_000
    }

    // MARK: - Float Test
    private func runFloatTest() -> Double {
        var accumulator: Double = 1.0

        let start = CFAbsoluteTimeGetCurrent()

        for i in 0..<floatOperations {
            let value = Double(i) * 0.00001
            accumulator = accumulator + value
            accumulator = accumulator * 1.000001
            accumulator = sqrt(accumulator * accumulator + 1.0)
            accumulator = sin(accumulator) + cos(accumulator)
        }

        let duration = CFAbsoluteTimeGetCurrent() - start

        // Prevent optimization
        if accumulator.isNaN { print("") }

        // Operations per second (4 ops per iteration)
        return Double(floatOperations * 4) / duration / 1_000_000
    }

    // MARK: - SIMD Test (per-core NEON, compute-bound)
    private func runSIMDTest() -> Double {
        // Same kernel as the multi-core test (see SIMDWorkload). Until v2.5.0 this used vDSP
        // on 1M-float vectors and copied one of them on every iteration (memory-bound).
        SIMDWorkload.run(iterations: quickMode ? 2_400 : 12_000)
    }

    // MARK: - Crypto Test
    private func runCryptoTest() -> Double {
        let data = Data((0..<cryptoDataSize).map { UInt8($0 & 0xFF) })
        let key = SymmetricKey(size: .bits256)

        do {
            let nonce = try AES.GCM.Nonce(data: Data(repeating: 0, count: 12))

            let start = CFAbsoluteTimeGetCurrent()

            // AES-GCM encryption
            let encrypted = try AES.GCM.seal(data, using: key, nonce: nonce)

            // SHA-256 hash
            _ = SHA256.hash(data: encrypted.ciphertext)

            let duration = CFAbsoluteTimeGetCurrent() - start

            // MB/s throughput
            return Double(cryptoDataSize) / duration / (1024 * 1024)
        } catch {
            // Return 0 to indicate benchmark failure
            return 0
        }
    }

    // MARK: - Compression Test
    private func runCompressionTest() -> Double {
        var data = Data(count: compressionDataSize)

        // Generate compressible data (mix of patterns and random)
        for i in 0..<compressionDataSize {
            if i % 100 < 80 {
                data[i] = UInt8(i % 256)  // Repeating pattern
            } else {
                data[i] = UInt8.random(in: 0...255)  // Random
            }
        }

        let start = CFAbsoluteTimeGetCurrent()

        // Compress using LZFSE (Apple's fast compression)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: compressionDataSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourcePtr in
            compression_encode_buffer(
                destinationBuffer,
                compressionDataSize,
                sourcePtr.bindMemory(to: UInt8.self).baseAddress!,
                compressionDataSize,
                nil,
                COMPRESSION_LZFSE
            )
        }

        // Decompress
        let decompressedBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: compressionDataSize)
        defer { decompressedBuffer.deallocate() }

        _ = compression_decode_buffer(
            decompressedBuffer,
            compressionDataSize,
            destinationBuffer,
            compressedSize,
            nil,
            COMPRESSION_LZFSE
        )

        let duration = CFAbsoluteTimeGetCurrent() - start

        // MB/s throughput (compress + decompress)
        return Double(compressionDataSize * 2) / duration / (1024 * 1024)
    }
}
