import Foundation

// MARK: - SIMD Workload (per-core NEON, compute-bound)

/// SIMD kernel shared by the single-core and multi-core tests, so both measure the same
/// per-core work and their ratio reflects core count and scaling only.
///
/// Explicit SIMD vectors (lowered to NEON) instead of Accelerate/vDSP:
/// - on Apple Silicon vDSP can be dispatched to a matrix unit (AMX/SME) shared per CPU
///   cluster, so its throughput scales with clusters, not cores (fixed for multi-core in v2.4.0);
/// - the data stays in L1 (8K floats per vector, 32 KB × 3 = 96 KB), so the test measures the
///   SIMD units, not the cache or memory hierarchy. Until v2.5.0 the single-core test streamed
///   1M-float vectors (12 MB) and copied one of them on every iteration, so it measured memory
///   bandwidth and allocation instead.
enum SIMDWorkload {
    static let vectorSize = 8_192
    private static let lanes = 8

    /// Runs multiply-add, add and dot product `iterations` times; returns GFLOPS
    /// (6 ops per element, the accounting used since v1.x)
    static func run(iterations: Int) -> Double {
        let chunks = vectorSize / lanes

        var vectorA = ContiguousArray<SIMD8<Float>>(repeating: .zero, count: chunks)
        var vectorB = ContiguousArray<SIMD8<Float>>(repeating: .zero, count: chunks)
        var vectorC = ContiguousArray<SIMD8<Float>>(repeating: .zero, count: chunks)

        for chunk in 0..<chunks {
            for lane in 0..<lanes {
                let i = chunk * lanes + lane
                vectorA[chunk][lane] = Float(i) * 0.001
                vectorB[chunk][lane] = Float(vectorSize - i) * 0.001
            }
        }

        var checksum = SIMD8<Float>.zero
        let start = CFAbsoluteTimeGetCurrent()

        vectorA.withUnsafeBufferPointer { a in
            vectorB.withUnsafeBufferPointer { b in
                vectorC.withUnsafeMutableBufferPointer { c in
                    for _ in 0..<iterations {
                        for i in 0..<chunks { c[i] = a[i] * b[i] + c[i] }
                        for i in 0..<chunks { c[i] = a[i] + b[i] }
                        var dot = SIMD8<Float>.zero
                        for i in 0..<chunks { dot = dot + a[i] * c[i] }
                        checksum += dot
                    }
                }
            }
        }

        let duration = CFAbsoluteTimeGetCurrent() - start

        // Prevent the compiler from eliminating the loops
        if checksum.sum().isNaN { print("") }

        let totalOps = Double(iterations) * Double(vectorSize) * 6.0
        return totalOps / duration / 1_000_000_000
    }
}
