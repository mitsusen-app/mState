// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mState",
    platforms: [.macOS(.v14)],
    targets: [
        // Samplers that read system metrics; no UI.
        .target(name: "MonitorCore", linkerSettings: [.linkedFramework("IOKit")]),
        // The menu bar app.
        .executableTarget(name: "mState", dependencies: ["MonitorCore"]),
        // CLI that lists every temperature sensor, used to map sensor names on new chips.
        .executableTarget(name: "sensor-probe", dependencies: ["MonitorCore"]),
    ]
)
