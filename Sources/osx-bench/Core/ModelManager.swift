import Foundation
import CryptoKit

// MARK: - Model Manager

struct ModelManager {
    // Model configuration
    static let modelVersion = "v1"
    static let modelName = "MobileNetV2.mlmodelc"
    static let modelZipName = "MobileNetV2.mlmodelc.zip"
    static let modelURL = "https://github.com/carlosacchi/apple-silicon-bench/releases/download/models-\(modelVersion)/\(modelZipName)"

    // SHA256 hash of the zip file (to be updated when model is uploaded)
    // This ensures integrity and prevents tampering
    static let expectedSHA256 = "PLACEHOLDER_SHA256_HASH"

    // Cache directory
    static var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("osx-bench/models/\(modelVersion)")
    }

    static var cachedModelPath: URL {
        cacheDirectory.appendingPathComponent(modelName)
    }

    let customModelPath: String?
    let offlineMode: Bool

    init(customModelPath: String? = nil, offlineMode: Bool = false) {
        self.customModelPath = customModelPath
        self.offlineMode = offlineMode
    }

    // MARK: - Public API

    /// Ensures the model is available and returns its path
    /// Returns nil if model is unavailable (offline mode without cache)
    func ensureModel() async throws -> URL? {
        // Priority 1: Custom model path
        if let customPath = customModelPath {
            let url = URL(fileURLWithPath: customPath)
            guard FileManager.default.fileExists(atPath: customPath) else {
                throw ModelError.customModelNotFound(path: customPath)
            }
            return url
        }

        // Priority 2: Cached model
        if FileManager.default.fileExists(atPath: Self.cachedModelPath.path) {
            return Self.cachedModelPath
        }

        // Priority 3: Download (if not offline)
        if offlineMode {
            print("  ⚠️  AI model not cached and --offline specified. Skipping AI benchmark.")
            return nil
        }

        // Download the model
        return try await downloadModel()
    }

    // MARK: - Download

    private func downloadModel() async throws -> URL {
        print("  📥 Downloading AI model (\(Self.modelZipName))...")

        guard let url = URL(string: Self.modelURL) else {
            throw ModelError.invalidURL
        }

        // Create cache directory
        try FileManager.default.createDirectory(
            at: Self.cacheDirectory,
            withIntermediateDirectories: true
        )

        // Download
        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        // Move to permanent location
        let zipPath = Self.cacheDirectory.appendingPathComponent(Self.modelZipName)

        // Remove existing zip if present
        try? FileManager.default.removeItem(at: zipPath)
        try FileManager.default.moveItem(at: tempURL, to: zipPath)

        // Verify SHA256 (skip if placeholder)
        if Self.expectedSHA256 != "PLACEHOLDER_SHA256_HASH" {
            print("  🔐 Verifying integrity...")
            let actualHash = try sha256Hash(of: zipPath)
            guard actualHash.lowercased() == Self.expectedSHA256.lowercased() else {
                try? FileManager.default.removeItem(at: zipPath)
                throw ModelError.hashMismatch(expected: Self.expectedSHA256, actual: actualHash)
            }
        }

        // Unzip
        print("  📦 Extracting model...")
        try unzip(zipPath, to: Self.cacheDirectory)

        // Clean up zip
        try? FileManager.default.removeItem(at: zipPath)

        // Verify model exists
        guard FileManager.default.fileExists(atPath: Self.cachedModelPath.path) else {
            throw ModelError.extractionFailed
        }

        print("  ✓ Model ready")
        return Self.cachedModelPath
    }

    // MARK: - Helpers

    private func sha256Hash(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func unzip(_ zipURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ModelError.extractionFailed
        }
    }
}

// MARK: - Errors

enum ModelError: LocalizedError {
    case customModelNotFound(path: String)
    case invalidURL
    case downloadFailed(statusCode: Int)
    case hashMismatch(expected: String, actual: String)
    case extractionFailed

    var errorDescription: String? {
        switch self {
        case .customModelNotFound(let path):
            return "Custom model not found at: \(path)"
        case .invalidURL:
            return "Invalid model URL"
        case .downloadFailed(let statusCode):
            return "Model download failed with status code: \(statusCode)"
        case .hashMismatch(let expected, let actual):
            return "Model integrity check failed. Expected SHA256: \(expected), got: \(actual)"
        case .extractionFailed:
            return "Failed to extract model archive"
        }
    }
}
