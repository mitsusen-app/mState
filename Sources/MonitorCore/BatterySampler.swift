import Foundation
import IOKit
import IOKit.ps

public struct BatterySample: Sendable {
    /// 0...1
    public let level: Double
    public let isCharging: Bool
    public let isOnAC: Bool
    /// Minutes until empty or full, whichever applies; nil while the system is still estimating.
    public let minutesRemaining: Int?
    /// Positive while charging, negative while discharging.
    public let watts: Double?
    public let temperatureCelsius: Double?
    public let cycleCount: Int?
}

public final class BatterySampler {
    public init() {}

    /// Returns nil on Macs without a battery.
    public func sample() -> BatterySample? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.lazy.compactMap({
                  IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
              }).first(where: { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType })
        else { return nil }

        let current = source[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = source[kIOPSMaxCapacityKey] as? Int ?? 100
        let charging = source[kIOPSIsChargingKey] as? Bool ?? false
        let onAC = source[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        let minutes = (charging ? source[kIOPSTimeToFullChargeKey] : source[kIOPSTimeToEmptyKey]) as? Int
        let smart = Self.smartBatteryProperties()

        var watts: Double?
        if let mV = smart?["Voltage"] as? NSNumber, let mA = smart?["Amperage"] as? NSNumber {
            // Amperage is a signed value stored in an unsigned field; intValue restores the sign.
            watts = mV.doubleValue * Double(mA.intValue) / 1_000_000
        }
        return BatterySample(
            level: max == 0 ? 0 : Double(current) / Double(max),
            isCharging: charging,
            isOnAC: onAC,
            minutesRemaining: (minutes ?? -1) >= 0 ? minutes : nil,
            watts: watts,
            temperatureCelsius: (smart?["Temperature"] as? NSNumber).map { $0.doubleValue / 100 },
            cycleCount: (smart?["CycleCount"] as? NSNumber)?.intValue
        )
    }

    private static func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return props?.takeRetainedValue() as? [String: Any]
    }
}
