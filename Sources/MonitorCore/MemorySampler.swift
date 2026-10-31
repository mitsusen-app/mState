import Darwin

public enum MemoryPressure: Sendable {
    case normal, warning, critical
}

public struct MemorySample: Sendable {
    public let total: UInt64
    /// Matches Activity Monitor's "Memory Used": app + wired + compressed.
    public let used: UInt64
    public let compressed: UInt64
    public let pressure: MemoryPressure

    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

public final class MemorySampler {
    private let total = SystemInfo.memoryBytes
    private let pageSize = UInt64(Sysctl.int("hw.pagesize") ?? 16384)

    public init() {}

    public func sample() -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemorySample(total: total, used: 0, compressed: 0, pressure: .normal)
        }

        let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let pressure: MemoryPressure = switch Sysctl.int("kern.memorystatus_vm_pressure_level") {
        case 4: .critical
        case 2: .warning
        default: .normal
        }
        return MemorySample(total: total, used: (app + wired + compressed) * pageSize,
                            compressed: compressed * pageSize, pressure: pressure)
    }
}
