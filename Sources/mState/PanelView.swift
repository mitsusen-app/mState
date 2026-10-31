import Charts
import MonitorCore
import SwiftUI

// No animations in this panel, on purpose. Values change every second, and the panel's
// vibrancy window renders on the CPU: `.contentTransition(.numericText())` (it blurs digits)
// cost ~14% CPU and leaked ~4 MB/s, and the implicit bar/meter animations another ~6%.
// Without them the open panel costs ~1%. Measure with MSTATE_WINDOW=1 before adding any.
struct PanelView: View {
    let store: MetricsStore

    var body: some View {
        VStack(spacing: 8) {
            header
            HStack(spacing: 8) {
                UsageCard(title: "CPU", fraction: store.cpu?.total ?? 0,
                          temperature: store.temperature?.cpu, history: store.cpuHistory)
                UsageCard(title: "GPU", fraction: store.gpu?.utilization ?? 0,
                          temperature: store.temperature?.gpu, history: store.gpuHistory)
            }
            if let power = store.power { PowerCard(power: power, history: store.systemPowerHistory) }
            if let memory = store.memory { MemoryCard(memory: memory) }
            CoresCard(clusters: store.clusters, perCore: store.cpu?.perCore ?? [])
            NetworkCard(network: store.network, down: store.downloadHistory, up: store.uploadHistory)
            if let battery = store.battery { BatteryCard(battery: battery) }
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            // Intel brand strings are long, e.g. "Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz".
            Text(SystemInfo.chipName).font(.system(size: 13, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            Text(store.clusters.map { "\($0.cores.count) \($0.name)" }.joined(separator: " · "))
                .caption()
        }
        .padding(.horizontal, 2)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Cards

private struct UsageCard: View {
    let title: String
    let fraction: Double
    let temperature: Double?
    let history: History

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(title).caption()
                Spacer()
                Text(Format.temperature(temperature))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Level.temperature(temperature))
            }
            BigValue(value: Format.percent(fraction), unit: "%", color: Level.usage(fraction))
            Sparkline(values: history.values, capacity: history.capacity, maxValue: 1)
                .frame(height: 28)
        }
    }
}

private struct PowerCard: View {
    let power: PowerSample
    let history: History

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("POWER").caption()
                Spacer()
                Text("SYSTEM").caption()
            }
            HStack(alignment: .bottom, spacing: 12) {
                BigValue(value: power.systemWatts.map { String(format: "%.1f", $0) } ?? "—", unit: " W", color: .primary)
                    .fixedSize()
                Sparkline(values: history.values, capacity: history.capacity,
                          maxValue: max(history.values.max() ?? 0, 20))
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
            }
            HStack(spacing: 14) {
                part("GPU", power.gpuWatts)
                part("CPU", power.cpuWatts)
                part("ANE", power.aneWatts)
                part("DRAM", power.dramWatts)
                Spacer(minLength: 0)
            }
        }
    }

    private func part(_ label: String, _ watts: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).caption()
            Text(watts.map { String(format: "%.1f W", $0) } ?? "—")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(watts == nil ? .tertiary : .primary)
        }
        .fixedSize()
        .help(watts == nil ? "This Mac doesn't expose \(label) power without root." : "")
    }
}

private struct MemoryCard: View {
    let memory: MemorySample

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("MEMORY").caption()
                Spacer()
                Text(pressureLabel).caption().foregroundStyle(pressureColor)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                BigValue(value: Format.gigabytes(memory.used), unit: " / \(Format.gigabytes(memory.total)) GB",
                         color: .primary)
                Spacer()
                Text("\(Format.gigabytes(memory.compressed)) GB COMPRESSED")
                    .caption()
                    .opacity(memory.compressed > 0 ? 1 : 0)
            }
            Meter(fraction: memory.usedFraction, color: pressureColor)
        }
    }

    private var pressureLabel: String {
        switch memory.pressure {
        case .normal: "PRESSURE NORMAL"
        case .warning: "PRESSURE WARN"
        case .critical: "PRESSURE CRITICAL"
        }
    }

    private var pressureColor: Color {
        switch memory.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

private struct CoresCard: View {
    let clusters: [CoreCluster]
    let perCore: [Double]

    private let barSpacing: CGFloat = 2
    private let clusterGap: CGFloat = 10
    private let barHeight: CGFloat = 26

    var body: some View {
        Card {
            Text("CORES").caption()
            GeometryReader { geo in
                // Every bar gets the same width, so wider clusters take proportionally more room.
                let total = CGFloat(clusters.reduce(0) { $0 + $1.cores.count })
                let gaps = CGFloat(clusters.count - 1) * clusterGap + (total - CGFloat(clusters.count)) * barSpacing
                let barWidth = max(1, (geo.size.width - gaps) / max(total, 1))
                HStack(alignment: .top, spacing: clusterGap) {
                    ForEach(clusters, id: \.name) { cluster in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .bottom, spacing: barSpacing) {
                                ForEach(Array(cluster.cores), id: \.self) { core in
                                    bar(core < perCore.count ? perCore[core] : 0, width: barWidth)
                                }
                            }
                            Text(cluster.name.uppercased()).caption().lineLimit(1).fixedSize()
                        }
                    }
                }
            }
            .frame(height: barHeight + 16)
        }
    }

    private func bar(_ value: Double, width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.06))
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Level.usage(value) == .primary ? Color.primary.opacity(0.55) : Level.usage(value))
                .frame(height: max(1.5, barHeight * value))
        }
        .frame(width: width, height: barHeight)
    }
}

private struct NetworkCard: View {
    let network: NetworkSample?
    let down: History
    let up: History

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NETWORK").caption()
                    rate("arrow.down", network?.downloadBytesPerSecond ?? 0)
                    rate("arrow.up", network?.uploadBytesPerSecond ?? 0)
                }
                Spacer(minLength: 12)
                MirrorChart(top: down, bottom: up)
                    .frame(width: 130, height: 40)
            }
        }
    }

    private func rate(_ symbol: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            Text(Format.rate(value)).font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}

private struct BatteryCard: View {
    let battery: BatterySample

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("BATTERY").caption()
                Spacer()
                if let cycles = battery.cycleCount { Text("CYCLE \(cycles)").caption() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BigValue(value: Format.percent(battery.level), unit: "%",
                         color: battery.level < 0.15 && !battery.isOnAC ? .red : .primary)
                if let watts = battery.watts {
                    Text(String(format: "%+.1f W", watts))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(watts > 0 ? .green : .secondary)
                }
                Spacer()
                Text(status).caption()
            }
            Meter(fraction: battery.level, color: isCharging ? .green : .primary.opacity(0.55))
        }
    }

    /// IOPS can report "charging" while a heavy load draws more than the adapter supplies;
    /// the measured current is the better signal.
    private var isCharging: Bool {
        battery.isCharging && (battery.watts ?? 1) > 0
    }

    private var status: String {
        let time = battery.minutesRemaining.map(Format.duration(minutes:))
        if isCharging { return time.map { "\($0) TO FULL" } ?? "CHARGING" }
        if battery.isOnAC { return (battery.watts ?? 0) < -0.5 ? "ON AC · DRAINING" : "ON AC" }
        return time.map { "\($0) LEFT" } ?? "ON BATTERY"
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct BigValue: View {
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(value)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
            Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

private struct Meter: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

private struct Sparkline: View {
    let values: [Double]
    let capacity: Int
    let maxValue: Double

    var body: some View {
        // Right-align the data so new samples always enter from the right edge.
        let offset = capacity - values.count
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("t", index + offset), y: .value("v", value))
                .foregroundStyle(Color.primary.opacity(0.08))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", index + offset), y: .value("v", value))
                .foregroundStyle(Color.primary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1.2))
                .interpolationMethod(.monotone)
        }
        .chartXScale(domain: 0...(capacity - 1))
        .chartYScale(domain: 0...maxValue)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

/// Download above the baseline, upload mirrored below it, on a shared scale.
private struct MirrorChart: View {
    let top: History
    let bottom: History

    var body: some View {
        let peak = max(top.values.max() ?? 0, bottom.values.max() ?? 0, 10_240)
        let offset = top.capacity - top.values.count
        Chart {
            ForEach(Array(top.values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("t", index + offset), y: .value("v", value / peak), series: .value("s", "down"))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(bottom.values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("t", index + offset), y: .value("v", -value / peak), series: .value("s", "up"))
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("zero", 0)).foregroundStyle(Color.primary.opacity(0.15)).lineStyle(StrokeStyle(lineWidth: 0.5))
        }
        .chartXScale(domain: 0...(top.capacity - 1))
        .chartYScale(domain: -1...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

private extension Text {
    /// Small uppercase label style used for every card title.
    func caption() -> some View {
        font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
    }
}
