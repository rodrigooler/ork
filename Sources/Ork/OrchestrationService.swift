import AppKit
import Foundation

/// Executes manager tool requests behind a root approval gate. ork-mcp
/// writes a request file under Application Support/Ork/mcp/requests and
/// waits; this service shows the request to the user and writes back the
/// decision. CLI permission prompts hang unattended agents, so approval is
/// always Ork-mediated UI.
final class OrchestrationService {
    static let shared = OrchestrationService()

    weak var store: AppStore?
    private var watcher: DispatchSourceFileSystemObject?

    static var requestsDir: URL {
        MCPBridge.dir.appendingPathComponent("requests", isDirectory: true)
    }

    /// Requests older than this are answered "expired": the waiting tool has
    /// already timed out, acting now would desynchronize manager and app.
    static let requestMaxAge: TimeInterval = 110

    struct ManagerRequest {
        let id: String
        let session: UUID
        let action: String
        let params: [String: String]
        let ts: Date
    }

    func start(store: AppStore) {
        self.store = store
        let dir = Self.requestsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.scan() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
        scan()
    }

    private func scan() {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: Self.requestsDir, includingPropertiesForKeys: nil) else { return }
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension == "json" && !url.lastPathComponent.hasSuffix(".response.json") {
            guard let data = try? Data(contentsOf: url),
                  let request = Self.parse(data) else { continue }
            try? FileManager.default.removeItem(at: url)
            handle(request)
        }
    }

    static func parse(_ data: Data) -> ManagerRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String,
              let session = (object["session"] as? String).flatMap(UUID.init(uuidString:)),
              let action = object["action"] as? String else { return nil }
        var params: [String: String] = [:]
        for (key, value) in object["params"] as? [String: Any] ?? [:] {
            params[key] = value as? String
        }
        let ts = Date(timeIntervalSince1970: object["ts"] as? Double ?? 0)
        return ManagerRequest(id: id, session: session, action: action, params: params, ts: ts)
    }

    static func summary(_ request: ManagerRequest, workspace: String) -> String {
        let name = request.params["name"] ?? "?"
        switch request.action {
        case "spawn_member":
            let agent = request.params["agent"] ?? "claude"
            var line = "Spawn '\(name)' (\(agent)) on the \(workspace) team"
            if let model = request.params["model"], !model.isEmpty { line += ", model \(model)" }
            if let role = request.params["role"], !role.isEmpty { line += "\n\nRole: \(role)" }
            return line
        case "configure_member":
            var line = "Reconfigure '\(name)' on the \(workspace) team"
            if let model = request.params["model"], !model.isEmpty { line += ", model \(model)" }
            if let effort = request.params["effort"], !effort.isEmpty { line += ", effort \(effort)" }
            if let role = request.params["role"], !role.isEmpty { line += "\n\nNew role: \(role)" }
            return line
        case "disband_member":
            return "Close '\(name)' and remove it from the \(workspace) team"
        default:
            return "\(request.action) \(name)"
        }
    }

    private func handle(_ request: ManagerRequest) {
        guard Date().timeIntervalSince(request.ts) < Self.requestMaxAge else {
            respond(request, approved: false, result: "request expired before the user saw it")
            return
        }
        guard let store,
              let manager = store.sessions.first(where: { $0.id == request.session }),
              store.managerSessionIDs.contains(manager.id),
              let workspace = store.workspace(id: manager.workspaceID) else {
            respond(request, approved: false, result: "requesting session is not a manager")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Ork Manager requests approval"
        alert.informativeText = Self.summary(request, workspace: workspace.name)
        alert.addButton(withTitle: "Approve")
        alert.addButton(withTitle: "Deny")
        NSApp.activate(ignoringOtherApps: true)
        let approved = alert.runModal() == .alertFirstButtonReturn
        guard approved else {
            EventFeed.shared.post(symbol: "hand.raised", tintHex: 0xC96A5F,
                                  text: "denied manager request: \(request.action)")
            respond(request, approved: false, result: "")
            return
        }
        let outcome = execute(request, workspace: workspace)
        EventFeed.shared.post(symbol: "person.badge.shield.checkmark", tintHex: 0x7FA65A,
                              text: "approved manager request: \(outcome)")
        respond(request, approved: true, result: outcome)
    }

    private func execute(_ request: ManagerRequest, workspace: Workspace) -> String {
        guard let store else { return "store unavailable" }
        let name = request.params["name"] ?? ""
        switch request.action {
        case "spawn_member":
            let slug = request.params["agent"] ?? "claude"
            let profile = AgentProfile.all.first { $0.slug == slug }
                ?? AgentProfile.all.first { $0.slug == "claude" }
            guard let profile else { return "no agent profile available" }
            guard let session = try? store.newSession(agent: profile, in: workspace, useWorktree: true) else {
                return "spawn failed (worktree could not be created)"
            }
            store.renameSession(session.id, to: name)
            store.joinTeam(session.id)
            let role = request.params["role"] ?? ""
            if !role.isEmpty || !(request.params["model"] ?? "").isEmpty {
                store.configureAgent(session.id, persona: role,
                                     model: request.params["model"] ?? "",
                                     effort: request.params["effort"] ?? "")
            }
            return "spawned '\(name)' (\(profile.name)) on \(workspace.name)"
        case "configure_member":
            guard let member = member(named: name, in: workspace) else { return "no member named '\(name)'" }
            store.configureAgent(member.id, persona: request.params["role"] ?? "",
                                 model: request.params["model"] ?? "",
                                 effort: request.params["effort"] ?? "")
            return "reconfigured '\(name)'"
        case "disband_member":
            guard let member = member(named: name, in: workspace) else { return "no member named '\(name)'" }
            guard !store.managerSessionIDs.contains(member.id) else { return "a manager cannot disband itself" }
            store.closeSession(member.id)
            return "closed '\(name)'"
        default:
            return "unknown action '\(request.action)'"
        }
    }

    private func member(named name: String, in workspace: Workspace) -> TerminalSession? {
        guard let store else { return nil }
        return TeamService.resolve(name, from: "", members: store.teamMembers(in: workspace.id)).first
    }

    private func respond(_ request: ManagerRequest, approved: Bool, result: String) {
        let payload: [String: Any] = ["approved": approved, "result": result]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: Self.requestsDir.appendingPathComponent("\(request.id).response.json"))
    }
}
