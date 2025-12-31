import Foundation

enum AppInfo {
    // Version is synced from Package.swift by scripts/bump-version.sh
    static let version = "1.1.0"

    static let name = "osx-bench"
    static let fullName = "Apple Silicon Bench"
    static let repository = "https://github.com/carlosacchi/apple-silicon-bench"

    // Developer info
    static let developer = "Carlo Sacchi"
    static let copyright = "Copyright © 2024 Carlo Sacchi"
    static let license = "MIT License"

    static var versionString: String {
        """
        \(fullName) v\(version)
        Developed by \(developer)
        \(repository)
        \(copyright) - \(license)
        """
    }
}
