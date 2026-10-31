import Foundation

public struct PowerSample: Sendable {
    /// CPU, ANE and DRAM come from the power manager (PMGR) channels. On M5 Max / macOS 27
    /// those counters never advance for unprivileged readers, so these are nil there.
    public let cpuWatts: Double?
    public let aneWatts: Double?
    public let dramWatts: Double?
    /// Reported by the GPU driver itself, which keeps updating without root.
    public let gpuWatts: Double
    /// Whole-machine draw from the SMC ("PSTR"), nil if the key isn't present.
    public let systemWatts: Double?

    /// CPU + GPU + ANE + DRAM when all are known.
    public var packageWatts: Double? {
        guard let cpuWatts, let aneWatts, let dramWatts else { return nil }
        return cpuWatts + gpuWatts + aneWatts + dramWatts
    }
}

public struct EnergyChannel: Sendable {
    public let group: String
    public let subgroup: String
    public let name: String
    public let unit: String
    /// Raw counter delta, in `unit`.
    public let energy: Double
    public let watts: Double
}

/// Per-component power from the private IOReport "Energy Model" group, plus total system
/// power from the SMC. Energy counters are sampled twice and the delta divided by elapsed
/// time gives watts.
///
/// The ANE has no utilization counter anywhere on macOS; its power draw is the only
/// signal of how busy it is. On M5 Max / macOS 27 that counter is frozen without root
/// (checked by scanning every IOReport channel and SMC power key under an ANE load),
/// so `aneWatts` is nil there.
public final class PowerSampler {
    private typealias CopyChannelsFn = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscriptionFn = @convention(c) (
        UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?
    ) -> OpaquePointer?
    private typealias CreateSamplesFn = @convention(c) (OpaquePointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateDeltaFn = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias GetStringFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias GetIntegerFn = @convention(c) (CFDictionary, Int32) -> Int64

    private let createSubscription: CreateSubscriptionFn
    private let createSamples: CreateSamplesFn
    private let createDelta: CreateDeltaFn
    private let getGroup: GetStringFn
    private let getSubgroup: GetStringFn
    private let getName: GetStringFn
    private let getUnit: GetStringFn
    private let getInteger: GetIntegerFn

    /// Every channel in the Energy Model group, kept so the subscription can be narrowed later.
    private let allChannels: [NSDictionary]
    private let groupTemplate: CFDictionary
    private var subscription: OpaquePointer?
    private var subscribed: CFMutableDictionary?
    private let smc: SMC?
    private var previous: (samples: CFDictionary, time: TimeInterval)?
    private var frozenSamples = 0
    private var gpuOnly = false

    /// Returns nil if IOReport isn't available or has no Energy Model channels, as on Intel Macs.
    public init?() {
        // libIOReport lives only in the dyld shared cache, but dlopen still resolves the path.
        guard let lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW),
              let copyChannels = Self.symbol("IOReportCopyChannelsInGroup", in: lib, as: CopyChannelsFn.self),
              let createSubscription = Self.symbol("IOReportCreateSubscription", in: lib, as: CreateSubscriptionFn.self),
              let createSamples = Self.symbol("IOReportCreateSamples", in: lib, as: CreateSamplesFn.self),
              let createDelta = Self.symbol("IOReportCreateSamplesDelta", in: lib, as: CreateDeltaFn.self),
              let getGroup = Self.symbol("IOReportChannelGetGroup", in: lib, as: GetStringFn.self),
              let getSubgroup = Self.symbol("IOReportChannelGetSubGroup", in: lib, as: GetStringFn.self),
              let getName = Self.symbol("IOReportChannelGetChannelName", in: lib, as: GetStringFn.self),
              let getUnit = Self.symbol("IOReportChannelGetUnitLabel", in: lib, as: GetStringFn.self),
              let getInteger = Self.symbol("IOReportSimpleGetIntegerValue", in: lib, as: GetIntegerFn.self),
              let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue()
        else { return nil }

        self.createSubscription = createSubscription
        self.createSamples = createSamples
        self.createDelta = createDelta
        self.getGroup = getGroup
        self.getSubgroup = getSubgroup
        self.getName = getName
        self.getUnit = getUnit
        self.getInteger = getInteger
        self.groupTemplate = channels
        self.allChannels = (channels as NSDictionary)["IOReportChannels"] as? [NSDictionary] ?? []
        self.smc = SMC()

        // The group has ~360 channels (per-core detail included); keep only the totals.
        guard !allChannels.isEmpty, subscribe(where: { Self.componentName($0) != nil }) else { return nil }
    }

    deinit {
        if let subscription { Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(subscription)).release() }
    }

    private func subscribe(where include: (String) -> Bool) -> Bool {
        guard let desired = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, groupTemplate) else { return false }
        (desired as NSMutableDictionary)["IOReportChannels"] = allChannels.filter { channel in
            guard let name = (channel["LegendChannel"] as? [Any])?.last as? String else { return false }
            return include(name)
        }
        var out: Unmanaged<CFMutableDictionary>?
        guard let new = createSubscription(nil, desired, &out, 0, nil), let subscribed = out?.takeRetainedValue() else {
            return false
        }
        if let subscription { Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(subscription)).release() }
        self.subscription = new
        self.subscribed = subscribed
        previous = nil
        return true
    }

    /// The first call only primes the counters and returns nil.
    public func sample() -> PowerSample? {
        let channels = readChannels()
        guard !channels.isEmpty else { return nil }
        var cpu = 0.0, gpu = 0.0, ane = 0.0, dram = 0.0
        var cpuCounterMoved = false
        for channel in channels {
            switch Self.componentName(channel.name) {
            case "CPU":
                cpu += channel.watts
                if channel.energy != 0 { cpuCounterMoved = true }
            case "GPU": gpu += channel.watts
            case "ANE": ane += channel.watts
            case "DRAM": dram += channel.watts
            default: break
            }
        }
        // A running CPU never uses exactly zero energy, so a zero delta means the PMGR
        // counters are frozen and its ANE/DRAM figures can't be trusted either. Once that's
        // clear, stop sampling those channels: IOReport sampling is the costly part here.
        let pmgrLive = cpuCounterMoved && !gpuOnly
        if !pmgrLive, !gpuOnly {
            frozenSamples += 1
            if frozenSamples >= 3, subscribe(where: { Self.componentName($0) == "GPU" }) { gpuOnly = true }
        }
        return PowerSample(cpuWatts: pmgrLive ? cpu : nil, aneWatts: pmgrLive ? ane : nil,
                           dramWatts: pmgrLive ? dram : nil, gpuWatts: gpu,
                           systemWatts: smc?.float("PSTR"))
    }

    /// Every Energy Model channel with its power over the last interval. Empty on the first call.
    public func readChannels() -> [EnergyChannel] {
        let now = ProcessInfo.processInfo.systemUptime
        guard let subscription, let subscribed,
              let current = createSamples(subscription, subscribed, nil)?.takeRetainedValue() else { return [] }
        defer { previous = (current, now) }
        guard let previous, now > previous.time,
              let delta = createDelta(previous.samples, current, nil)?.takeRetainedValue(),
              let items = (delta as NSDictionary)["IOReportChannels"] as? [CFDictionary] else { return [] }

        let seconds = now - previous.time
        return items.map { item in
            let unit = getUnit(item)?.takeUnretainedValue() as String? ?? ""
            let energy = Double(getInteger(item, 0))
            return EnergyChannel(
                group: getGroup(item)?.takeUnretainedValue() as String? ?? "",
                subgroup: getSubgroup(item)?.takeUnretainedValue() as String? ?? "",
                name: getName(item)?.takeUnretainedValue() as String? ?? "",
                unit: unit,
                energy: energy,
                watts: energy * Self.joules(perUnit: unit) / seconds
            )
        }
    }

    /// Maps a top-level Energy Model channel to its component. Names seen across chips:
    /// "CPU Energy" (or "DIE_n_CPU Energy" on Ultra), "GPU Energy", "ANE"/"ANE0"/"ANE0_n",
    /// "DRAM"/"DRAM0". Per-core and SRAM sub-channels return nil.
    private static func componentName(_ name: String) -> String? {
        if name.hasSuffix("CPU Energy") { return "CPU" }
        if name == "GPU Energy" { return "GPU" }
        if name.range(of: #"^ANE\d*(_\d+)?$"#, options: .regularExpression) != nil { return "ANE" }
        if name.range(of: #"^DRAM\d*(_\d+)?$"#, options: .regularExpression) != nil { return "DRAM" }
        return nil
    }

    private static func joules(perUnit unit: String) -> Double {
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "mJ": 1e-3
        case "uJ", "µJ": 1e-6
        case "nJ": 1e-9
        default: 0
        }
    }

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer, as: T.Type) -> T? {
        dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
    }
}
