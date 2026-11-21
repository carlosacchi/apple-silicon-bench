import Foundation
import Testing
@testable import osx_bench

@Suite("SystemInfo")
struct SystemInfoTests {
    private func levels(_ pairs: [(String, Int)]) -> [CoreLevel] {
        pairs.map { CoreLevel(name: $0.0, count: $0.1) }
    }

    private func systemInfo(gpuModel: String = "Apple M1", gpuCores: Int = 7) -> SystemInfo {
        SystemInfo(
            machineId: "secret-machine-id", chip: "Apple M1", coresPerformance: 4, coresEfficiency: 4,
            totalCores: 8, coreLevels: levels([("Performance", 4), ("Efficiency", 4)]), ramGB: 8,
            osVersion: "27.2.1", modelIdentifier: "MacBookAir10,1", diskVendor: "Apple",
            diskModel: "APPLE SSD AP0256Q", diskCapacityGB: 251, diskType: "SSD",
            gpuModel: gpuModel, gpuCores: gpuCores, gpuMetalVersion: "Metal 4",
            batteryCycleCount: nil, batteryHealth: nil, batteryChargingStatus: nil
        )
    }

    // MARK: - Efficiency core count

    @Test func test_efficiencyCoreCount_performanceAndEfficiency_countsEfficiencyLevel() {
        // M1: 4P + 4E
        #expect(SystemInfo.efficiencyCoreCount(in: levels([("Performance", 4), ("Efficiency", 4)])) == 4)
    }

    @Test func test_efficiencyCoreCount_threeTiers_countsOnlyEfficiency() {
        // M6: 2S + 4P + 6E
        let m6 = levels([("Super", 2), ("Performance", 4), ("Efficiency", 6)])
        #expect(SystemInfo.efficiencyCoreCount(in: m6) == 6)
    }

    @Test func test_efficiencyCoreCount_noEfficiencyTier_returnsZero() {
        // M5 Pro: 6S + 12P, no efficiency cores (v2.5.0 exported 6 + 12E)
        let m5Pro = levels([("Super", 6), ("Performance", 12)])
        #expect(SystemInfo.efficiencyCoreCount(in: m5Pro) == 0)
    }

    @Test func test_efficiencyCoreCount_singleLevel_returnsZero() {
        #expect(SystemInfo.efficiencyCoreCount(in: levels([("CPU", 8)])) == 0)
    }

    @Test func test_efficiencyCoreCount_nameIsCaseInsensitive() {
        #expect(SystemInfo.efficiencyCoreCount(in: levels([("Performance", 4), ("efficiency", 2)])) == 2)
    }

    // MARK: - Export

    @Test func test_forExport_includesGPUAndOmitsMachineId() throws {
        let export = systemInfo().forExport()
        #expect(export.gpuModel == "Apple M1")
        #expect(export.gpuCores == 7)

        let json = String(decoding: try JSONEncoder().encode(export), as: UTF8.self)
        #expect(json.contains("\"gpuCores\":7"))
        #expect(!json.contains("secret-machine-id"))
    }

    @Test func test_forExport_unknownGPU_exportsNil() {
        let export = systemInfo(gpuModel: "Unknown", gpuCores: 0).forExport()
        #expect(export.gpuModel == nil)
        #expect(export.gpuCores == nil)
    }

    @Test func test_exportJSON_writesMetadataAndGPU() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx-bench-export-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let results = BenchmarkResults(benchmarks: [])
        let scores = BenchmarkScores(cpuSingleCore: 0, cpuMultiCore: 0, memory: 0, disk: 0, gpu: 0, total: 0)
        try ResultsExporter.exportJSON(results: results, scores: scores, systemInfo: systemInfo(),
                                       quickMode: true, passes: 3, to: url.path)

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let metadata = try #require(object?["metadata"] as? [String: Any])
        #expect(metadata["version"] as? String == AppInfo.version)
        #expect(metadata["quickMode"] as? Bool == true)
        #expect(metadata["passes"] as? Int == 3)
        let info = try #require(object?["systemInfo"] as? [String: Any])
        #expect(info["gpuCores"] as? Int == 7)
        #expect(info["machineId"] == nil)
    }
}
