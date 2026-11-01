import Foundation
import MonitorCore
import Observation

/// Fixed-length rolling window for sparklines.
struct History {
    let capacity: Int
    private(set) var values: [Double] = []

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }
}

@MainActor
@Observable
final class MetricsStore {
    static let historyLength = 60

    private(set) var cpu: CPUSample?
    private(set) var gpu: GPUSample?
    private(set) var memory: MemorySample?
    private(set) var network: NetworkSample?
    private(set) var battery: BatterySample?
    private(set) var temperature: TemperatureSample?
    private(set) var power: PowerSample?

    private(set) var cpuHistory = History(capacity: historyLength)
    private(set) var gpuHistory = History(capacity: historyLength)
    private(set) var downloadHistory = History(capacity: historyLength)
    private(set) var uploadHistory = History(capacity: historyLength)
    private(set) var systemPowerHistory = History(capacity: historyLength)

    var agentAccess = AgentAccess.isEnabled {
        didSet { AgentAccess.isEnabled = agentAccess }
    }

    let clusters: [CoreCluster]

    @ObservationIgnored private let cpuSampler = CPUSampler()
    @ObservationIgnored private let gpuSampler = GPUSampler()
    @ObservationIgnored private let memorySampler = MemorySampler()
    @ObservationIgnored private let networkSampler = NetworkSampler()
    @ObservationIgnored private let batterySampler = BatterySampler()
    @ObservationIgnored private let temperatureSampler = TemperatureSampler()
    @ObservationIgnored private let powerSampler = PowerSampler()
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var loop: Task<Void, Never>?

    init() {
        clusters = cpuSampler.clusters
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() {
        let cpu = cpuSampler.sample()
        let gpu = gpuSampler.sample()
        let network = networkSampler.sample()
        self.cpu = cpu
        self.gpu = gpu
        self.network = network
        memory = memorySampler.sample()
        if let power = powerSampler?.sample() {
            self.power = power
            systemPowerHistory.append(power.systemWatts ?? 0)
        }

        cpuHistory.append(cpu.total)
        gpuHistory.append(gpu?.utilization ?? 0)
        downloadHistory.append(network.downloadBytesPerSecond)
        uploadHistory.append(network.uploadBytesPerSecond)

        // Temperatures and battery change slowly and cost more to read, so refresh them
        // every few seconds.
        if tickCount % 3 == 0 {
            temperature = temperatureSampler.sample()
            battery = batterySampler.sample()
        }
        tickCount += 1
    }
}
