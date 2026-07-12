import Foundation

/// Request handling for the ork-mcp stdio server: agents on a team call
/// team_send/team_board/team_members as MCP tools instead of shell echoes.
///
/// The bridge file (<bridgeDir>/<session>.json, {"teamDir","member"}) is
/// written by Ork on team join/rename and removed on leave; it is read on
/// EVERY tool call so a session that joins a team after the CLI started, or
/// gets renamed, needs no restart. Absent file = not in a team.
///
/// The outbox contract is TeamService's (Sources/Ork/TeamService.swift):
/// <sender>__<recipient>__<millis>.md dropped into <teamDir>/outbox, router
/// bounces failures back into the sender's terminal.
public struct MCPServer {
    public let sessionID: String
    public let bridgeDir: URL
    public let version: String

    public init(sessionID: String, bridgeDir: URL, version: String) {
        self.sessionID = sessionID
        self.bridgeDir = bridgeDir
        self.version = version
    }

    struct Bridge: Decodable {
        let teamDir: String
        let member: String
    }

    private func bridge() -> Bridge? {
        let url = bridgeDir.appendingPathComponent("\(sessionID).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Bridge.self, from: data)
    }

    /// Handles one JSON-RPC message; nil means no response (notification).
    public func handle(_ request: [String: Any]) -> [String: Any]? {
        let method = request["method"] as? String ?? ""
        let id = request["id"]
        guard id != nil else { return nil }

        switch method {
        case "initialize":
            let params = request["params"] as? [String: Any]
            let clientVersion = params?["protocolVersion"] as? String ?? "2024-11-05"
            return result(id, [
                "protocolVersion": clientVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "ork", "version": version],
            ])
        case "ping":
            return result(id, [String: Any]())
        case "tools/list":
            return result(id, ["tools": Self.tools])
        case "tools/call":
            let params = request["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            return result(id, call(name, args))
        default:
            return ["jsonrpc": "2.0", "id": id!,
                    "error": ["code": -32601, "message": "method not found: \(method)"]]
        }
    }

    private func result(_ id: Any?, _ payload: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id!, "result": payload]
    }

    private static let tools: [[String: Any]] = [
        [
            "name": "team_send",
            "description": "Send a message to a teammate on this Ork agent team. Recipient is a member name from team_members, 'all' to broadcast, or 'ork' for control commands (sleep, escalate <id>: reason, archive <summary>). Same protocol as the board: short pointer messages, shapes like 'claim <id>' / 'done <id>: outcome'.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "recipient": ["type": "string", "description": "Member name, 'all' or 'ork'"],
                    "message": ["type": "string", "description": "The message text"],
                ],
                "required": ["recipient", "message"],
            ],
        ],
        [
            "name": "team_board",
            "description": "Read the team's shared board.md (backlog, tasks, decisions, status).",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "team_members",
            "description": "Read the team roster (member names and worktree paths).",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
    ]

    private func call(_ name: String, _ args: [String: Any]) -> [String: Any] {
        guard let bridge = bridge() else {
            return text("This session is not on a team. Join a team in Ork first; until then there is nothing to message.", isError: true)
        }
        let teamDir = URL(fileURLWithPath: bridge.teamDir)
        switch name {
        case "team_send":
            let recipient = (args["recipient"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let message = (args["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recipient.isEmpty, !message.isEmpty else {
                return text("recipient and message are both required.", isError: true)
            }
            guard !recipient.contains("/"), !recipient.contains("__") else {
                return text("invalid recipient name.", isError: true)
            }
            let millis = Int(Date().timeIntervalSince1970 * 1000)
            let url = teamDir.appendingPathComponent("outbox/\(bridge.member)__\(recipient)__\(millis).md")
            do {
                try message.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return text("could not write the message: \(error.localizedDescription)", isError: true)
            }
            return text("sent to \(recipient). No reply means received; delivery problems bounce back into your terminal as [team] notes.")
        case "team_board":
            return file(teamDir.appendingPathComponent("board.md"), fallback: "Board is empty.")
        case "team_members":
            return file(teamDir.appendingPathComponent("members.md"), fallback: "No roster yet.")
        default:
            return text("unknown tool: \(name)", isError: true)
        }
    }

    private func file(_ url: URL, fallback: String) -> [String: Any] {
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text(content.isEmpty ? fallback : content)
    }

    private func text(_ message: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": isError]
    }
}
