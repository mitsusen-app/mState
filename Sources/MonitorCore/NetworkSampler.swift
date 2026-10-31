import Darwin
import Foundation

public struct NetworkSample: Sendable {
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
}

public final class NetworkSampler {
    private var previous: (rx: UInt64, tx: UInt64, time: TimeInterval)?

    public init() {}

    public func sample() -> NetworkSample {
        let now = ProcessInfo.processInfo.systemUptime
        let (rx, tx) = Self.readCounters()
        defer { previous = (rx, tx, now) }
        guard let previous, now > previous.time else {
            return NetworkSample(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }
        let dt = now - previous.time
        // Counters reset when an interface goes down; treat that as zero rather than a huge spike.
        let drx = rx >= previous.rx ? rx - previous.rx : 0
        let dtx = tx >= previous.tx ? tx - previous.tx : 0
        return NetworkSample(downloadBytesPerSecond: Double(drx) / dt, uploadBytesPerSecond: Double(dtx) / dt)
    }

    /// Sums 64-bit byte counters over physical interfaces (en*). `getifaddrs` only
    /// exposes 32-bit counters that wrap at 4 GB, so read NET_RT_IFLIST2 instead.
    /// Tunnels (utun*) are skipped so VPN traffic isn't counted twice.
    private static func readCounters() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                defer { offset += Int(header.ifm_msglen) }
                guard header.ifm_msglen > 0 else { break }
                guard Int32(header.ifm_type) == RTM_IFINFO2 else { continue }
                let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard if_indextoname(UInt32(msg.ifm_index), &name) != nil,
                      String(nullTerminated: name).hasPrefix("en") else { continue }
                rx += msg.ifm_data.ifi_ibytes
                tx += msg.ifm_data.ifi_obytes
            }
        }
        return (rx, tx)
    }
}
