import Foundation
import MonitorCore

// Lists every temperature sensor (HID and SMC) and how mState classifies it.
// Usage: swift run sensor-probe            full listing
//        swift run sensor-probe --groups   SMC averages per key prefix, to spot which group heats under load

let groupsOnly = CommandLine.arguments.contains("--groups")

// --smc-prefix X: print every float SMC key starting with X (e.g. P for power keys).
if let flag = CommandLine.arguments.firstIndex(of: "--smc-prefix"), let prefix = CommandLine.arguments.dropFirst(flag + 1).first {
    guard let smc = SMC() else { exit(1) }
    var line: [String] = []
    for i in 0..<smc.keyCount {
        guard let key = smc.key(at: i), key.hasPrefix(prefix), let info = smc.info(key), info.type == "flt ",
              let value = smc.float(key, info: info) else { continue }
        line.append("\(key) \(String(format: "%8.3f", value))")
    }
    for row in stride(from: 0, to: line.count, by: 6) { print(line[row..<min(row + 6, line.count)].joined(separator: "   ")) }
    exit(0)
}

// --power [seconds]: list IOReport Energy Model channels and the parsed totals, every second.
if let flag = CommandLine.arguments.firstIndex(of: "--power") {
    guard let power = PowerSampler() else {
        print("IOReport Energy Model is unavailable.")
        exit(1)
    }
    let seconds = CommandLine.arguments.dropFirst(flag + 1).first.flatMap(Int.init) ?? 1
    _ = power.readChannels()
    for second in 1...seconds {
        Thread.sleep(forTimeInterval: 1)
        if second == 1 {
            // Per-core detail channels (DTL, SRAM, per-core) are skipped to keep this readable.
            print("== Energy Model channels (non-zero, first interval) ==")
            for channel in power.readChannels() where channel.energy != 0
                && !channel.name.contains("DTL") && !channel.name.contains("_") {
                print(channel.name.padding(toLength: 24, withPad: " ", startingAt: 0),
                      "[\(channel.unit)]".padding(toLength: 6, withPad: " ", startingAt: 0),
                      String(format: "raw %14.0f  %8.3f W", channel.energy, channel.watts), channel.subgroup)
            }
            print("")
            continue
        }
        guard let s = power.sample() else { continue }
        let w = { (v: Double?) in v.map { String(format: "%6.2f W", $0) } ?? "frozen" }
        print("CPU \(w(s.cpuWatts))  GPU \(w(s.gpuWatts))  ANE \(w(s.aneWatts))  DRAM \(w(s.dramWatts))  system \(w(s.systemWatts))")
    }
    exit(0)
}

func format(_ value: Double?) -> String {
    value.map { String(format: "%.1f °C", $0) } ?? "no match"
}

if !groupsOnly {
    print("== HID sensors ==")
    if let hid = HIDTemperatureSensors() {
        // Many sensors appear once per die with the same name; collapse them.
        let grouped = Dictionary(grouping: hid.read(), by: \.name)
        let width = grouped.keys.map(\.count).max() ?? 10
        for name in grouped.keys.sorted() {
            let values = grouped[name]!.map(\.celsius)
            print(name.padding(toLength: width, withPad: " ", startingAt: 0),
                  String(format: "%6.1f °C  x%d", values.reduce(0, +) / Double(values.count), values.count),
                  TemperatureSampler.isHIDCPUSensor(name) ? "CPU" : "")
        }
    } else {
        print("IOHIDEventSystemClient is unavailable.")
    }
}

guard let smc = SMC() else {
    print("AppleSMC is unavailable.")
    exit(1)
}

var found: [(key: String, value: Double)] = []
for i in 0..<smc.keyCount {
    guard let key = smc.key(at: i), key.hasPrefix("T"), let info = smc.info(key),
          let value = smc.temperature(key, info: info), value > 1, value < 150 else { continue }
    found.append((key, value))
}

if groupsOnly {
    let groups = Dictionary(grouping: found, by: { String($0.key.prefix(2)) })
    for prefix in groups.keys.sorted() {
        let values = groups[prefix]!.map(\.value)
        print(prefix, String(format: "avg %5.1f  max %5.1f  n=%d", values.reduce(0, +) / Double(values.count),
                             values.max()!, values.count))
    }
} else {
    print("\n== SMC temperature keys ==")
    // Print in columns; there are usually hundreds of keys.
    for row in stride(from: 0, to: found.count, by: 6) {
        print(found[row..<min(row + 6, found.count)].map { item in
            let tag = TemperatureSampler.classify(smcKey: item.key).map { "[\($0)]" } ?? ""
            return "\(item.key) \(String(format: "%5.1f", item.value))\(tag)".padding(toLength: 17, withPad: " ", startingAt: 0)
        }.joined(separator: " "))
    }
    print("Temperature keys: \(found.count)")
}

print("\nChip: \(SystemInfo.chipName), generation \(SystemInfo.appleSiliconGeneration.map(String.init) ?? "Intel")")
let sample = TemperatureSampler().sample()
print("\nmState reads  CPU: \(format(sample.cpu))  GPU: \(format(sample.gpu))")
