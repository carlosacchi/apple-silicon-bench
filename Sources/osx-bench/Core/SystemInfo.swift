import Foundation

struct SystemInfo: Codable {
    let machineId: String
    let chip: String
    let coresPerformance: Int
    let coresEfficiency: Int
    let totalCores: Int
    let ramGB: Int
    let osVersion: String
    let modelIdentifier: String
    let diskModel: String
    let diskCapacityGB: Int
    let diskType: String  // "SSD" or "HDD"
    let gpuModel: String
    let gpuCores: Int
    let gpuMetalVersion: String
    let batteryCycleCount: Int?
    let batteryHealth: String?
    let batteryChargingStatus: String?

    static func gather() throws -> SystemInfo {
        let machineId = getMachineId()
        let chip = getChipName()
        let (pCores, eCores) = getCoreCount()
        let ram = getRAMSize()
        let os = getOSVersion()
        let model = getModelIdentifier()
        let diskInfo = getDiskInfo()
        let gpuInfo = getGPUInfo()
        let batteryInfo = getBatteryInfo()

        return SystemInfo(
            machineId: machineId,
            chip: chip,
            coresPerformance: pCores,
            coresEfficiency: eCores,
            totalCores: pCores + eCores,
            ramGB: ram,
            osVersion: os,
            modelIdentifier: model,
            diskModel: diskInfo.model,
            diskCapacityGB: diskInfo.capacityGB,
            diskType: diskInfo.type,
            gpuModel: gpuInfo.model,
            gpuCores: gpuInfo.cores,
            gpuMetalVersion: gpuInfo.metalVersion,
            batteryCycleCount: batteryInfo.cycleCount,
            batteryHealth: batteryInfo.health,
            batteryChargingStatus: batteryInfo.chargingStatus
        )
    }

    func printBrief() {
        let thermal = ThermalMonitor.currentState()
        let line = String(repeating: "─", count: 44)
        print(line)
        print("  System Information")
        print(line)
        print(dotPad("Chip", chip))
        print(dotPad("Cores", "\(coresPerformance)P + \(coresEfficiency)E (\(totalCores) total)"))
        print(dotPad("RAM", "\(ramGB) GB"))
        print(dotPad("macOS", osVersion))
        print(dotPad("Thermal", "\(thermal.emoji) \(thermal.description)"))
        print(line)
    }

    func printExtended() {
        let diskSummary = "\(diskCapacityGB) GB \(diskType)"
        let line = String(repeating: "─", count: 50)
        print()
        print(line)
        print("  System Information (Extended)")
        print(line)
        print(dotPad("Chip", chip, width: 50))
        print(dotPad("P-Cores", String(coresPerformance), width: 50))
        print(dotPad("E-Cores", String(coresEfficiency), width: 50))
        print(dotPad("Total Cores", String(totalCores), width: 50))
        print(dotPad("RAM", "\(ramGB) GB", width: 50))
        print(dotPad("Disk", diskSummary, width: 50))
        print(dotPad("Disk Model", diskModel, width: 50))
        print(dotPad("macOS", osVersion, width: 50))
        print(dotPad("Model", modelIdentifier, width: 50))
        
        // GPU Information
        print(dotPad("GPU", gpuModel, width: 50))
        print(dotPad("GPU Cores", String(gpuCores), width: 50))
        print(dotPad("Metal", gpuMetalVersion, width: 50))
        
        // Battery Information (if available)
        if let cycleCount = batteryCycleCount {
            print(dotPad("Battery Cycles", String(cycleCount), width: 50))
        }
        if let health = batteryHealth {
            print(dotPad("Battery Health", health, width: 50))
        }
        if let chargingStatus = batteryChargingStatus {
            print(dotPad("Battery Status", chargingStatus, width: 50))
        }
        
        print(line)
        print()
    }

    func printSensitive() {
        let diskSummary = "\(diskCapacityGB) GB \(diskType)"
        let line = String(repeating: "─", count: 50)
        print()
        print(line)
        print("  System Information (Sensitive - Includes Machine ID)")
        print(line)
        print(dotPad("Machine ID", machineId, width: 50))
        print(dotPad("Chip", chip, width: 50))
        print(dotPad("P-Cores", String(coresPerformance), width: 50))
        print(dotPad("E-Cores", String(coresEfficiency), width: 50))
        print(dotPad("Total Cores", String(totalCores), width: 50))
        print(dotPad("RAM", "\(ramGB) GB", width: 50))
        print(dotPad("Disk", diskSummary, width: 50))
        print(dotPad("Disk Model", diskModel, width: 50))
        print(dotPad("macOS", osVersion, width: 50))
        print(dotPad("Model", modelIdentifier, width: 50))
        
        // GPU Information
        print(dotPad("GPU", gpuModel, width: 50))
        print(dotPad("GPU Cores", String(gpuCores), width: 50))
        print(dotPad("Metal", gpuMetalVersion, width: 50))
        
        // Battery Information (if available)
        if let cycleCount = batteryCycleCount {
            print(dotPad("Battery Cycles", String(cycleCount), width: 50))
        }
        if let health = batteryHealth {
            print(dotPad("Battery Health", health, width: 50))
        }
        if let chargingStatus = batteryChargingStatus {
            print(dotPad("Battery Status", chargingStatus, width: 50))
        }
        
        print(line)
        print()
    }

    private func dotPad(_ label: String, _ value: String, width: Int = 44) -> String {
        // Format: "  Label .......... Value"
        let prefix = "  \(label) "
        let suffix = " \(value)"
        let dotsCount = max(2, width - prefix.count - suffix.count)
        return prefix + String(repeating: ".", count: dotsCount) + suffix
    }

    // MARK: - Private Helpers

    private static func getGPUInfo() -> (model: String, cores: Int, metalVersion: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPDisplaysDataType"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return ("Unknown", 0, "Unknown")
            }

            var model = "Unknown"
            var cores = 0
            var metalVersion = "Unknown"

            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("Chipset Model:") {
                    model = trimmed
                        .replacingOccurrences(of: "Chipset Model:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("Total Number of Cores:") {
                    let coresStr = trimmed
                        .replacingOccurrences(of: "Total Number of Cores:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let coreCount = Int(coresStr) {
                        cores = coreCount
                    }
                } else if trimmed.hasPrefix("Metal Support:") {
                    metalVersion = trimmed
                        .replacingOccurrences(of: "Metal Support:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
            }

            return (model, cores, metalVersion)
        } catch {
            return ("Unknown", 0, "Unknown")
        }
    }

    private static func getBatteryInfo() -> (cycleCount: Int?, health: String?, chargingStatus: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return (nil, nil, nil)
            }

            var cycleCount: Int? = nil
            var health: String? = nil
            var chargingStatus: String? = nil

            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("Cycle Count:") {
                    let countStr = trimmed
                        .replacingOccurrences(of: "Cycle Count:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let count = Int(countStr) {
                        cycleCount = count
                    }
                } else if trimmed.hasPrefix("Condition:") {
                    health = trimmed
                        .replacingOccurrences(of: "Condition:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("Charging:") {
                    chargingStatus = trimmed
                        .replacingOccurrences(of: "Charging:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
            }

            return (cycleCount, health, chargingStatus)
        } catch {
            return (nil, nil, nil)
        }
    }

    private static func getMachineId() -> String {
        // Get or create a persistent machine ID
        let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".osx-bench")
        let idFile = configDir.appendingPathComponent("machine_id")

        if let existingId = try? String(contentsOf: idFile, encoding: .utf8) {
            return existingId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Generate new ID with secure file permissions
        let newId = UUID().uuidString
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? newId.write(to: idFile, atomically: true, encoding: .utf8)
        // Set restrictive permissions on the machine ID file (owner read/write only)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: idFile.path)
        return newId
    }

    private static func getChipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var chipName = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &chipName, &size, nil, 0)
        return String(cString: chipName)
    }

    private static func getCoreCount() -> (performance: Int, efficiency: Int) {
        // Try to get Apple Silicon specific core counts
        var pCores = 0
        var eCores = 0

        var size = MemoryLayout<Int32>.size
        var value: Int32 = 0

        // Performance cores
        if sysctlbyname("hw.perflevel0.logicalcpu", &value, &size, nil, 0) == 0 {
            pCores = Int(value)
        }

        // Efficiency cores
        size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel1.logicalcpu", &value, &size, nil, 0) == 0 {
            eCores = Int(value)
        }

        // Fallback to total count if specific counts not available
        if pCores == 0 && eCores == 0 {
            size = MemoryLayout<Int32>.size
            sysctlbyname("hw.ncpu", &value, &size, nil, 0)
            pCores = Int(value)
            eCores = 0
        }

        return (pCores, eCores)
    }

    private static func getRAMSize() -> Int {
        var size = MemoryLayout<UInt64>.size
        var ram: UInt64 = 0
        sysctlbyname("hw.memsize", &ram, &size, nil, 0)
        return Int(ram / (1024 * 1024 * 1024))
    }

    private static func getOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func getModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    private static func getDiskInfo() -> (model: String, capacityGB: Int, type: String) {
        // Use diskutil to get disk information
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "disk0"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return ("Unknown", 0, "Unknown")
            }

            var model = "Unknown"
            var capacityGB = 0
            var isSSD = false

            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("Device / Media Name:") {
                    model = trimmed
                        .replacingOccurrences(of: "Device / Media Name:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("Disk Size:") {
                    // Parse size like "251.0 GB (..."
                    let sizeStr = trimmed
                        .replacingOccurrences(of: "Disk Size:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let gbRange = sizeStr.range(of: #"[\d.]+"#, options: .regularExpression) {
                        if let gb = Double(sizeStr[gbRange]) {
                            capacityGB = Int(gb.rounded())
                        }
                    }
                } else if trimmed.hasPrefix("Solid State:") {
                    isSSD = trimmed.contains("Yes")
                }
            }

            return (model, capacityGB, isSSD ? "SSD" : "HDD")
        } catch {
            return ("Unknown", 0, "Unknown")
        }
    }

    // MARK: - Privacy-Safe Export Version

    /// Returns a copy without machine ID for privacy-safe JSON exports
    func forExport() -> SystemInfoExport {
        SystemInfoExport(
            chip: chip,
            coresPerformance: coresPerformance,
            coresEfficiency: coresEfficiency,
            totalCores: totalCores,
            ramGB: ramGB,
            osVersion: osVersion,
            modelIdentifier: modelIdentifier,
            diskModel: diskModel,
            diskCapacityGB: diskCapacityGB,
            diskType: diskType
        )
    }
}

/// Privacy-safe version of SystemInfo without machine ID for exports
struct SystemInfoExport: Codable {
    let chip: String
    let coresPerformance: Int
    let coresEfficiency: Int
    let totalCores: Int
    let ramGB: Int
    let osVersion: String
    let modelIdentifier: String
    let diskModel: String
    let diskCapacityGB: Int
    let diskType: String
}
