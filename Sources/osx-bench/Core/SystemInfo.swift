import Foundation

/// One CPU performance level as reported by the kernel (hw.perflevelN.*)
struct CoreLevel: Codable {
    let name: String   // e.g. "Performance", "Efficiency"
    let count: Int

    /// Single-letter abbreviation used in compact output (e.g. "P", "E")
    var abbreviation: String {
        name.first.map { String($0).uppercased() } ?? "?"
    }
}

struct SystemInfo: Codable {
    let machineId: String
    let chip: String
    let coresPerformance: Int  // Cores in every non-efficiency level (e.g. Super + Performance)
    let coresEfficiency: Int   // Cores in the efficiency level
    let totalCores: Int
    let coreLevels: [CoreLevel]
    let ramGB: Int
    let osVersion: String
    let modelIdentifier: String
    let diskVendor: String
    let diskModel: String
    let diskCapacityGB: Int  // Decimal GB (1 GB = 10^9 bytes), as reported by diskutil
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
        let coreLevels = getCoreLevels()
        let totalCores = coreLevels.reduce(0) { $0 + $1.count }
        let eCores = efficiencyCoreCount(in: coreLevels)
        let ram = getRAMSize()
        let os = getOSVersion()
        let model = getModelIdentifier()
        let diskInfo = getDiskInfo()
        let gpuInfo = getGPUInfo()
        let batteryInfo = getBatteryInfo()

        return SystemInfo(
            machineId: machineId,
            chip: chip,
            coresPerformance: totalCores - eCores,
            coresEfficiency: eCores,
            totalCores: totalCores,
            coreLevels: coreLevels,
            ramGB: ram,
            osVersion: os,
            modelIdentifier: model,
            diskVendor: diskInfo.vendor,
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

    // MARK: - Display

    /// Compact core layout, e.g. "4P + 4E (8 total)"
    var coreSummary: String {
        let layout = coreLevels.map { "\($0.count)\($0.abbreviation)" }.joined(separator: " + ")
        return coreLevels.count > 1 ? "\(layout) (\(totalCores) total)" : "\(totalCores) cores"
    }

    /// Disk capacity, e.g. "251 GB" or "1 TB" / "2.5 TB"
    var diskCapacityDescription: String {
        guard diskCapacityGB >= 1000 else { return "\(diskCapacityGB) GB" }
        let tb = Double(diskCapacityGB) / 1000
        return tb.rounded() == tb ? "\(Int(tb)) TB" : String(format: "%.1f TB", tb)
    }

    /// Disk summary, e.g. "251 GB SSD"
    var diskSummary: String {
        "\(diskCapacityDescription) \(diskType)"
    }

    func printBrief() {
        let thermal = ThermalMonitor.currentState()
        let line = String(repeating: "─", count: 44)
        print(line)
        print("  System Information")
        print(line)
        print(dotPad("Chip", chip))
        print(dotPad("Cores", coreSummary))
        print(dotPad("RAM", "\(ramGB) GB"))
        print(dotPad("Disk", diskSummary))
        print(dotPad("Disk Brand", diskVendor))
        print(dotPad("Disk Model", diskModel))
        print(dotPad("macOS", osVersion))
        print(dotPad("Thermal", "\(thermal.emoji) \(thermal.description)"))
        print(line)
    }

    func printExtended() {
        printDetailed(title: "System Information (Extended)", includeMachineId: false)
    }

    func printSensitive() {
        printDetailed(title: "System Information (Sensitive - Includes Machine ID)", includeMachineId: true)
    }

    private func printDetailed(title: String, includeMachineId: Bool) {
        let width = 50
        let line = String(repeating: "─", count: width)
        print()
        print(line)
        print("  \(title)")
        print(line)
        if includeMachineId {
            print(dotPad("Machine ID", machineId, width: width))
        }
        print(dotPad("Chip", chip, width: width))
        for level in coreLevels {
            print(dotPad("\(level.name) Cores", String(level.count), width: width))
        }
        print(dotPad("Total Cores", String(totalCores), width: width))
        print(dotPad("RAM", "\(ramGB) GB", width: width))
        print(dotPad("Disk", diskSummary, width: width))
        print(dotPad("Disk Brand", diskVendor, width: width))
        print(dotPad("Disk Model", diskModel, width: width))
        print(dotPad("macOS", osVersion, width: width))
        print(dotPad("Model", modelIdentifier, width: width))

        // GPU Information
        print(dotPad("GPU", gpuModel, width: width))
        print(dotPad("GPU Cores", String(gpuCores), width: width))
        print(dotPad("Metal", gpuMetalVersion, width: width))

        // Battery Information (if available)
        if let cycleCount = batteryCycleCount {
            print(dotPad("Battery Cycles", String(cycleCount), width: width))
        }
        if let health = batteryHealth {
            print(dotPad("Battery Health", health, width: width))
        }
        if let chargingStatus = batteryChargingStatus {
            print(dotPad("Battery Charging", chargingStatus, width: width))
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

    /// Reads every CPU performance level from the kernel instead of assuming a fixed
    /// P/E split, so chips with renamed or additional core tiers are reported correctly.
    private static func getCoreLevels() -> [CoreLevel] {
        let levelCount = sysctlInt("hw.nperflevels") ?? 0

        var levels: [CoreLevel] = []
        for index in 0..<levelCount {
            guard let count = sysctlInt("hw.perflevel\(index).logicalcpu"), count > 0 else { continue }
            let name = sysctlString("hw.perflevel\(index).name") ?? (index == 0 ? "Performance" : "Efficiency")
            levels.append(CoreLevel(name: name, count: count))
        }

        // Fallback to total count if per-level counts are not available
        if levels.isEmpty {
            levels = [CoreLevel(name: "CPU", count: sysctlInt("hw.ncpu") ?? 1)]
        }
        return levels
    }

    /// Cores in the efficiency tier: the level the kernel names "Efficiency",
    /// or the slowest (last) level if none carries that name.
    /// On a 2S + 4P + 6E chip this returns 6, so Super and Performance count as performance cores.
    private static func efficiencyCoreCount(in levels: [CoreLevel]) -> Int {
        guard levels.count > 1 else { return 0 }
        let named = levels.filter { $0.name.caseInsensitiveCompare("Efficiency") == .orderedSame }
        if !named.isEmpty {
            return named.reduce(0) { $0 + $1.count }
        }
        return levels.last?.count ?? 0
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
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

    private static func runDiskutil(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func diskutilValue(_ key: String, in output: String) -> String? {
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key):") {
                return String(trimmed.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Physical disk backing the boot volume (where the disk benchmark writes its temp files).
    /// APFS volumes live on a synthesized container, so follow "APFS Physical Store" back to the device.
    private static func getBootPhysicalDisk() -> String {
        guard let output = runDiskutil(["info", "/"]) else { return "disk0" }
        let store = diskutilValue("APFS Physical Store", in: output) ?? diskutilValue("Part of Whole", in: output)
        guard let store = store,
              let range = store.range(of: #"^disk\d+"#, options: .regularExpression) else {
            return "disk0"
        }
        return String(store[range])
    }

    private static func getDiskInfo() -> (vendor: String, model: String, capacityGB: Int, type: String) {
        guard let output = runDiskutil(["info", getBootPhysicalDisk()]) else {
            return ("Unknown", "Unknown", 0, "Unknown")
        }

        let model = diskutilValue("Device / Media Name", in: output) ?? "Unknown"
        let isSSD = diskutilValue("Solid State", in: output)?.hasPrefix("Yes") ?? false

        // "Disk Size: 251.0 GB (251000193024 Bytes) (...)" - use the exact byte count
        var capacityGB = 0
        if let size = diskutilValue("Disk Size", in: output),
           let match = size.range(of: #"\((\d+) Bytes\)"#, options: .regularExpression) {
            let bytes = Double(size[match].filter(\.isNumber)) ?? 0
            capacityGB = Int((bytes / 1_000_000_000).rounded())
        }

        return (diskVendor(fromModel: model), model, capacityGB, isSSD ? "SSD" : "HDD")
    }

    /// Derives the manufacturer from the drive's media name (e.g. "APPLE SSD AP0256Q" -> "Apple")
    static func diskVendor(fromModel model: String) -> String {
        let knownVendors: [String: String] = [
            "APPLE": "Apple", "SAMSUNG": "Samsung", "WDC": "Western Digital", "WD": "Western Digital",
            "SANDISK": "SanDisk", "CRUCIAL": "Crucial", "CT": "Crucial", "KINGSTON": "Kingston",
            "SEAGATE": "Seagate", "ST": "Seagate", "TOSHIBA": "Toshiba", "KIOXIA": "Kioxia",
            "INTEL": "Intel", "SK": "SK hynix", "HYNIX": "SK hynix", "SABRENT": "Sabrent",
            "LACIE": "LaCie", "OWC": "OWC", "TEAM": "Team Group", "LEXAR": "Lexar", "MICRON": "Micron",
        ]
        let tokens = model.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
        guard let first = tokens.first, model != "Unknown" else { return "Unknown" }

        let key = first.uppercased()
        if let vendor = knownVendors[key] {
            return vendor
        }
        // Bare part numbers with a vendor prefix, e.g. "CT1000P3SSD8" (Crucial), "ST2000DM008" (Seagate)
        let prefix = String(key.prefix(2))
        if key.dropFirst(2).first?.isNumber == true, let vendor = knownVendors[prefix] {
            return vendor
        }
        // Otherwise assume the first word is the brand ("Sabrent Rocket 4" -> "Sabrent")
        guard tokens.count > 1 else { return "Unknown" }
        return first.prefix(1).uppercased() + first.dropFirst().lowercased()
    }

    // MARK: - Privacy-Safe Export Version

    /// Returns a copy without machine ID for privacy-safe JSON exports
    func forExport() -> SystemInfoExport {
        SystemInfoExport(
            chip: chip,
            coresPerformance: coresPerformance,
            coresEfficiency: coresEfficiency,
            totalCores: totalCores,
            coreLevels: coreLevels,
            ramGB: ramGB,
            osVersion: osVersion,
            modelIdentifier: modelIdentifier,
            diskVendor: diskVendor,
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
    let coreLevels: [CoreLevel]
    let ramGB: Int
    let osVersion: String
    let modelIdentifier: String
    let diskVendor: String
    let diskModel: String
    let diskCapacityGB: Int
    let diskType: String
}
