import Foundation

public struct TemperatureReading: Sendable {
    public let name: String
    public let celsius: Double
}

/// Reads Apple Silicon temperature sensors through the private IOHIDEventSystemClient API.
/// The symbols live in IOKit but aren't in the public headers, so they're resolved with dlsym.
/// No root needed, but this keeps the app out of the Mac App Store.
public final class HIDTemperatureSensors {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> OpaquePointer?
    private typealias SetMatchingFn = @convention(c) (OpaquePointer, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (OpaquePointer) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (OpaquePointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (OpaquePointer, Int64, Int32, Int64) -> OpaquePointer?
    private typealias GetFloatFn = @convention(c) (OpaquePointer, Int32) -> Double

    private static let temperatureEventType: Int64 = 15 // kIOHIDEventTypeTemperature
    private static let temperatureField = Int32(temperatureEventType << 16)

    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn
    private let client: OpaquePointer
    private let services: [(name: String, service: OpaquePointer)]
    /// Keeps the services array alive; the pointers above are borrowed from it.
    private let servicesArray: CFArray

    /// Returns nil if the private API isn't available.
    public init?() {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = Self.symbol("IOHIDEventSystemClientCreate", in: iokit, as: CreateFn.self),
              let setMatching = Self.symbol("IOHIDEventSystemClientSetMatching", in: iokit, as: SetMatchingFn.self),
              let copyServices = Self.symbol("IOHIDEventSystemClientCopyServices", in: iokit, as: CopyServicesFn.self),
              let copyProperty = Self.symbol("IOHIDServiceClientCopyProperty", in: iokit, as: CopyPropertyFn.self),
              let copyEvent = Self.symbol("IOHIDServiceClientCopyEvent", in: iokit, as: CopyEventFn.self),
              let getFloat = Self.symbol("IOHIDEventGetFloatValue", in: iokit, as: GetFloatFn.self),
              let client = create(kCFAllocatorDefault)
        else { return nil }

        // Vendor-defined usage page / usage that Apple uses for temperature sensors.
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(client, matching)
        guard let array = copyServices(client)?.takeRetainedValue() else { return nil }

        var services: [(String, OpaquePointer)] = []
        for i in 0..<CFArrayGetCount(array) {
            guard let raw = CFArrayGetValueAtIndex(array, i) else { continue }
            let service = OpaquePointer(raw)
            let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? "Unknown \(i)"
            services.append((name, service))
        }

        self.copyEvent = copyEvent
        self.getFloat = getFloat
        self.client = client
        self.servicesArray = array
        self.services = services.sorted { $0.0 < $1.0 }
    }

    deinit {
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(client)).release()
    }

    public func read() -> [TemperatureReading] {
        services.compactMap { name, service -> TemperatureReading? in
            guard let event = copyEvent(service, Self.temperatureEventType, 0, 0) else { return nil }
            defer { Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(event)).release() }
            let value = getFloat(event, Self.temperatureField)
            // Idle or unpowered sensors report 0 or junk; ignore anything implausible.
            guard value > 1, value < 150 else { return nil }
            return TemperatureReading(name: name, celsius: value)
        }
    }

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer, as: T.Type) -> T? {
        dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
    }
}
