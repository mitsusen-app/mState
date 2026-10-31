import SwiftUI

enum Format {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))"
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    /// "1.24 MB/s", "82 KB/s"
    static func rate(_ bytesPerSecond: Double) -> String {
        let (value, unit) = scaled(bytesPerSecond)
        return "\(value) \(unit)B/s"
    }

    /// Menu bar form: "1.2M", "82K"
    static func shortRate(_ bytesPerSecond: Double) -> String {
        let (value, unit) = scaled(bytesPerSecond)
        return "\(value)\(unit.isEmpty ? "B" : unit)"
    }

    static func temperature(_ celsius: Double?) -> String {
        celsius.map { "\(Int($0.rounded()))°" } ?? "—"
    }

    static func duration(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private static func scaled(_ bytes: Double) -> (String, String) {
        let units = ["", "K", "M", "G"]
        var value = bytes
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        let digits = value < 10 && index > 0 ? 2 : (value < 100 && index > 0 ? 1 : 0)
        return (String(format: "%.\(digits)f", value), units[index])
    }
}

/// Neutral by default; color only appears when a value crosses a threshold.
enum Level {
    /// High usage isn't an error, so it tops out at orange; red is for temperature and battery.
    static func usage(_ fraction: Double) -> Color {
        fraction >= 0.9 ? .orange : .primary
    }

    static func temperature(_ celsius: Double?) -> Color {
        guard let celsius else { return .secondary }
        return celsius >= 100 ? .red : celsius >= 90 ? .orange : .secondary
    }
}
