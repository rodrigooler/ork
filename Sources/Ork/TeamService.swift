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

    func briefing(for session: TerminalSession, workspace: Workspace, teammates: [String]) -> String {
        let dir = Self.teamDir(workspace.id).path
        let name = Self.memberName(session)
        let mates = teammates.isEmpty ? "none yet" : teammates.joined(separator: ", ")
        return """
        [ork team] You are '\(name)', part of an agent team working on '\(workspace.name)'. \
        Teammates: \(mates). Shared board (read it before starting a task, append decisions and \
        status when you finish): "\(dir)/board.md". To message a teammate run: \
        echo "your text" > "\(dir)/outbox/\(name)__TEAMMATE__$RANDOM.md" \
        replacing TEAMMATE with their name, or with 'all' to broadcast. Incoming messages appear \
        in your input as [team msg from NAME]. Acknowledge this briefing briefly and wait.
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
            appendLog(workspaceID, "  (undelivered: no team member named '\(recipient)')")
            return
        }
        for target in targets {
            if target.hibernated {
                appendLog(workspaceID, "  (skipped \(Self.memberName(target)): hibernated)")
                continue
            }
            store.wake(target.id)
            let message = "[team msg from \(sender)] \(text)"
            TerminalRegistry.shared.send(target.id, text: Self.bracketedPaste(message) + "\r")
        }
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
