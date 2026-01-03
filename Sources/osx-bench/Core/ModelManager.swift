import Foundation
import CryptoKit
import CoreML

// MARK: - Model Manager

struct ModelManager {
    // Model configuration - download directly from Apple's ML assets
    // Using fixed version with SHA256 verification for reproducibility
    static let modelVersion = "v1"
    static let modelSourceName = "MobileNetV2.mlmodel"
    static let modelCompiledName = "MobileNetV2.mlmodelc"

    // Apple's official CoreML model repository
    // MobileNetV2 last modified: 2019-11-05 (stable version)
    static let appleModelURL = "https://ml-assets.apple.com/coreml/models/Image/ImageClassification/MobileNetV2/MobileNetV2.mlmodel"

    // SHA256 hash of the model file for integrity verification
    // This ensures we always use the same model version for reproducible benchmarks
    static let expectedSHA256 = "cb5a35f593582232140556bbfa4618e66b37b8ff2fc33ba17db909e1050fd144"

    // Cache directory
    static var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("osx-bench/models/\(modelVersion)")
    }

    static var cachedSourcePath: URL {
        cacheDirectory.appendingPathComponent(modelSourceName)
    }

    static var cachedCompiledPath: URL {
        cacheDirectory.appendingPathComponent(modelCompiledName)
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

        // Priority 2: Cached compiled model
        if FileManager.default.fileExists(atPath: Self.cachedCompiledPath.path) {
            return Self.cachedCompiledPath
        }

        // Priority 3: Download and compile (if not offline)
        if offlineMode {
            print("  ⚠️  AI model not cached and --offline specified. Skipping AI benchmark.")
            return nil
        }

        // Download and compile the model
        return try await downloadAndCompileModel()
    }

    // MARK: - Download and Compile

    private func downloadAndCompileModel() async throws -> URL {
        print("  📥 Downloading AI model from Apple ML assets...")

        guard let url = URL(string: Self.appleModelURL) else {
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

        // Move to cache directory
        try? FileManager.default.removeItem(at: Self.cachedSourcePath)
        try FileManager.default.moveItem(at: tempURL, to: Self.cachedSourcePath)

        // Verify SHA256 hash for reproducibility
        print("  🔐 Verifying model integrity...")
        let actualHash = try sha256Hash(of: Self.cachedSourcePath)
        guard actualHash.lowercased() == Self.expectedSHA256.lowercased() else {
            try? FileManager.default.removeItem(at: Self.cachedSourcePath)
            throw ModelError.hashMismatch(expected: Self.expectedSHA256, actual: actualHash)
        }

        print("  ⚙️  Compiling model for your device...")

        // Compile the model using CoreML's built-in compiler (no Xcode needed)
        let compiledURL = try compileModelWithCoreML()

        // Clean up source .mlmodel (keep only compiled)
        try? FileManager.default.removeItem(at: Self.cachedSourcePath)

        print("  ✓ Model ready")
        return compiledURL
    }

    private func compileModelWithCoreML() throws -> URL {
        // Use CoreML's built-in model compiler - works without Xcode Command Line Tools
        let compiledURL = try MLModel.compileModel(at: Self.cachedSourcePath)

        // Move compiled model to our cache directory
        try? FileManager.default.removeItem(at: Self.cachedCompiledPath)
        try FileManager.default.moveItem(at: compiledURL, to: Self.cachedCompiledPath)

        return Self.cachedCompiledPath
    }

    // MARK: - Helpers

    private func sha256Hash(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors

enum ModelError: LocalizedError {
    case customModelNotFound(path: String)
    case invalidURL
    case downloadFailed(statusCode: Int)
    case hashMismatch(expected: String, actual: String)
    case compilationFailed

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
        case .compilationFailed:
            return "Failed to compile CoreML model"
        }
    }
}
