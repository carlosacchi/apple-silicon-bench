import Foundation

enum AppInfo {
    // Version is synced from Package.swift by scripts/bump-version.sh
    static let version = "1.3.1"

    static let name = "osx-bench"
    static let fullName = "Apple Silicon Bench"
    static let repository = "https://github.com/carlosacchi/apple-silicon-bench"

    // Developer info
    static let developer = "Carlo Sacchi"
    static let license = "MIT License"
    static let releaseDate = "2026-01-01"  // Updated with each release

    static var copyright: String {
        let year = Calendar.current.component(.year, from: Date())
        return "Copyright © \(year) Carlo Sacchi"
    }

    static var versionString: String {
        """
        \(fullName) v\(version) (\(releaseDate))
        Designed and developed by \(developer)
        \(repository)
        \(copyright) - \(license)
        """
    }
}
