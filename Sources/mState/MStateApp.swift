import AppKit
import SwiftUI

struct MStateApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    // Not @State: SwiftUI's property wrappers are macros in this SDK, and the Command Line
    // Tools don't ship the SwiftUIMacros plugin. The App value is created once, so a let is fine.
    private let store = MetricsStore()

    init() {
        Snapshot.runIfRequested(store: store)
        appDelegate.store = store
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: MetricsStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The bundled app sets LSUIElement; this also hides the Dock icon under `swift run`.
        NSApp.setActivationPolicy(.accessory)
        if let store { Snapshot.showWindowIfRequested(store: store) }
    }
}
