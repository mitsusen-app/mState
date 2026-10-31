import Foundation
import IOKit

/// Minimal reader for the System Management Controller via the AppleSMC user client.
/// Talks the same 80-byte SMCKeyData_t struct as the classic smc.h, but builds it as raw
/// bytes so the layout doesn't depend on Swift struct padding.
public final class SMC {
    public struct KeyInfo: Sendable {
        public let size: UInt32
        public let type: String
    }

    private enum Offset {
        static let key = 0
        static let dataSize = 28
        static let dataType = 32
        static let result = 40
        static let command = 42
        static let index = 44
        static let bytes = 48
    }

    private enum Command: UInt8 {
        case readKey = 5
        case keyFromIndex = 8
        case keyInfo = 9
    }

    private static let structSize = 80
    private static let handleEvent: UInt32 = 2
    private let connection: io_connect_t

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    public var keyCount: Int {
        guard let data = read("#KEY"), data.count >= 4 else { return 0 }
        return Int(UInt32(bigEndian: data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
    }

    public func key(at index: Int) -> String? {
        var input = Self.request(.keyFromIndex)
        Self.store(UInt32(index), in: &input, at: Offset.index)
        guard let output = call(input) else { return nil }
        return Self.fourCC(output.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: Offset.key, as: UInt32.self) })
    }

    public func info(_ key: String) -> KeyInfo? {
        var input = Self.request(.keyInfo)
        Self.store(Self.code(key), in: &input, at: Offset.key)
        guard let output = call(input) else { return nil }
        return output.withUnsafeBytes {
            KeyInfo(size: $0.loadUnaligned(fromByteOffset: Offset.dataSize, as: UInt32.self),
                    type: Self.fourCC($0.loadUnaligned(fromByteOffset: Offset.dataType, as: UInt32.self)))
        }
    }

    public func read(_ key: String, info known: KeyInfo? = nil) -> [UInt8]? {
        guard let info = known ?? info(key), info.size > 0, info.size <= 32 else { return nil }
        var input = Self.request(.readKey)
        Self.store(Self.code(key), in: &input, at: Offset.key)
        Self.store(info.size, in: &input, at: Offset.dataSize)
        guard let output = call(input) else { return nil }
        return Array(output[Offset.bytes..<(Offset.bytes + Int(info.size))])
    }

    /// Reads a key stored as a little-endian 32-bit float ("flt "), which is what
    /// Apple Silicon uses for temperatures.
    public func float(_ key: String, info known: KeyInfo? = nil) -> Double? {
        guard let info = known ?? info(key), info.type == "flt ",
              let bytes = read(key, info: info), bytes.count == 4 else { return nil }
        return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
    }

    /// Reads a temperature key in either format: "flt " on Apple Silicon, or "sp78" on Intel,
    /// a big-endian signed fixed-point value with 8 fractional bits.
    public func temperature(_ key: String, info known: KeyInfo? = nil) -> Double? {
        guard let info = known ?? info(key) else { return nil }
        switch info.type {
        case "flt ":
            return float(key, info: info)
        case "sp78":
            guard let bytes = read(key, info: info), bytes.count == 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outputSize = Self.structSize
        let status = input.withUnsafeBytes { inBuf in
            output.withUnsafeMutableBytes { outBuf in
                IOConnectCallStructMethod(connection, Self.handleEvent, inBuf.baseAddress, Self.structSize,
                                          outBuf.baseAddress, &outputSize)
            }
        }
        guard status == KERN_SUCCESS, output[Offset.result] == 0 else { return nil }
        return output
    }

    private static func request(_ command: Command) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: structSize)
        buffer[Offset.command] = command.rawValue
        return buffer
    }

    private static func store(_ value: UInt32, in buffer: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value) { buffer.replaceSubrange(offset..<(offset + 4), with: $0) }
    }

    private static func code(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func fourCC(_ value: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }, as: UTF8.self)
    }
}
