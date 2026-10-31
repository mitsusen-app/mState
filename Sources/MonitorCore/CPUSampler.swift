import Darwin

public struct CoreCluster: Sendable, Equatable {
    /// Name reported by the kernel, e.g. "Super", "Performance", "Efficiency".
    public let name: String
    /// Logical CPU indices that belong to this cluster.
    public let cores: Range<Int>
}

public struct CPUSample: Sendable {
    /// Overall usage, 0...1.
    public let total: Double
    /// Per logical CPU usage, 0...1, indexed by logical CPU id.
    public let perCore: [Double]
}

public final class CPUSampler {
    public let clusters: [CoreCluster]
    private var previous: [processor_cpu_load_info] = []

    public init() {
        clusters = Self.readClusters()
    }

    public func sample() -> CPUSample {
        let current = Self.readLoads()
        defer { previous = current }
        guard previous.count == current.count, !current.isEmpty else {
            return CPUSample(total: 0, perCore: Array(repeating: 0, count: current.count))
        }

        var busySum: UInt64 = 0
        var allSum: UInt64 = 0
        let perCore = zip(previous, current).map { old, new -> Double in
            // Tick counters are UInt32 and wrap, so subtract with overflow.
            let user = UInt64(new.cpu_ticks.0 &- old.cpu_ticks.0)
            let system = UInt64(new.cpu_ticks.1 &- old.cpu_ticks.1)
            let idle = UInt64(new.cpu_ticks.2 &- old.cpu_ticks.2)
            let nice = UInt64(new.cpu_ticks.3 &- old.cpu_ticks.3)
            let busy = user + system + nice
            let all = busy + idle
            busySum += busy
            allSum += all
            return all == 0 ? 0 : Double(busy) / Double(all)
        }
        return CPUSample(total: allSum == 0 ? 0 : Double(busySum) / Double(allSum), perCore: perCore)
    }

    private static func readLoads() -> [processor_cpu_load_info] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        return info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(count)) {
            Array(UnsafeBufferPointer(start: $0, count: Int(count)))
        }
    }

    /// Apple Silicon numbers logical CPUs from the slowest cluster to the fastest,
    /// while perflevel0 is the fastest. So walk perflevels in reverse.
    private static func readClusters() -> [CoreCluster] {
        let levels = Sysctl.int("hw.nperflevels") ?? 0
        guard levels > 0 else {
            let n = Sysctl.int("hw.ncpu") ?? 0
            return [CoreCluster(name: "CPU", cores: 0..<n)]
        }
        var start = 0
        return (0..<levels).reversed().compactMap { level in
            guard let n = Sysctl.int("hw.perflevel\(level).logicalcpu") else { return nil }
            let name = Sysctl.string("hw.perflevel\(level).name") ?? "L\(level)"
            defer { start += n }
            return CoreCluster(name: name, cores: start..<(start + n))
        }
    }
}
