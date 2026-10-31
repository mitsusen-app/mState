import Foundation

public struct TemperatureSample: Sendable {
    public let cpu: Double?
    public let gpu: Double?
}

/// CPU and GPU die temperatures. SMC is the primary source; HID sensors are the fallback for
/// chips whose keys aren't in the table below.
public final class TemperatureSampler {
    private let smc: SMC?
    private let cpuKeys: [(String, SMC.KeyInfo)]
    private let gpuKeys: [(String, SMC.KeyInfo)]
    private let hid: HIDTemperatureSensors?

    public init() {
        let smc = SMC()
        let table = Self.table(for: SystemInfo.appleSiliconGeneration)
        var cpu = Self.existing(table.cpu, in: smc)
        var gpu = Self.existing(table.gpu, in: smc)
        if SystemInfo.appleSiliconGeneration == nil {
            // Intel lists are in order of preference, and mix die and proximity sensors
            // that shouldn't be averaged together.
            cpu = Array(cpu.prefix(1))
            gpu = Array(gpu.prefix(1))
        } else if cpu.isEmpty || gpu.isEmpty, let smc {
            // A chip newer than the table. Keys for each group sit in the same prefix so far.
            let scan = Self.scan(smc)
            if cpu.isEmpty { cpu = Self.spread(scan.filter { $0.0.hasPrefix("Tp0") }, limit: 18) }
            if gpu.isEmpty { gpu = Self.spread(scan.filter { $0.0.hasPrefix("Tg") }, limit: 12) }
        }
        self.smc = smc
        self.cpuKeys = cpu
        self.gpuKeys = gpu
        self.hid = cpu.isEmpty || gpu.isEmpty ? HIDTemperatureSensors() : nil
    }

    public func sample() -> TemperatureSample {
        let readings = hid?.read() ?? []
        return TemperatureSample(
            cpu: average(cpuKeys) ?? Self.average(readings.filter { Self.isHIDCPUSensor($0.name) }.map(\.celsius)),
            gpu: average(gpuKeys) ?? Self.average(readings.filter { Self.isHIDGPUSensor($0.name) }.map(\.celsius))
        )
    }

    /// "CPU", "GPU", or nil for keys this Mac's average doesn't use.
    public static func classify(smcKey key: String) -> String? {
        let table = table(for: SystemInfo.appleSiliconGeneration)
        if table.cpu.contains(key) { return "CPU" }
        if table.gpu.contains(key) { return "GPU" }
        return nil
    }

    // Keys per chip generation, from the exelban/stats sensor list. Only the M5 row has been
    // checked on real hardware (M5 Max); `swift run sensor-probe` prints what a Mac exposes.
    private static func table(for generation: Int?) -> (cpu: [String], gpu: [String]) {
        switch generation {
        case nil:
            return (["TC0E", "TC0F", "TC0D", "TCAD", "TC0P"], ["TCGC", "TGDD", "TG0D", "TG0P"])
        case 1:
            return (["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b", "Tp09", "Tp0T"],
                    ["Tg05", "Tg0D", "Tg0L", "Tg0T"])
        case 2:
            return (["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp1h", "Tp1t", "Tp1p", "Tp1l"],
                    ["Tg0f", "Tg0j"])
        case 3:
            return (["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
                     "Te05", "Te0L", "Te0P", "Te0S"],
                    ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"])
        case 4:
            return (["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e", "Te05", "Te0S", "Te09", "Te0H"],
                    ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"])
        default:
            // M5 and later. M6 keys are unknown, so it starts from these and falls back to a scan.
            return (["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
                     "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"],
                    ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"])
        }
    }

    public static func isHIDCPUSensor(_ name: String) -> Bool {
        name.hasPrefix("PMU tdie") || name.contains("ACC MTR")
    }

    public static func isHIDGPUSensor(_ name: String) -> Bool {
        name.contains("GPU MTR")
    }

    private static func existing(_ keys: [String], in smc: SMC?) -> [(String, SMC.KeyInfo)] {
        guard let smc else { return [] }
        return keys.compactMap { key in smc.info(key).map { (key, $0) } }
    }

    private static func scan(_ smc: SMC) -> [(String, SMC.KeyInfo)] {
        (0..<smc.keyCount).compactMap { index in
            guard let key = smc.key(at: index), key.hasPrefix("T"), let info = smc.info(key) else { return nil }
            return (key, info)
        }
    }

    private func average(_ keys: [(String, SMC.KeyInfo)]) -> Double? {
        guard let smc else { return nil }
        // Sensors that are powered down read near zero; leave them out of the average.
        return Self.average(keys.compactMap { smc.temperature($0.0, info: $0.1) }.filter { $0 > 1 && $0 < 150 })
    }

    private static func spread<T>(_ items: [T], limit: Int) -> [T] {
        guard items.count > limit else { return items }
        return (0..<limit).map { items[$0 * items.count / limit] }
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
