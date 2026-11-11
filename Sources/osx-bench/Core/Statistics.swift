import Foundation

// MARK: - Latency Statistics

/// Summary statistics over per-iteration samples (same unit as the input)
struct LatencyStats: Equatable {
    let mean: Double
    let p50: Double
    let p95: Double
    let stdDev: Double

    /// Returns nil for an empty sample set
    init?(samples: [Double]) {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        self.mean = mean
        self.p50 = Self.percentile(sorted, 0.50)
        self.p95 = Self.percentile(sorted, 0.95)
        // Sample standard deviation (n - 1); 0 for a single sample
        if sorted.count > 1 {
            let variance = sorted.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(sorted.count - 1)
            self.stdDev = variance.squareRoot()
        } else {
            self.stdDev = 0
        }
    }

    /// Percentile with linear interpolation between closest ranks; `sorted` must be ascending
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let clamped = min(max(fraction, 0), 1)
        let rank = clamped * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }
}

// MARK: - Vector Comparison

enum VectorComparison {
    /// Cosine similarity of two equal-length vectors; nil if lengths differ or a vector is all zeros
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return nil }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    /// Index of the largest element (first one on ties)
    static func argmax(_ values: [Double]) -> Int? {
        guard !values.isEmpty else { return nil }
        var best = 0
        for i in values.indices where values[i] > values[best] {
            best = i
        }
        return best
    }
}
