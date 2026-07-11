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
        // Tolerance lets the system coalesce timer wakeups (App Nap friendly).
        freezeTimer?.tolerance = 5
        statsTimer?.tolerance = 2
        // Stats pause while the deck is hidden; refresh the moment it is back.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow, !(window is NSPanel),
                  window.occlusionState.contains(.visible) else { return }
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

    // MARK: - Privacy (hide other clients while recording)

    private var selectedWorkspace: Workspace? {
        if case .workspace(let id)? = selection { return workspace(id: id) }
        return nil
    }

    /// In privacy mode only the section holding the selected project stays
    /// visible, so a screen recording for one client never shows the others.
    var visibleOrganizations: [Organization] {
        guard OrkSettings.shared.privacyMode else { return organizations }
        guard let orgID = selectedWorkspace?.organizationID else { return [] }
        return organizations.filter { $0.id == orgID }
    }

    var visibleUngroupedWorkspaces: [Workspace] {
        guard OrkSettings.shared.privacyMode else { return ungroupedWorkspaces }
        guard let selected = selectedWorkspace, selected.organizationID == nil else { return [] }
        return ungroupedWorkspaces
    }

    func isWorkspaceVisible(_ id: UUID) -> Bool {
        guard OrkSettings.shared.privacyMode else { return true }
        guard let selected = selectedWorkspace, let target = workspace(id: id) else { return false }
        return target.organizationID == selected.organizationID
    }

    // MARK: - Sidebar ordering (drag and drop)

    /// Drop semantics: the moved item takes the target's place — moving down
    /// lands after the target, moving up lands before it. After removal the
    /// target index already encodes both cases, so one insert covers them.
    static func reordered<T: Identifiable>(_ items: [T], moving id: T.ID, onto targetID: T.ID) -> [T] {
        guard id != targetID,
              let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == targetID }) else { return items }
        var result = items
        result.insert(result.remove(at: from), at: to)
        return result
    }

    func reorderOrganization(_ id: UUID, onto targetID: UUID) {
        organizations = Self.reordered(organizations, moving: id, onto: targetID)
        save()
    }

    /// Dropping a project onto another adopts the target's section
    /// (organization) and takes its place in the list.
    func reorderWorkspace(_ id: UUID, onto targetID: UUID) {
        guard let target = workspace(id: targetID),
              let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].organizationID = target.organizationID
        workspaces = Self.reordered(workspaces, moving: id, onto: targetID)
        save()
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
        EventFeed.shared.post(symbol: agent.symbol, tintHex: agent.tintHex, text: "\(agent.name) spawned in \(workspace.name)")
        return session
    }

    func closeSession(_ id: UUID) {
        let workspaceID = sessions.first { $0.id == id }?.workspaceID
        let wasCoordinator = workspaceID.map { teamMembers(in: $0).first?.id == id } ?? false
        TerminalRegistry.shared.close(id)
        sessions.removeAll { $0.id == id }
        frozenSessionIDs.remove(id)
        teamSessionIDs.remove(id)
        cpuSamples[id] = nil
        if focusedSessionID == id { focusedSessionID = nil }
        if focusModeSessionID == id { focusModeSessionID = nil }
        if let workspaceID {
            if wasCoordinator { promoteNextCoordinator(in: workspaceID) }
            TeamService.shared.stopWatcherIfIdle(workspaceID)
        }
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
        let wasCoordinator = teamSessionIDs.contains(id)
            && teamMembers(in: sessions[index].workspaceID).first?.id == id
        sessions[index].exited = true
        let session = sessions[index]
        if wasCoordinator { promoteNextCoordinator(in: session.workspaceID) }
        if teamSessionIDs.contains(id) { TeamService.shared.writeMembersFile(session.workspaceID) }
        let workspaceName = workspace(id: session.workspaceID)?.name ?? "project"
        if OrkSettings.shared.notifyOnExit {
            Notifier.notify(
                title: "\(session.agent.name) finished",
                body: session.worktreeBranch.map { "\(workspaceName) · \($0)" } ?? workspaceName
            )
        }
        EventFeed.shared.post(symbol: "xmark.circle", tintHex: 0xC96A5F, text: "\(session.displayName) exited in \(workspaceName)")
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
            if let session = sessions.first(where: { $0.id == id }) {
                EventFeed.shared.post(symbol: "moon.zzz", tintHex: 0x6F6B62, text: "\(session.displayName) slept")
            }
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
                notifyCoordinatorOfIdleMember(session)
                EventFeed.shared.post(symbol: "snowflake", tintHex: 0x6F6B62, text: "\(session.displayName) went idle, frozen")
            }
        }
    }

    /// An idle worker cannot ask for work once frozen; tell the coordinator
    /// it is free so the next assignment wakes it with the task attached.
    private func notifyCoordinatorOfIdleMember(_ session: TerminalSession) {
        guard teamSessionIDs.contains(session.id) else { return }
        let members = teamMembers(in: session.workspaceID)
        guard let coordinator = members.first, coordinator.id != session.id else { return }
        let name = TeamService.memberName(session)
        TeamService.shared.notify(
            memberNamed: TeamService.memberName(coordinator), in: members,
            text: "\(name) is idle and was frozen. Any message you send wakes it with the task; if there is nothing left, reply 'standby'."
        )
        TeamService.shared.appendLog(session.workspaceID, "- [\(TeamService.timestamp())] \(name) went idle (frozen), coordinator notified")
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
        EventFeed.shared.post(symbol: "memorychip", tintHex: 0x6F6B62, text: "\(sessions[index].displayName) hibernated, memory freed")
    }

    func resumeHibernated(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].hibernated else { return }
        sessions[index].hibernated = false
        save()
        EventFeed.shared.post(symbol: "bolt", text: "\(sessions[index].displayName) resumed")
    }

    // MARK: - Git stats (card chips)

    /// The chips only render in the main window, so polling while it is
    /// closed, minimized or fully covered spawns git for nobody. Frozen and
    /// hibernated sessions cannot touch their worktree; they keep their last
    /// stats instead of costing three git spawns per tick.
    private func pollStats() {
        guard !statsPollInFlight, Self.deckWindowVisible else { return }
        let eligible = sessions.filter { !$0.exited && $0.worktreeBranch != nil }
        guard !eligible.isEmpty else {
            if !sessionStats.isEmpty { sessionStats = [:] }
            return
        }
        let liveIDs = Set(eligible.map(\.id))
        let targets = eligible.compactMap { session -> (id: UUID, dir: String, repo: String)? in
            guard !session.hibernated, !frozenSessionIDs.contains(session.id),
                  let ws = workspace(id: session.workspaceID) else { return nil }
            return (session.id, session.directory, ws.path)
        }
        guard !targets.isEmpty else { return }
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
                guard let self else { return }
                self.sessionStats = self.sessionStats
                    .filter { liveIDs.contains($0.key) }
                    .merging(fresh) { _, new in new }
                self.statsPollInFlight = false
            }
        }
    }

    /// True while any regular window (not the notch panel or a popover) is
    /// actually on screen. Pane refresh loops share it: polling a window
    /// nobody can see is wasted work.
    static var deckWindowVisible: Bool {
        NSApp.windows.contains { !($0 is NSPanel) && $0.isVisible && $0.occlusionState.contains(.visible) }
    }

    /// Runtime configuration typed into the PTY: /model and /effort are
    /// registered Claude Code slash commands (verified against the installed
    /// CLI), and the persona lands as a plain role message any agent
    /// understands. The persona persists and joins future team briefings.
    func configureAgent(_ id: UUID, persona rawPersona: String, model: String, effort: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        wake(id)
        let persona = rawPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        if sessions[index].persona != (persona.isEmpty ? nil : persona) {
            sessions[index].persona = persona.isEmpty ? nil : persona
            save()
        }
        var sends: [String] = []
        let model = model.trimmingCharacters(in: .whitespaces)
        if !model.isEmpty { sends.append("/model \(model)\r") }
        if !effort.isEmpty { sends.append("/effort \(effort)\r") }
        if !persona.isEmpty {
            sends.append(TeamService.bracketedPaste(
                "[ork] Your role in this session: \(persona). Follow it from now on; acknowledge briefly."
            ) + "\r")
        }
        // Staggered so each command lands after the previous one settles.
        for (offset, text) in sends.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(offset) * 0.4) {
                TerminalRegistry.shared.send(id, text: text)
            }
        }
    }

    /// A duplicate name gets the short id appended so exact-match routing
    /// never picks the wrong terminal; an empty name restores the default.
    /// Teammates already self-correct on the old name (the router bounces
    /// unknown recipients with the roster), but the renamed agent itself must
    /// learn how to sign its outbox files, so it gets a note.
    func renameSession(_ id: UUID, to raw: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        let oldName = TeamService.memberName(session)
        let cleaned = TeamService.sanitizedName(raw)
        if cleaned.isEmpty {
            sessions[index].customName = nil
        } else {
            // 'ork', 'all' and 'user' are routing keywords; a member wearing
            // one would be unreachable or impersonate the user.
            let reserved = ["ork", "all", "user"].contains(cleaned.lowercased())
            let taken = reserved || sessions.contains {
                $0.id != id && !$0.exited && $0.workspaceID == session.workspaceID
                    && TeamService.memberName($0) == cleaned
            }
            sessions[index].customName = taken ? "\(cleaned)-\(session.shortID)" : cleaned
        }
        save()
        let newName = TeamService.memberName(sessions[index])
        guard newName != oldName else { return }
        EventFeed.shared.post(symbol: "pencil", text: "\(oldName) is now \(newName)")
        guard teamSessionIDs.contains(id) else { return }
        let workspaceID = session.workspaceID
        TeamService.shared.appendLog(workspaceID, "- [\(TeamService.timestamp())] \(oldName) renamed to \(newName)")
        let members = teamMembers(in: workspaceID)
        TeamService.shared.notify(
            memberNamed: newName, in: members,
            text: "you are now named '\(newName)'. Sign outbox files as \(newName)__RECIPIENT__$RANDOM.md; teammates messaging '\(oldName)' get bounced with the roster."
        )
        TeamService.shared.writeMembersFile(workspaceID)
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
        TeamService.shared.writeMembersFile(ws.id)
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
        EventFeed.shared.post(symbol: "person.2.fill", text: "\(TeamService.memberName(session)) joined the \(ws.name) team")
        save()
    }

    /// Resends the current protocol briefing to every member in place, so an
    /// existing team picks up protocol changes after an app update without
    /// being disbanded. Join order is kept: the first member stays coordinator.
    func rebriefTeam(_ workspaceID: UUID) {
        let members = teamMembers(in: workspaceID)
        guard let ws = workspace(id: workspaceID), !members.isEmpty else { return }
        TeamService.shared.ensureTeam(workspaceID: ws.id, workspaceName: ws.name)
        TeamService.shared.writeMembersFile(ws.id)
        for (index, member) in members.enumerated() where !member.hibernated {
            // Coordinator first in the teammate list, so member briefings
            // name the right coordinator.
            let mates = members.filter { $0.id != member.id }.map(TeamService.memberName)
            let briefing = TeamService.shared.briefing(
                for: member, workspace: ws, teammates: mates,
                asCoordinator: index == 0, rebrief: true
            )
            wake(member.id)
            TerminalRegistry.shared.send(member.id, text: TeamService.bracketedPaste(briefing) + "\r")
        }
        TeamService.shared.appendLog(ws.id, "- [\(TeamService.timestamp())] protocol rebrief sent to all members")
        EventFeed.shared.post(symbol: "arrow.triangle.2.circlepath", text: "team \(ws.name) rebriefed with the current protocol")
    }

    func leaveTeam(_ id: UUID) {
        guard teamSessionIDs.contains(id) else { return }
        guard let session = sessions.first(where: { $0.id == id }) else {
            teamSessionIDs.remove(id)
            return
        }
        let wasCoordinator = teamMembers(in: session.workspaceID).first?.id == id
        teamSessionIDs.remove(id)
        let note = "[team] \(TeamService.memberName(session)) left the team."
        for member in teamMembers(in: session.workspaceID) where !member.hibernated {
            TerminalRegistry.shared.send(member.id, text: TeamService.bracketedPaste(note) + "\r")
        }
        TeamService.shared.appendLog(session.workspaceID, "- [\(TeamService.timestamp())] \(TeamService.memberName(session)) left")
        EventFeed.shared.post(symbol: "person.2.slash", tintHex: 0x6F6B62, text: "\(TeamService.memberName(session)) left the team")
        if wasCoordinator { promoteNextCoordinator(in: session.workspaceID) }
        TeamService.shared.writeMembersFile(session.workspaceID)
        TeamService.shared.stopWatcherIfIdle(session.workspaceID)
        save()
    }

    /// Coordinator departed: the next member in join order takes over and is
    /// told so, otherwise the team keeps reporting to a ghost.
    private func promoteNextCoordinator(in workspaceID: UUID) {
        let members = teamMembers(in: workspaceID)
        guard let next = members.first else { return }
        TeamService.shared.notify(
            memberNamed: TeamService.memberName(next), in: members,
            text: "the coordinator left. \(TeamService.coordinatorRole)"
        )
        TeamService.shared.appendLog(workspaceID, "- [\(TeamService.timestamp())] \(TeamService.memberName(next)) promoted to coordinator")
        EventFeed.shared.post(symbol: "crown", text: "\(TeamService.memberName(next)) promoted to coordinator")
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
