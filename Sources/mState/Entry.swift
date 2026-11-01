import MonitorCore

@main
enum Entry {
    /// `--json` and `--mcp` run in the same binary as the app, and neither starts its UI.
    @MainActor
    static func main() {
        switch CommandLine.arguments.dropFirst().first {
        case "--json": print(MetricsCollector().collect().json(pretty: true))
        case "--mcp": MCPServer().run()
        default: MStateApp.main()
        }
    }
}
