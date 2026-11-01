import Foundation

/// One reading of every metric, shaped for agents: units are in the field names, and a field
/// is left out when this Mac doesn't expose it.
public struct MetricsSnapshot: Encodable, Sendable {
    public struct Cluster: Encodable, Sendable {
        let name: String
        let coreCount: Int
        let usagePercent: Double
    }

    public struct CPU: Encodable, Sendable {
        let usagePercent: Double
        let temperatureCelsius: Double?
        let clusters: [Cluster]
        let perCorePercent: [Double]
    }

    public struct GPU: Encodable, Sendable {
        let usagePercent: Double?
        let temperatureCelsius: Double?
    }

    public struct Memory: Encodable, Sendable {
        let totalBytes: UInt64
        let usedBytes: UInt64
        let compressedBytes: UInt64
        let usedPercent: Double
        let pressure: String
    }

    public struct Network: Encodable, Sendable {
        let downloadBytesPerSecond: Double
        let uploadBytesPerSecond: Double
    }

    public struct Battery: Encodable, Sendable {
        let levelPercent: Double
        let charging: Bool
        let onAc: Bool
        let minutesRemaining: Int?
        /// Positive while charging, negative while draining.
        let watts: Double?
        let temperatureCelsius: Double?
        let cycleCount: Int?
    }

    public struct Power: Encodable, Sendable {
        let systemWatts: Double?
        let gpuWatts: Double
        let cpuWatts: Double?
        let aneWatts: Double?
        let dramWatts: Double?
    }

    let timestamp: String
    let chip: String
    let cpu: CPU
    let gpu: GPU
    let memory: Memory
    let network: Network
    let battery: Battery?
    let power: Power?

    /// One line unless `pretty`, so it also fits in a newline-delimited stream.
    public func json(pretty: Bool = false) -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
                                          : [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Takes a one-off reading for callers without a running sample loop.
public final class MetricsCollector {
    private let cpuSampler = CPUSampler()
    private let gpuSampler = GPUSampler()
    private let memorySampler = MemorySampler()
    private let networkSampler = NetworkSampler()
    private let batterySampler = BatterySampler()
    private let temperatureSampler = TemperatureSampler()
    private let powerSampler = PowerSampler()

    public init() {}

    /// Takes about a second: CPU, network, and power are rates, so they need two samples.
    public func collect() -> MetricsSnapshot {
        _ = cpuSampler.sample()
        _ = networkSampler.sample()
        _ = powerSampler?.sample()
        Thread.sleep(forTimeInterval: 1)

        let cpu = cpuSampler.sample()
        let gpu = gpuSampler.sample()
        let memory = memorySampler.sample()
        let network = networkSampler.sample()
        let battery = batterySampler.sample()
        let power = powerSampler?.sample()
        let temperature = temperatureSampler.sample()

        return MetricsSnapshot(
            timestamp: Date().ISO8601Format(),
            chip: SystemInfo.chipName,
            cpu: .init(
                usagePercent: Self.percent(cpu.total),
                temperatureCelsius: temperature.cpu.map(Self.rounded),
                clusters: cpuSampler.clusters.map { cluster in
                    let cores = cpu.perCore[cluster.cores]
                    return .init(name: cluster.name, coreCount: cores.count,
                                 usagePercent: Self.percent(cores.reduce(0, +) / Double(max(cores.count, 1))))
                },
                perCorePercent: cpu.perCore.map(Self.percent)
            ),
            gpu: .init(usagePercent: gpu.map { Self.percent($0.utilization) },
                       temperatureCelsius: temperature.gpu.map(Self.rounded)),
            memory: .init(totalBytes: memory.total, usedBytes: memory.used, compressedBytes: memory.compressed,
                          usedPercent: Self.percent(memory.usedFraction), pressure: Self.name(memory.pressure)),
            network: .init(downloadBytesPerSecond: network.downloadBytesPerSecond.rounded(),
                           uploadBytesPerSecond: network.uploadBytesPerSecond.rounded()),
            battery: battery.map { battery in
                .init(levelPercent: Self.percent(battery.level),
                      // Same rule as the panel: a heavy load can drain the battery while IOPS says charging.
                      charging: battery.isCharging && (battery.watts ?? 1) > 0,
                      onAc: battery.isOnAC, minutesRemaining: battery.minutesRemaining,
                      watts: battery.watts.map(Self.rounded),
                      temperatureCelsius: battery.temperatureCelsius.map(Self.rounded),
                      cycleCount: battery.cycleCount)
            },
            power: power.map { power in
                .init(systemWatts: power.systemWatts.map(Self.rounded), gpuWatts: Self.rounded(power.gpuWatts),
                      cpuWatts: power.cpuWatts.map(Self.rounded), aneWatts: power.aneWatts.map(Self.rounded),
                      dramWatts: power.dramWatts.map(Self.rounded))
            }
        )
    }

    private static func percent(_ fraction: Double) -> Double {
        rounded(fraction * 100)
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func name(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: "normal"
        case .warning: "warning"
        case .critical: "critical"
        }
    }
}
