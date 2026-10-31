import AppKit
import SwiftUI

/// Debug aid for iterating on the UI without screen-recording permission:
///   MSTATE_SNAPSHOT=/some/dir swift run mState
/// samples for a few seconds, writes the menu bar label and the panel (light and dark) as PNGs, then quits.
@MainActor
enum Snapshot {
    static func runIfRequested(store: MetricsStore) {
        guard let dir = ProcessInfo.processInfo.environment["MSTATE_SNAPSHOT"] else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        Task {
            try? await Task.sleep(for: .seconds(6))
            write(MenuBarLabel(store: store).padding(4).background(.white), to: url.appendingPathComponent("menubar.png"))
            for scheme in [ColorScheme.light, .dark] {
                let panel = PanelView(store: store)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
                write(panel, to: url.appendingPathComponent("panel-\(scheme == .light ? "light" : "dark").png"))
            }
            NSApp.terminate(nil)
        }
    }

    /// MSTATE_WINDOW=1 shows the panel in a regular window on a vibrancy background, so its
    /// steady-state cost can be measured without clicking the status item.
    static func showWindowIfRequested(store: MetricsStore) {
        guard ProcessInfo.processInfo.environment["MSTATE_WINDOW"] != nil else { return }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        let hosting = NSHostingView(rootView: PanelView(store: store))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "mState panel (debug)"
        window.contentView = effect
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        debugWindow = window
    }

    private static var debugWindow: NSWindow?

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
