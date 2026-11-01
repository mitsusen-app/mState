import Foundation

/// Whether `mState --mcp` may return metrics. Off by default; the switch is in the panel.
///
/// The server runs as a separate process, started by the agent client, so it reads this on
/// every call. The suite is shared because a process can't use its own bundle ID as one, and
/// `--mcp` also runs without a bundle under `swift run`.
enum AgentAccess {
    private static let suite = "io.github.mitsusen-app.mstate.agent"
    private static let key = "enabled"

    static var isEnabled: Bool {
        get { UserDefaults(suiteName: suite)?.bool(forKey: key) ?? false }
        set { UserDefaults(suiteName: suite)?.set(newValue, forKey: key) }
    }
}
