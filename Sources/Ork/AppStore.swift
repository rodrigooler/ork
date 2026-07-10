import SwiftUI

enum SidebarSelection: Hashable {
    case workspace(UUID)
    case usage
}

final class AppStore: ObservableObject {
    @Published var workspaces: [Workspace] = []
    @Published var organizations: [Organization] = []
    @Published var connections: [DBConnection] = []
    @Published var sessions: [TerminalSession] = []
    @Published var selection: SidebarSelection?
    @Published var sidebarHidden = false
    @Published var focusedSessionID: UUID?
    @Published var focusModeSessionID: UUID?
    @Published var claudeUsage: AgentUsage?
    @Published var usageScanned = false

    /// Set by RootView; lets AppKit surfaces (notch panel) reopen the SwiftUI window.
    var openMainWindow: (() -> Void)?

    private var usageLoadStarted = false

    /// Sessions parked with SIGSTOP after sustained idle CPU; see pollFreeze().
    @Published private(set) var frozenSessionIDs: Set<UUID> = []
    /// Slept by the user, not the idle poll: survives freezeEnabled being off.
    private var manualSleepIDs: Set<UUID> = []
    private var freezeTimer: Timer?
    private var cpuSamples: [UUID: (cpu: Double, idlePolls: Int)] = [:]

    /// Per-session git diff stats shown on the card, refreshed by pollStats().
    @Published private(set) var sessionStats: [UUID: GitService.Stats] = [:]
    private var statsTimer: Timer?
    private var statsPollInFlight = false

    /// Sessions enrolled in their workspace's agent team; see TeamService.
    @Published private(set) var teamSessionIDs: Set<UUID> = []

    /// Below this share of one core, a CLI is repainting its TUI, not working.
    private static let idleCPUFraction = 0.06
    private static let freezePollInterval: TimeInterval = 30
    /// ORK_FREEZE_AFTER (seconds) overrides the Settings value for testing.
    private var freezeAfter: TimeInterval {
        ProcessInfo.processInfo.environment["ORK_FREEZE_AFTER"].flatMap(TimeInterval.init)
            ?? TimeInterval(OrkSettings.shared.freezeMinutes * 60)
    }

    private struct Persisted: Codable {
        var workspaces: [Workspace]
        var organizations: [Organization]
        var connections: [DBConnection]
        var sessions: [TerminalSession]
        var teamSessionIDs: [UUID]

        init(workspaces: [Workspace], organizations: [Organization], connections: [DBConnection], sessions: [TerminalSession], teamSessionIDs: [UUID]) {
            self.workspaces = workspaces
            self.organizations = organizations
            self.connections = connections
            self.sessions = sessions
            self.teamSessionIDs = teamSessionIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            workspaces = (try? container.decode([Workspace].self, forKey: .workspaces)) ?? []
            organizations = (try? container.decode([Organization].self, forKey: .organizations)) ?? []
            connections = (try? container.decode([DBConnection].self, forKey: .connections)) ?? []
            sessions = (try? container.decode([TerminalSession].self, forKey: .sessions)) ?? []
            teamSessionIDs = (try? container.decode([UUID].self, forKey: .teamSessionIDs)) ?? []
        }
    }

    private let stateURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    private(set) var restoredSessionIDs: Set<UUID> = []

    init() {
        if let data = try? Data(contentsOf: stateURL),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data) {
            workspaces = persisted.workspaces
            organizations = persisted.organizations
            connections = persisted.connections
            sessions = persisted.sessions
            teamSessionIDs = Set(persisted.teamSessionIDs)
            // These sessions had a live CLI before the last quit; relaunch
            // them with the agent's resume command so the conversation returns.
            restoredSessionIDs = Set(persisted.sessions.map(\.id))
        }
        selection = workspaces.first.map { .workspace($0.id) }
        TeamService.shared.store = self
        // Restored members keep their team: restart the outbox watchers.
        for workspaceID in Set(sessions.filter { teamSessionIDs.contains($0.id) }.map(\.workspaceID)) {
            let name = workspaces.first { $0.id == workspaceID }?.name ?? "project"
            TeamService.shared.ensureTeam(workspaceID: workspaceID, workspaceName: name)
        }
        freezeTimer = Timer.scheduledTimer(withTimeInterval: Self.freezePollInterval, repeats: true) { [weak self] _ in
            self?.pollFreeze()
        }
        statsTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.pollStats()
        }
        pollStats()
    }

    private func save() {
        let live = sessions.filter { !$0.exited }
        let persisted = Persisted(
            workspaces: workspaces,
            organizations: organizations,
            connections: connections,
            sessions: live,
            teamSessionIDs: live.map(\.id).filter { teamSessionIDs.contains($0) }
        )
        try? JSONEncoder().encode(persisted).write(to: stateURL, options: .atomic)
    }

    // MARK: - Workspaces

    func addWorkspace(at url: URL, organizationID: UUID? = nil) {
        if let existing = workspaces.first(where: { $0.path == url.path }) {
            if let orgID = organizationID, existing.organizationID != orgID {
                moveWorkspace(existing, toOrganization: orgID)
            }
            selection = .workspace(existing.id)
            return
        }
        let workspace = Workspace(id: UUID(), name: url.lastPathComponent, path: url.path, organizationID: organizationID)
        workspaces.append(workspace)
        selection = .workspace(workspace.id)
        save()
    }

    func renameWorkspace(_ workspace: Workspace, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[index].name = trimmed
        save()
    }

    func removeWorkspace(_ workspace: Workspace) {
        for session in sessions where session.workspaceID == workspace.id {
            TerminalRegistry.shared.close(session.id)
            frozenSessionIDs.remove(session.id)
            cpuSamples[session.id] = nil
        }
        sessions.removeAll { $0.workspaceID == workspace.id }
        connections.removeAll { $0.workspaceID == workspace.id }
        workspaces.removeAll { $0.id == workspace.id }
        if selection == .workspace(workspace.id) {
            selection = workspaces.first.map { .workspace($0.id) }
        }
        if let focus = focusModeSessionID, !sessions.contains(where: { $0.id == focus }) {
            focusModeSessionID = nil
        }
        save()
    }

    func workspace(id: UUID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    func moveWorkspace(_ workspace: Workspace, toOrganization orgID: UUID?) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[index].organizationID = orgID
        save()
    }

    // MARK: - Organizations

    @discardableResult
    func addOrganization(name: String) -> Organization {
        let org = Organization(id: UUID(), name: name)
        organizations.append(org)
        save()
        return org
    }

    func renameOrganization(_ org: Organization, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = organizations.firstIndex(where: { $0.id == org.id }) else { return }
        organizations[index].name = trimmed
        save()
    }

    func removeOrganization(_ org: Organization) {
        for i in workspaces.indices where workspaces[i].organizationID == org.id {
            workspaces[i].organizationID = nil
        }
        organizations.removeAll { $0.id == org.id }
        save()
    }

    func workspaces(in orgID: UUID) -> [Workspace] {
        workspaces.filter { $0.organizationID == orgID }
    }

    var ungroupedWorkspaces: [Workspace] {
        workspaces.filter { $0.organizationID == nil }
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
        save()
        return session
    }

    func closeSession(_ id: UUID) {
        let workspaceID = sessions.first { $0.id == id }?.workspaceID
        TerminalRegistry.shared.close(id)
        sessions.removeAll { $0.id == id }
        frozenSessionIDs.remove(id)
        teamSessionIDs.remove(id)
        cpuSamples[id] = nil
        if focusedSessionID == id { focusedSessionID = nil }
        if focusModeSessionID == id { focusModeSessionID = nil }
        if let workspaceID { TeamService.shared.stopWatcherIfIdle(workspaceID) }
        save()
    }

    func closeSessionAndRemoveWorktree(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }),
              let branch = session.worktreeBranch,
              let ws = workspace(id: session.workspaceID) else {
            closeSession(id)
            return
        }
        let dir = session.directory
        let repo = ws.path
        closeSession(id)
        Task.detached { WorktreeService.remove(repo: repo, worktreePath: dir, branch: branch) }
    }

    func markExited(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), !sessions[index].exited else { return }
        sessions[index].exited = true
        let session = sessions[index]
        let workspaceName = workspace(id: session.workspaceID)?.name ?? "project"
        if OrkSettings.shared.notifyOnExit {
            Notifier.notify(
                title: "\(session.agent.name) finished",
                body: session.worktreeBranch.map { "\(workspaceName) · \($0)" } ?? workspaceName
            )
        }
        save()
    }

    func setFocus(_ id: UUID, focused: Bool) {
        if focused {
            focusedSessionID = id
            wake(id)
        } else if focusedSessionID == id {
            focusedSessionID = nil
        }
    }

    // MARK: - Freeze (idle sessions parked with SIGSTOP)

    /// User-initiated SIGSTOP from the terminal's context menu.
    func sleepSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }),
              !session.exited, !session.hibernated,
              !frozenSessionIDs.contains(id) else { return }
        if TerminalRegistry.shared.freeze(id) {
            frozenSessionIDs.insert(id)
            manualSleepIDs.insert(id)
        }
    }

    private func pollFreeze() {
        guard OrkSettings.shared.freezeEnabled else {
            for id in Array(frozenSessionIDs) where !manualSleepIDs.contains(id) { wake(id) }
            return
        }
        let requiredPolls = max(1, Int(freezeAfter / Self.freezePollInterval))
        for session in sessions where !session.exited && !frozenSessionIDs.contains(session.id) {
            let id = session.id
            guard let pid = TerminalRegistry.shared.shellPid(for: id) else {
                cpuSamples[id] = nil
                continue
            }
            let cpu = ProcessCPU.groupCPUSeconds(pgid: pid)
            guard let prev = cpuSamples[id] else {
                cpuSamples[id] = (cpu, 0)
                continue
            }
            // Negative delta means a child process exited — activity, not idleness.
            let delta = cpu - prev.cpu
            let isIdle = delta >= 0 && delta < Self.idleCPUFraction * Self.freezePollInterval
            let isFocused = focusedSessionID == id || focusModeSessionID == id
            let idlePolls = (isIdle && !isFocused) ? prev.idlePolls + 1 : 0
            cpuSamples[id] = (cpu, idlePolls)
            if idlePolls >= requiredPolls, TerminalRegistry.shared.freeze(id) {
                frozenSessionIDs.insert(id)
            }
        }
    }

    func wake(_ id: UUID) {
        guard frozenSessionIDs.contains(id) else { return }
        TerminalRegistry.shared.thaw(id)
        frozenSessionIDs.remove(id)
        manualSleepIDs.remove(id)
        cpuSamples[id] = nil
    }

    // MARK: - Hibernate (process killed, memory freed, resumes on demand)

    func hibernate(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              !sessions[index].exited, !sessions[index].hibernated else { return }
        TerminalRegistry.shared.terminate(id)
        sessions[index].hibernated = true
        frozenSessionIDs.remove(id)
        manualSleepIDs.remove(id)
        cpuSamples[id] = nil
        if focusedSessionID == id { focusedSessionID = nil }
        if focusModeSessionID == id { focusModeSessionID = nil }
        // The next terminal attach relaunches with the agent's resume command.
        restoredSessionIDs.insert(id)
        save()
    }

    func resumeHibernated(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].hibernated else { return }
        sessions[index].hibernated = false
        save()
    }

    // MARK: - Git stats (card chips)

    private func pollStats() {
        guard !statsPollInFlight else { return }
        let targets = sessions.compactMap { session -> (id: UUID, dir: String, repo: String)? in
            guard !session.exited, session.worktreeBranch != nil,
                  let ws = workspace(id: session.workspaceID) else { return nil }
            return (session.id, session.directory, ws.path)
        }
        guard !targets.isEmpty else {
            if !sessionStats.isEmpty { sessionStats = [:] }
            return
        }
        statsPollInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            var fresh: [UUID: GitService.Stats] = [:]
            var baseCache: [String: String?] = [:]
            for target in targets {
                let base: String?
                if let cached = baseCache[target.repo] {
                    base = cached
                } else {
                    base = GitService.defaultBranch(repo: target.repo)
                    baseCache[target.repo] = base
                }
                fresh[target.id] = GitService.stats(worktree: target.dir, baseBranch: base)
            }
            DispatchQueue.main.async {
                self?.sessionStats = fresh
                self?.statsPollInFlight = false
            }
        }
    }

    // MARK: - Team (terminal-to-terminal messaging via TeamService)

    func teamMembers(in workspaceID: UUID) -> [TerminalSession] {
        sessions.filter { !$0.exited && $0.workspaceID == workspaceID && teamSessionIDs.contains($0.id) }
    }

    func joinTeam(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }),
              !session.exited, !session.hibernated, !teamSessionIDs.contains(id),
              let ws = workspace(id: session.workspaceID) else { return }
        let existing = teamMembers(in: ws.id)
        teamSessionIDs.insert(id)
        TeamService.shared.ensureTeam(workspaceID: ws.id, workspaceName: ws.name)
        let briefing = TeamService.shared.briefing(
            for: session, workspace: ws, teammates: existing.map(TeamService.memberName)
        )
        wake(id)
        TerminalRegistry.shared.send(id, text: TeamService.bracketedPaste(briefing) + "\r")
        let note = "[team] \(TeamService.memberName(session)) joined the team."
        for member in existing where !member.hibernated {
            TerminalRegistry.shared.send(member.id, text: TeamService.bracketedPaste(note) + "\r")
        }
        TeamService.shared.appendLog(ws.id, "- [\(TeamService.timestamp())] \(TeamService.memberName(session)) joined")
        save()
    }

    func leaveTeam(_ id: UUID) {
        guard teamSessionIDs.contains(id) else { return }
        teamSessionIDs.remove(id)
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let note = "[team] \(TeamService.memberName(session)) left the team."
        for member in teamMembers(in: session.workspaceID) where !member.hibernated {
            TerminalRegistry.shared.send(member.id, text: TeamService.bracketedPaste(note) + "\r")
        }
        TeamService.shared.appendLog(session.workspaceID, "- [\(TeamService.timestamp())] \(TeamService.memberName(session)) left")
        TeamService.shared.stopWatcherIfIdle(session.workspaceID)
        save()
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

    // MARK: - Usage

    func loadUsageIfNeeded() {
        guard !usageLoadStarted else { return }
        usageLoadStarted = true
        Task.detached(priority: .utility) { [weak self] in
            let usage = UsageService.claudeCode()
            DispatchQueue.main.async {
                self?.claudeUsage = usage
                self?.usageScanned = true
            }
        }
    }
}
