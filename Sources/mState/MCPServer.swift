import Foundation
import MonitorCore

/// Read-only MCP server over stdio, started by an agent client with `mState --mcp`.
///
/// Serves both eras of the protocol from one loop: 2026-07-28 clients send their version in
/// each request's `_meta`, and older clients open with `initialize`. Everything is plain
/// JSON, one message per line, so there's no dependency on an MCP SDK.
final class MCPServer {
    private static let modernVersions = ["2026-07-28"]
    private static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    private static let versionKey = "io.modelcontextprotocol/protocolVersion"
    private static let serverInfoKey = "io.modelcontextprotocol/serverInfo"
    private static let toolName = "get_metrics"
    private static let instructions = """
    Reads live system metrics from this Mac. The metrics don't identify which process is \
    causing a load. A missing field means this Mac doesn't expose that value.
    """

    private struct Failure: Error {
        let code: Int
        let message: String
        var requestedVersion: String?
    }

    private let collector = MetricsCollector()

    func run() {
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                write(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            // Notifications have no id and get no reply.
            guard let id = message["id"], !(id is NSNull) else { continue }
            do {
                write(["jsonrpc": "2.0", "id": id, "result": try result(for: message)])
            } catch let failure as Failure {
                var error: [String: Any] = ["code": failure.code, "message": failure.message]
                if let requested = failure.requestedVersion {
                    error["data"] = ["supported": Self.modernVersions + Self.legacyVersions, "requested": requested]
                }
                write(["jsonrpc": "2.0", "id": id, "error": error])
            } catch {
                write(["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": "Internal error"]])
            }
        }
    }

    private func result(for message: [String: Any]) throws -> [String: Any] {
        guard let method = message["method"] as? String else {
            throw Failure(code: -32600, message: "Invalid request")
        }
        let params = message["params"] as? [String: Any] ?? [:]
        let version = (params["_meta"] as? [String: Any])?[Self.versionKey] as? String
        let supported = Self.modernVersions + Self.legacyVersions
        if let version, !supported.contains(version) {
            throw Failure(code: -32022, message: "Unsupported protocol version", requestedVersion: version)
        }

        var result: [String: Any]
        var cacheable = false
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            return [
                "protocolVersion": requested.flatMap { Self.legacyVersions.contains($0) ? $0 : nil } ?? Self.legacyVersions[0],
                "capabilities": Self.capabilities,
                "serverInfo": Self.serverInfo,
                "instructions": Self.instructions,
            ]
        case "ping":
            return [:]
        case "server/discover":
            result = ["supportedVersions": supported, "capabilities": Self.capabilities, "instructions": Self.instructions]
            cacheable = true
        case "tools/list":
            result = ["tools": [Self.tool]]
            cacheable = true
        case "tools/call":
            guard params["name"] as? String == Self.toolName else {
                throw Failure(code: -32602, message: "Unknown tool")
            }
            result = callTool()
        default:
            throw Failure(code: -32601, message: "Method not found")
        }

        guard version != nil || method == "server/discover" else { return result }
        result["resultType"] = "complete"
        result["_meta"] = [Self.serverInfoKey: Self.serverInfo]
        if cacheable {
            result["ttlMs"] = 0
            result["cacheScope"] = "private"
        }
        return result
    }

    private func callTool() -> [String: Any] {
        guard AgentAccess.isEnabled else {
            let text = "mState agent access is off. Ask the user to turn on Agent access in the mState menu bar panel."
            return ["content": [["type": "text", "text": text]], "isError": true]
        }
        return ["content": [["type": "text", "text": collector.collect().json()]], "isError": false]
    }

    private func write(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private static var capabilities: [String: Any] {
        ["tools": [String: Any]()]
    }

    private static var serverInfo: [String: Any] {
        ["name": "mState", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"]
    }

    private static var tool: [String: Any] {
        [
            "name": toolName,
            "title": "Get Mac metrics",
            "description": """
            Returns current CPU, GPU, memory, network, battery, power, and temperature readings for this Mac as JSON. \
            Takes about a second.
            """,
            "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ]
    }
}
