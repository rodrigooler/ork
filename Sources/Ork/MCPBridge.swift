import Foundation

/// Wires claude sessions to the ork-mcp stdio server (Sources/OrkMCP).
/// The bridge file maps a session to its team dir and member name; the
/// server reads it on every tool call, so joining a team after the CLI
/// started, or renaming, needs no restart. No bridge file = not on a team.
enum MCPBridge {
    static let dir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ork/mcp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// ork-mcp ships next to the Ork binary (Contents/MacOS in the .app,
    /// .build/<config> under swift run); nil disables the bridge.
    static var serverBinary: URL? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let sibling = executable.deletingLastPathComponent().appendingPathComponent("ork-mcp")
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }

    /// MCP config handed to claude at spawn. Written for every claude
    /// session: the server just reports "not on a team" until a bridge
    /// file appears, so spawn order and team joins stay decoupled.
    static func configPath(for sessionID: UUID) -> String? {
        guard let server = serverBinary else { return nil }
        let url = dir.appendingPathComponent("\(sessionID.uuidString)-config.json")
        let config: [String: Any] = [
            "mcpServers": ["ork": ["command": server.path, "args": ["--session", sessionID.uuidString]]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys]) else { return nil }
        try? data.write(to: url)
        return url.path
    }

    static func writeBridge(session: TerminalSession, workspace: Workspace?, manager: Bool) {
        var payload: [String: Any] = [
            "teamDir": TeamService.teamDir(session.workspaceID).path,
            "member": TeamService.memberName(session),
            "manager": manager,
        ]
        if let workspace {
            payload["workspace"] = workspace.name
            payload["directory"] = workspace.path
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? data.write(to: dir.appendingPathComponent("\(session.id.uuidString).json"))
    }

    static func removeBridge(_ sessionID: UUID) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(sessionID.uuidString).json"))
    }

    /// Close also drops the spawn config; nothing references it anymore.
    static func removeAll(_ sessionID: UUID) {
        removeBridge(sessionID)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(sessionID.uuidString)-config.json"))
    }
}
