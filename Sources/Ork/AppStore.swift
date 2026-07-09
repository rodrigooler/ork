import SwiftUI

final class AppStore: ObservableObject {
    @Published var workspaces: [Workspace] = []
    @Published var connections: [DBConnection] = []
    @Published var sessions: [TerminalSession] = []
    @Published var selectedWorkspaceID: UUID?

    private struct Persisted: Codable {
        var workspaces: [Workspace]
        var connections: [DBConnection]

        init(workspaces: [Workspace], connections: [DBConnection]) {
            self.workspaces = workspaces
            self.connections = connections
        }

        // Tolerant decode so a schema change never wipes saved workspaces.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            workspaces = (try? container.decode([Workspace].self, forKey: .workspaces)) ?? []
            connections = (try? container.decode([DBConnection].self, forKey: .connections)) ?? []
        }
    }

    private let stateURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    init() {
        if let data = try? Data(contentsOf: stateURL),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data) {
            workspaces = persisted.workspaces
            connections = persisted.connections
        }
        selectedWorkspaceID = workspaces.first?.id
    }

    private func save() {
        let persisted = Persisted(workspaces: workspaces, connections: connections)
        try? JSONEncoder().encode(persisted).write(to: stateURL, options: .atomic)
    }

    // MARK: - Workspaces

    func addWorkspace(at url: URL) {
        if let existing = workspaces.first(where: { $0.path == url.path }) {
            selectedWorkspaceID = existing.id
            return
        }
        let workspace = Workspace(id: UUID(), name: url.lastPathComponent, path: url.path)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        save()
    }

    func removeWorkspace(_ workspace: Workspace) {
        for session in sessions where session.workspaceID == workspace.id {
            TerminalRegistry.shared.close(session.id)
        }
        sessions.removeAll { $0.workspaceID == workspace.id }
        connections.removeAll { $0.workspaceID == workspace.id }
        workspaces.removeAll { $0.id == workspace.id }
        if selectedWorkspaceID == workspace.id {
            selectedWorkspaceID = workspaces.first?.id
        }
        save()
    }

    func workspace(id: UUID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    // MARK: - Sessions

    @discardableResult
    func newSession(agent: AgentProfile, in workspace: Workspace, useWorktree: Bool) throws -> TerminalSession {
        var directory = workspace.path
        var branch: String?
        if useWorktree {
            let worktree = try WorktreeService.add(repo: workspace.path, slug: agent.slug)
            directory = worktree.path
            branch = worktree.branch
        }
        let session = TerminalSession(
            id: UUID(),
            workspaceID: workspace.id,
            agent: agent,
            directory: directory,
            worktreeBranch: branch
        )
        sessions.append(session)
        return session
    }

    func closeSession(_ id: UUID) {
        TerminalRegistry.shared.close(id)
        sessions.removeAll { $0.id == id }
    }

    func markExited(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].exited = true
    }

    // MARK: - Connections (scoped per workspace)

    func connections(for workspaceID: UUID) -> [DBConnection] {
        connections.filter { $0.workspaceID == workspaceID }
    }

    func addConnection(_ connection: DBConnection) {
        connections.append(connection)
        save()
    }

    func removeConnection(_ id: UUID) {
        connections.removeAll { $0.id == id }
        save()
    }
}
