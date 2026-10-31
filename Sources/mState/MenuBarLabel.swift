import AppKit
import SwiftUI

/// The status item. MenuBarExtra labels only render plain Text/Image, so the compact
/// two-line layout is drawn with ImageRenderer and shown as a template image, which
/// lets macOS tint it for light/dark menu bars.
struct MenuBarLabel: View {
    let store: MetricsStore

    var body: some View {
        Image(nsImage: render())
    }

    private func render() -> NSImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }

    private var content: some View {
        HStack(spacing: 7) {
            stack("CPU", "\(Format.percent(store.cpu?.total ?? 0))%")
            MiniSpark(values: store.cpuHistory.values.suffix(16))
                .frame(width: 22, height: 13)
            stack("GPU", "\(Format.percent(store.gpu?.utilization ?? 0))%")
            VStack(alignment: .trailing, spacing: -1) {
                Text("↑" + Format.shortRate(store.network?.uploadBytesPerSecond ?? 0))
                Text("↓" + Format.shortRate(store.network?.downloadBytesPerSecond ?? 0))
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .frame(width: 44, alignment: .trailing)
        }
        .foregroundStyle(.black)
        .frame(height: 22)
    }

    private func stack(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(label).font(.system(size: 7.5, weight: .semibold)).tracking(0.6)
            Text(value).font(.system(size: 10.5, weight: .medium, design: .monospaced))
        }
        .frame(width: 30, alignment: .leading)
    }
}

/// Tiny line chart drawn with a plain Path, which keeps the per-second menu bar render cheap.
private struct MiniSpark: View {
    let values: ArraySlice<Double>

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let points = Array(values)
                guard points.count > 1 else { return }
                let step = geo.size.width / CGFloat(points.count - 1)
                for (i, v) in points.enumerated() {
                    let p = CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(min(max(v, 0), 1))))
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
            }
            .stroke(.black, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
    }
}
