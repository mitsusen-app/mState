import Foundation
import IOKit

public struct GPUSample: Sendable {
    /// 0...1
    public let utilization: Double
}

public final class GPUSampler {
    public init() {}

    /// Reads "Device Utilization %" from the IOAccelerator's PerformanceStatistics. No root needed.
    public func sample() -> GPUSample? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: Int?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let value = stats["Device Utilization %"] as? Int else { continue }
            best = max(best ?? 0, value)
        }
        return best.map { GPUSample(utilization: Double($0) / 100) }
    }
}
