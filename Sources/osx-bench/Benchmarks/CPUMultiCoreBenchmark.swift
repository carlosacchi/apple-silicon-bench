import Foundation
import Accelerate
import CryptoKit
import Compression

struct CPUMultiCoreBenchmark: Benchmark {
    let iterations: Int = 1  // Kept for protocol conformance
    let duration: Int  // Duration in seconds
    let coreCount: Int
    let quickMode: Bool

    init(duration: Int, coreCount: Int, quickMode: Bool = false) {
        self.duration = duration
        self.coreCount = coreCount
        self.quickMode = quickMode
    }

    // Scaled parameters based on mode
    private var integerOperations: Int { quickMode ? 10_000_000 : 100_000_000 }
    private var floatOperations: Int { quickMode ? 5_000_000 : 50_000_000 }
    private var simdIterations: Int { quickMode ? 20 : 100 }
    private var cryptoDataSize: Int { quickMode ? 8 * 1024 * 1024 : 64 * 1024 * 1024 }
    private var compressionDataSize: Int { quickMode ? 4 * 1024 * 1024 : 32 * 1024 * 1024 }

    func run() async throws -> [TestResult] {
        var results: [TestResult] = []
        let testDuration = Double(duration) / 5.0  // Divide duration among 5 tests

        // Integer operations (parallel)
        let intResult = await measureParallelForDuration(seconds: testDuration) {
            runIntegerTest()
        }
        results.append(TestResult(name: "Integer_Multi", value: intResult, unit: "Mops/s"))

        // Floating point operations (parallel)
        let floatResult = await measureParallelForDuration(seconds: testDuration) {
            runFloatTest()
        }
        results.append(TestResult(name: "Float_Multi", value: floatResult, unit: "Mops/s"))

        // SIMD / Accelerate operations (parallel)
        let simdResult = await measureParallelForDuration(seconds: testDuration) {
            runSIMDTest()
        }
        results.append(TestResult(name: "SIMD_Multi", value: simdResult, unit: "GFLOPS"))

        // Cryptography parallel
        let cryptoResult = await measureParallelForDuration(seconds: testDuration) {
            runCryptoTest()
        }
        results.append(TestResult(name: "Crypto_Multi", value: cryptoResult, unit: "MB/s"))

        // Compression parallel
        let compressionResult = await measureParallelForDuration(seconds: testDuration) {
            runCompressionTest()
        }
        results.append(TestResult(name: "Compression_Multi", value: compressionResult, unit: "MB/s"))

        return results
    }

    private func measureParallelForDuration(seconds: Double, operation: @escaping @Sendable () -> Double) async -> Double {
        // Warmup (skip in quick mode)
        if !quickMode {
            await withTaskGroup(of: Double.self) { group in
                for _ in 0..<coreCount {
                    group.addTask {
                        operation()
                    }
                }
                for await _ in group { }
            }
        }

        // Actual measurement - run for duration on all cores
        var totalThroughput = 0.0
        let endTime = CFAbsoluteTimeGetCurrent() + seconds

        await withTaskGroup(of: Double.self) { group in
            for _ in 0..<coreCount {
                group.addTask {
                    var sum = 0.0
                    var count = 0
                    while CFAbsoluteTimeGetCurrent() < endTime {
                        sum += operation()
                        count += 1
                    }
                    return count > 0 ? sum / Double(count) : 0
                }
            }

            for await result in group {
                totalThroughput += result
            }
        }

        return totalThroughput
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

        if accumulator == Int64.min { print("") }

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

        if accumulator.isNaN { print("") }

        return Double(floatOperations * 4) / duration / 1_000_000
    }

    // MARK: - SIMD Test (compute-bound for multi-core scaling)
    private func runSIMDTest() -> Double {
        // Use small vectors that fit in L1 cache per core (~96KB total)
        // This ensures the test is compute-bound, not memory-bandwidth bound,
        // so throughput properly scales with core count.
        // (1M-element vectors cause all cores to contend for shared memory bandwidth,
        // making multi-core barely faster than single-core)
        let vectorSize = 8_192  // 32KB per vector × 3 = 96KB (fits in 128KB L1)
        let iterations = quickMode ? 2_400 : 12_000  // More iterations to compensate

        var vectorA = [Float](repeating: 0, count: vectorSize)
        var vectorB = [Float](repeating: 0, count: vectorSize)
        var vectorC = [Float](repeating: 0, count: vectorSize)

        for i in 0..<vectorSize {
            vectorA[i] = Float(i) * 0.001
            vectorB[i] = Float(vectorSize - i) * 0.001
        }

        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<iterations {
            vDSP_vma(vectorA, 1, vectorB, 1, vectorC, 1, &vectorC, 1, vDSP_Length(vectorSize))
            vDSP_vadd(vectorA, 1, vectorB, 1, &vectorC, 1, vDSP_Length(vectorSize))
            var dotResult: Float = 0
            vDSP_dotpr(vectorA, 1, vectorB, 1, &dotResult, vDSP_Length(vectorSize))
        }

        let duration = CFAbsoluteTimeGetCurrent() - start

        let totalOps = Double(iterations) * Double(vectorSize) * 6.0
        return totalOps / duration / 1_000_000_000
    }

    // MARK: - Crypto Test
    private func runCryptoTest() -> Double {
        let data = Data((0..<cryptoDataSize).map { UInt8($0 & 0xFF) })
        let key = SymmetricKey(size: .bits256)

        do {
            let nonce = try AES.GCM.Nonce(data: Data(repeating: 0, count: 12))

            let start = CFAbsoluteTimeGetCurrent()

            let encrypted = try AES.GCM.seal(data, using: key, nonce: nonce)
            _ = SHA256.hash(data: encrypted.ciphertext)

            let duration = CFAbsoluteTimeGetCurrent() - start

            return Double(cryptoDataSize) / duration / (1024 * 1024)
        } catch {
            // Return 0 to indicate benchmark failure
            return 0
        }
    }

    // MARK: - Compression Test
    private func runCompressionTest() -> Double {
        var data = Data(count: compressionDataSize)

        for i in 0..<compressionDataSize {
            if i % 100 < 80 {
                data[i] = UInt8(i % 256)
            } else {
                data[i] = UInt8.random(in: 0...255)
            }
        }

        let start = CFAbsoluteTimeGetCurrent()

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

        return Double(compressionDataSize * 2) / duration / (1024 * 1024)
    }
}
