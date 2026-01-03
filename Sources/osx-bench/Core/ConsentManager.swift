import Foundation

// MARK: - Consent Manager

struct ConsentManager {
    private static let consentFileName = "privacy-consent"

    private static var consentDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("osx-bench")
    }

    private static var consentFilePath: URL {
        consentDirectory.appendingPathComponent(consentFileName)
    }

    /// Extract MAJOR.MINOR from a semantic version string (e.g., "2.1.0" -> "2.1")
    private static func majorMinor(from version: String) -> String {
        let components = version.split(separator: ".")
        guard components.count >= 2 else { return version }
        return "\(components[0]).\(components[1])"
    }

    /// Read the version from the stored consent file
    private static func storedConsentVersion() -> String? {
        guard FileManager.default.fileExists(atPath: consentFilePath.path) else {
            return nil
        }

        do {
            let content = try String(contentsOf: consentFilePath, encoding: .utf8)
            // Parse "Version: X.Y.Z" line
            for line in content.components(separatedBy: .newlines) {
                if line.hasPrefix("Version:") {
                    let version = line
                        .replacingOccurrences(of: "Version:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    return version
                }
            }
        } catch {
            // If we can't read the file, treat as no consent
        }
        return nil
    }

    /// Check if user has already accepted the privacy policy for current MAJOR.MINOR version
    /// Re-ask consent on MAJOR or MINOR version upgrades (not PATCH)
    static func hasAcceptedPrivacyPolicy() -> Bool {
        guard let storedVersion = storedConsentVersion() else {
            return false
        }

        let storedMajorMinor = majorMinor(from: storedVersion)
        let currentMajorMinor = majorMinor(from: AppInfo.version)

        // Same MAJOR.MINOR = consent still valid
        // Different MAJOR.MINOR = re-ask consent
        return storedMajorMinor == currentMajorMinor
    }

    /// Record that user has accepted the privacy policy
    static func recordAcceptance() throws {
        try FileManager.default.createDirectory(
            at: consentDirectory,
            withIntermediateDirectories: true
        )

        let content = """
        Privacy Policy Accepted
        Date: \(ISO8601DateFormatter().string(from: Date()))
        Version: \(AppInfo.version)
        """

        try content.write(to: consentFilePath, atomically: true, encoding: String.Encoding.utf8)
    }

    /// Display privacy consent prompt and return true if accepted
    static func requestConsent() -> Bool {
        print("")
        print("╔══════════════════════════════════════════════════════════════════╗")
        print("║                     PRIVACY POLICY NOTICE                        ║")
        print("╠══════════════════════════════════════════════════════════════════╣")
        print("║                                                                  ║")
        print("║  Apple Silicon Bench respects your privacy:                      ║")
        print("║                                                                  ║")
        print("║  • No personal data is collected                                 ║")
        print("║  • No telemetry or analytics                                     ║")
        print("║  • All results stay on your device                               ║")
        print("║  • Open source - verify the code yourself                        ║")
        print("║                                                                  ║")
        print("║  The AI benchmark may download a ~5MB model from GitHub.         ║")
        print("║                                                                  ║")
        print("║  Full privacy policy:                                            ║")
        print("║  https://github.com/carlosacchi/apple-silicon-bench/wiki/Privacy-Policy")
        print("║                                                                  ║")
        print("╚══════════════════════════════════════════════════════════════════╝")
        print("")
        print("Do you accept the privacy policy? (y/n): ", terminator: "")

        guard let response = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) else {
            return false
        }

        return response == "y" || response == "yes"
    }

    /// Check consent and prompt if needed. Returns true if OK to proceed.
    static func ensureConsent() -> Bool {
        if hasAcceptedPrivacyPolicy() {
            return true
        }

        if requestConsent() {
            do {
                try recordAcceptance()
                print("")
                print("✓ Privacy policy accepted. This prompt won't appear again.")
                print("")
                return true
            } catch {
                print("Warning: Could not save consent preference: \(error.localizedDescription)")
                // Still allow to proceed even if we can't save
                return true
            }
        } else {
            print("")
            print("Privacy policy not accepted. Exiting.")
            print("Run the program again and accept to use Apple Silicon Bench.")
            print("")
            return false
        }
    }
}
