import Darwin

enum Sysctl {
    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        // Some keys are 32-bit; sysctl only fills `size` bytes.
        return size == MemoryLayout<Int32>.size ? Int(Int32(truncatingIfNeeded: value)) : Int(value)
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(nullTerminated: buffer)
    }
}

extension String {
    init(nullTerminated buffer: [CChar]) {
        self.init(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

public enum SystemInfo {
    /// e.g. "Apple M5 Max"
    public static let chipName = Sysctl.string("machdep.cpu.brand_string") ?? "Mac"
    public static let memoryBytes = UInt64(Sysctl.int("hw.memsize") ?? 0)
    /// 1 for M1, 5 for M5, and so on; nil on Intel.
    public static let appleSiliconGeneration: Int? = {
        guard let range = chipName.range(of: #"(?<=Apple M)\d+"#, options: .regularExpression) else { return nil }
        return Int(chipName[range])
    }()
}
