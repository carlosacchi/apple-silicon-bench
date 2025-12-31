import Foundation

/// Monitors thermal state during benchmarks
struct ThermalMonitor {

    enum ThermalLevel: String, Codable {
        case nominal = "Nominal"      // Normal operation
        case fair = "Fair"            // Slightly elevated, minor throttling possible
        case serious = "Serious"      // Significant throttling
        case critical = "Critical"    // Maximum throttling, performance severely impacted

        var emoji: String {
            switch self {
            case .nominal: return "🟢"
            case .fair: return "🟡"
            case .serious: return "🟠"
            case .critical: return "🔴"
            }
        }

        var description: String {
            switch self {
            case .nominal: return "Normal - No throttling"
            case .fair: return "Warm - Minor throttling possible"
            case .serious: return "Hot - Significant throttling"
            case .critical: return "Critical - Severe throttling"
            }
        }
    }

    /// Get current thermal state
    static func currentState() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .nominal
        }
    }

    /// Print current thermal state
    static func printStatus() {
        let state = currentState()
        print("  Thermal .... \(state.emoji) \(state.description)")
    }

    /// Check if system is throttling
    static var isThrottling: Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    /// Warning message if throttling detected
    static func throttlingWarning() -> String? {
        if isThrottling {
            return "⚠️  Thermal throttling detected! Results may be lower than normal."
        }
        return nil
    }
}

/// Thermal snapshot for recording state at specific points
struct ThermalSnapshot: Codable {
    let timestamp: Date
    let level: ThermalMonitor.ThermalLevel
    let phase: String

    init(phase: String) {
        self.timestamp = Date()
        self.level = ThermalMonitor.currentState()
        self.phase = phase
    }
}

/// Collects thermal data throughout benchmark run
class ThermalCollector {
    private var snapshots: [ThermalSnapshot] = []

    func record(phase: String) {
        snapshots.append(ThermalSnapshot(phase: phase))
    }

    var startState: ThermalMonitor.ThermalLevel? {
        snapshots.first?.level
    }

    var endState: ThermalMonitor.ThermalLevel? {
        snapshots.last?.level
    }

    var worstState: ThermalMonitor.ThermalLevel {
        let levels: [ThermalMonitor.ThermalLevel] = [.nominal, .fair, .serious, .critical]
        var worst = ThermalMonitor.ThermalLevel.nominal

        for snapshot in snapshots {
            if let currentIndex = levels.firstIndex(of: snapshot.level),
               let worstIndex = levels.firstIndex(of: worst),
               currentIndex > worstIndex {
                worst = snapshot.level
            }
        }
        return worst
    }

    var hadThrottling: Bool {
        snapshots.contains { $0.level == .serious || $0.level == .critical }
    }

    func summary() -> String {
        guard let start = startState, let end = endState else {
            return "No thermal data"
        }

        if hadThrottling {
            return "\(start.emoji) → \(end.emoji) (⚠️ Throttling detected)"
        } else {
            return "\(start.emoji) → \(end.emoji)"
        }
    }

    var allSnapshots: [ThermalSnapshot] {
        snapshots
    }
}
