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
    /// How long a mutating manager tool waits for the root user's decision.
    public let approvalTimeout: TimeInterval

    public init(sessionID: String, bridgeDir: URL, version: String, approvalTimeout: TimeInterval = 120) {
        self.sessionID = sessionID
        self.bridgeDir = bridgeDir
        self.version = version
        self.approvalTimeout = approvalTimeout
    }

    struct Bridge: Decodable {
        let teamDir: String
        let member: String
        let manager: Bool?
        let workspace: String?
        let directory: String?
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
        [
            "name": "ork_project_info",
            "description": "Manager only: workspace name, project directory, team roster and current board, in one read.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "ork_spawn_member",
            "description": "Manager only: spawn a new team member in this workspace (own git worktree) and brief it with a standing role. Waits for the root user's approval in Ork; a denial is a decision, not an error. Keep teams as small as the demand allows.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Member name, short and unique (e.g. 'ana-qa')"],
                    "agent": ["type": "string", "description": "Agent slug (claude, codex, opencode, gemini, grok, kilo); default claude"],
                    "role": ["type": "string", "description": "Standing role and skills for this member, tailored to the project"],
                    "model": ["type": "string", "description": "Optional model override"],
                    "effort": ["type": "string", "description": "Optional reasoning effort override"],
                ],
                "required": ["name", "role"],
            ],
        ],
        [
            "name": "ork_configure_member",
            "description": "Manager only: change a running member's standing role, model or effort. Waits for the root user's approval in Ork.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Member name from team_members"],
                    "role": ["type": "string", "description": "New standing role; empty keeps the current one"],
                    "model": ["type": "string", "description": "Optional model override"],
                    "effort": ["type": "string", "description": "Optional reasoning effort override"],
                ],
                "required": ["name"],
            ],
        ],
        [
            "name": "ork_disband_member",
            "description": "Manager only: close a member's session (it leaves the team first). Waits for the root user's approval in Ork.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Member name from team_members"],
                ],
                "required": ["name"],
            ],
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
        case "ork_project_info", "ork_spawn_member", "ork_configure_member", "ork_disband_member":
            guard bridge.manager == true else {
                return text("This session is not a team manager; orchestration tools are manager only. Ask the user to spawn a manager from the team pane.", isError: true)
            }
            if name == "ork_project_info" {
                let roster = (try? String(contentsOf: teamDir.appendingPathComponent("members.md"), encoding: .utf8)) ?? "No roster yet."
                let board = (try? String(contentsOf: teamDir.appendingPathComponent("board.md"), encoding: .utf8)) ?? "Board is empty."
                return text("""
                Workspace: \(bridge.workspace ?? "unknown")
                Directory: \(bridge.directory ?? "unknown")

                Roster:
                \(roster)

                Board:
                \(board)
                """)
            }
            return requestApproval(action: String(name.dropFirst("ork_".count)), params: args)
        default:
            return text("unknown tool: \(name)", isError: true)
        }
    }

    // MARK: - Root approval gate

    /// Mutating manager tools never act directly: the request lands as a file
    /// Ork watches, the root user approves or denies in the UI, and the
    /// response file carries the outcome back. No answer within the timeout
    /// counts as denied.
    private func requestApproval(action: String, params: [String: Any]) -> [String: Any] {
        let requests = bridgeDir.appendingPathComponent("requests", isDirectory: true)
        try? FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let payload: [String: Any] = [
            "id": id,
            "session": sessionID,
            "action": action,
            "params": params,
            "ts": Date().timeIntervalSince1970,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return text("could not encode the request.", isError: true)
        }
        do {
            try data.write(to: requests.appendingPathComponent("\(id).json"))
        } catch {
            return text("could not write the request: \(error.localizedDescription)", isError: true)
        }

        let responseURL = requests.appendingPathComponent("\(id).response.json")
        let deadline = Date().addingTimeInterval(approvalTimeout)
        while Date() < deadline {
            if let response = try? Data(contentsOf: responseURL),
               let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any] {
                try? FileManager.default.removeItem(at: responseURL)
                let approved = object["approved"] as? Bool ?? false
                let note = object["result"] as? String ?? ""
                if approved {
                    return text(note.isEmpty ? "approved and done." : note)
                }
                return text("the root user denied this action\(note.isEmpty ? "." : ": \(note)") Adjust the plan or ask them directly in this terminal.", isError: false)
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        try? FileManager.default.removeItem(at: requests.appendingPathComponent("\(id).json"))
        return text("no decision from the root user within \(Int(approvalTimeout)) s; treat it as not approved and ask them directly in this terminal.", isError: false)
    }

    private func file(_ url: URL, fallback: String) -> [String: Any] {
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text(content.isEmpty ? fallback : content)
    }

    private func text(_ message: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": isError]
    }
}
