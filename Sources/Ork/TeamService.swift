import Foundation

/// Terminal-to-terminal messaging. Agents drop small files into a watched
/// outbox; Ork routes each one by typing its content straight into the
/// recipient's PTY. Kernel-push via DispatchSource, no polling, and the only
/// token cost is the message text itself in the recipient's context.
///
/// Layout under Application Support/Ork/team/<workspaceID>/:
///   board.md   shared context, agents read at task start and append after
///   log.md     audit trail of every routed message
///   outbox/    agents write <sender>__<recipient>__<n>.md, Ork consumes
final class TeamService {
    static let shared = TeamService()
    weak var store: AppStore?

    static let root: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ork/team", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func teamDir(_ workspaceID: UUID) -> URL {
        root.appendingPathComponent(workspaceID.uuidString, isDirectory: true)
    }
    static func boardURL(_ workspaceID: UUID) -> URL { teamDir(workspaceID).appendingPathComponent("board.md") }
    static func logURL(_ workspaceID: UUID) -> URL { teamDir(workspaceID).appendingPathComponent("log.md") }
    static func outboxURL(_ workspaceID: UUID) -> URL {
        teamDir(workspaceID).appendingPathComponent("outbox", isDirectory: true)
    }

    /// Stable addressable name: agent slug plus the session's short id.
    static func memberName(_ session: TerminalSession) -> String {
        "\(session.agent.slug)-\(session.shortID)"
    }

    static func bracketedPaste(_ text: String) -> String {
        "\u{1B}[200~" + text + "\u{1B}[201~"
    }

    /// sender__recipient__anything.md; recipient "all" broadcasts.
    static func parseMessageFilename(_ name: String) -> (sender: String, recipient: String)? {
        guard name.hasSuffix(".md") else { return nil }
        let parts = name.dropLast(3).components(separatedBy: "__")
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    /// The first member to join coordinates; everyone else reports to them.
    /// The role text is what makes the team parallelize instead of chatting.
    func briefing(for session: TerminalSession, workspace: Workspace, teammates: [String]) -> String {
        let dir = Self.teamDir(workspace.id).path
        let name = Self.memberName(session)
        let isCoordinator = teammates.isEmpty
        let mates = teammates.isEmpty ? "none yet" : teammates.joined(separator: ", ")
        let role = isCoordinator
            ? """
            You are the COORDINATOR. When the user gives you a multi-step task: split it into \
            independent subtasks, write them on the board under '## Tasks' as '- [ ] task — owner', \
            message each owner their assignment immediately, and start your own share. Do not do \
            work a teammate could do in parallel. Integrate results as 'done' reports arrive. \
            Ork freezes idle teammates to save CPU and tells you when that happens; your message \
            wakes them with the task attached, so never assume a quiet teammate is gone. If someone \
            has not reported in a while, ping them.
            """
            : """
            Your coordinator is \(teammates.first ?? "the first member"). When you get an assignment: \
            do it right away, tick its box on the board, and message the coordinator 'done: <task>' \
            with a one-line result. If you are idle, message the coordinator asking for work; if you \
            get frozen while idle, any incoming message wakes you, so just act on it.
            """
        return """
        [ork team] You are '\(name)', part of an agent team working on '\(workspace.name)'. \
        Teammates: \(mates). Shared board (read before starting, append after): "\(dir)/board.md". \
        To message a teammate run: echo "your text" > "\(dir)/outbox/\(name)__TEAMMATE__$RANDOM.md" \
        replacing TEAMMATE with their name, or with 'all' to broadcast. Incoming messages appear \
        in your input as [team msg from NAME]. \(role) Keep team messages to one or two short \
        sentences. Acknowledge this briefing briefly and wait.
        """
    }

    // MARK: - Lifecycle

    private var watchers: [UUID: DispatchSourceFileSystemObject] = [:]
    private var scanScheduled: Set<UUID> = []

    func ensureTeam(workspaceID: UUID, workspaceName: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.outboxURL(workspaceID), withIntermediateDirectories: true)
        let board = Self.boardURL(workspaceID)
        if !fm.fileExists(atPath: board.path) {
            let template = """
            # Team Board — \(workspaceName)

            Shared context for every agent on this team. Read before starting a task.
            Append under the sections below; never rewrite other agents' entries.

            ## Tasks
            <!-- coordinator splits work here: - [ ] task — owner -->

            ## Decisions

            ## Status

            """
            try? template.write(to: board, atomically: true, encoding: .utf8)
        }
        startWatcher(workspaceID)
    }

    private func startWatcher(_ workspaceID: UUID) {
        guard watchers[workspaceID] == nil else { return }
        let fd = open(Self.outboxURL(workspaceID).path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleScan(workspaceID) }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchers[workspaceID] = source
        scanOutbox(workspaceID)
    }

    func stopWatcherIfIdle(_ workspaceID: UUID) {
        guard let store, store.teamMembers(in: workspaceID).isEmpty else { return }
        watchers.removeValue(forKey: workspaceID)?.cancel()
    }

    /// Coalesces bursts and gives echo a beat to finish writing the file.
    private func scheduleScan(_ workspaceID: UUID) {
        guard !scanScheduled.contains(workspaceID) else { return }
        scanScheduled.insert(workspaceID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.scanScheduled.remove(workspaceID)
            self?.scanOutbox(workspaceID)
        }
    }

    // MARK: - Routing

    func scanOutbox(_ workspaceID: UUID) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: Self.outboxURL(workspaceID), includingPropertiesForKeys: nil) else { return }
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let parsed = Self.parseMessageFilename(url.lastPathComponent) else { continue }
            let content = (try? String(contentsOf: url, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Empty reads usually mean the writer has not flushed yet; the
            // next directory event retries this file.
            guard !content.isEmpty else { continue }
            try? fm.removeItem(at: url)
            route(content, from: parsed.sender, to: parsed.recipient, workspaceID: workspaceID)
        }
    }

    private func route(_ text: String, from sender: String, to recipient: String, workspaceID: UUID) {
        guard let store else { return }
        let members = store.teamMembers(in: workspaceID)
        let targets = recipient == "all"
            ? members.filter { Self.memberName($0) != sender }
            : members.filter { Self.memberName($0) == recipient }
        appendLog(workspaceID, "- [\(Self.timestamp())] \(sender) → \(recipient): \(text)")
        guard !targets.isEmpty else {
            // A dropped assignment deadlocks the team; bounce it so the
            // sender can correct the name instead of waiting forever.
            appendLog(workspaceID, "  (undelivered: no team member named '\(recipient)', bounced to sender)")
            let roster = members.map(Self.memberName).joined(separator: ", ")
            notify(memberNamed: sender, in: members,
                   text: "delivery FAILED: no member named '\(recipient)'. Members: \(roster). Resend as \(sender)__MEMBER__$RANDOM.md.")
            return
        }
        for target in targets {
            if target.hibernated {
                appendLog(workspaceID, "  (skipped \(Self.memberName(target)): hibernated, sender notified)")
                notify(memberNamed: sender, in: members,
                       text: "\(Self.memberName(target)) is hibernated and did not receive your message. Ask the user to resume it, then resend.")
                continue
            }
            store.wake(target.id)
            let message = "[team msg from \(sender)] \(text)"
            TerminalRegistry.shared.send(target.id, text: Self.bracketedPaste(message) + "\r")
        }
    }

    /// System note typed into one member's terminal, waking it if frozen.
    func notify(memberNamed name: String, in members: [TerminalSession], text: String) {
        guard let session = members.first(where: { Self.memberName($0) == name }), !session.hibernated else { return }
        store?.wake(session.id)
        TerminalRegistry.shared.send(session.id, text: Self.bracketedPaste("[team] \(text)") + "\r")
    }

    func appendLog(_ workspaceID: UUID, _ line: String) {
        let url = Self.logURL(workspaceID)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func timestamp() -> String {
        timeFormatter.string(from: Date())
    }
}
