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

    /// Team address: the user-given name when set, else slug plus short id.
    static func memberName(_ session: TerminalSession) -> String {
        session.customName ?? "\(session.agent.slug)-\(session.shortID)"
    }

    /// Names travel inside outbox filenames, so anything that could break the
    /// sender__recipient parsing or the filesystem is dropped.
    static func sanitizedName(_ raw: String) -> String {
        let cleaned = raw.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }
            .trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(24)).trimmingCharacters(in: .whitespaces)
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
    /// The protocol rules are what keep N-member teams fast and factual:
    /// pointers over payloads, the board as single source of truth, and
    /// verified-only reporting.
    func briefing(for session: TerminalSession, workspace: Workspace, teammates: [String]) -> String {
        let dir = Self.teamDir(workspace.id).path
        let name = Self.memberName(session)
        let isCoordinator = teammates.isEmpty
        let mates = teammates.isEmpty ? "none yet" : teammates.joined(separator: ", ")
        let role = isCoordinator ? Self.coordinatorRole : Self.memberRole(coordinator: teammates.first ?? "the first member")
        let persona = session.persona.map { " Your standing role: \($0)." } ?? ""
        return """
        [ork team] You are '\(name)' on an agent team for '\(workspace.name)'. Teammates: \(mates). \
        Board: "\(dir)/board.md". \
        Send: echo "text" > "\(dir)/outbox/\(name)__MEMBER__$RANDOM.md" (MEMBER = teammate name, or 'all' to broadcast). \
        Incoming messages appear in your input as [team msg from NAME]. Protocol, follow strictly: \
        (1) Message shapes: 'task <id>: goal, files, done-criteria' | 'done <id>: one-line verified outcome' | 'blocked <id>: reason'. \
        (2) Max \(Self.messageCharCap) chars per message; code, diffs and logs go in commits or on the board, messages carry pointers (file:line, board section). \
        (3) The board is the single source of truth: '## Tasks' holds active work as '- [ ] id: task — owner'; in '## Status' keep ONE line per member and overwrite your own; move finished rounds to '## Archive'; never restate board content in messages. \
        (4) Report only what you verified by running or reading; mark guesses 'unverified'; never invent or assume teammate results. \
        \(role)\(persona) Keep messages short and factual. Acknowledge this briefing briefly and wait.
        """
    }

    static let coordinatorRole = """
    You are the COORDINATOR: split multi-step work into independent subtasks on the board, \
    message each owner immediately, take your own share, and integrate 'done' reports. Ork \
    freezes idle teammates and notifies you; your message wakes them with the task attached, \
    so never assume a quiet teammate is gone. Ping anyone silent for too long.
    """

    static func memberRole(coordinator: String) -> String {
        """
        Your coordinator is \(coordinator): act on assignments immediately, tick the box on the \
        board, report 'done <id>'. If idle, ask for work. Getting frozen while idle is normal; \
        any incoming message wakes you, just act on it.
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
            Keep it small: this file is read often, so redundancy costs everyone.

            ## Tasks
            <!-- active work only: - [ ] id: task — owner ; finished rounds move to Archive -->

            ## Decisions
            <!-- one line each, append-only -->

            ## Status
            <!-- ONE line per member, overwrite your own: name: current state -->

            ## Archive

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

    /// Longer payloads belong on the board or in commits; the cap keeps
    /// N-member teams from flooding each other's context windows.
    static let messageCharCap = 1200

    /// Resolves a recipient segment to sessions. Exact name, then 'all'
    /// (minus the sender), then a unique fuzzy match ("b507" finds
    /// claude-b507). Digit-only strays like a bare $RANDOM never match.
    static func resolve(_ raw: String, from sender: String, members: [TerminalSession]) -> [TerminalSession] {
        if raw == "all" { return members.filter { memberName($0) != sender } }
        if let exact = members.first(where: { memberName($0) == raw }) { return [exact] }
        let needle = normalize(raw)
        guard needle.rangeOfCharacter(from: .letters) != nil else { return [] }
        let fuzzy = members.filter { member in
            let name = normalize(memberName(member))
            return name.contains(needle) || needle.contains(name)
        }
        return fuzzy.count == 1 ? fuzzy : []
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func scanOutbox(_ workspaceID: UUID) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: Self.outboxURL(workspaceID), includingPropertiesForKeys: nil),
              let store else { return }
        let members = store.teamMembers(in: workspaceID)
        // Batch per recipient: several messages in one scan window become a
        // single injection, one agent turn instead of N.
        var perTarget: [UUID: [String]] = [:]
        var routedSummaries: [String] = []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let parsed = Self.parseMessageFilename(url.lastPathComponent) else { continue }
            let content = (try? String(contentsOf: url, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Empty reads usually mean the writer has not flushed yet; the
            // next directory event retries this file.
            guard !content.isEmpty else { continue }
            try? fm.removeItem(at: url)

            appendLog(workspaceID, "- [\(Self.timestamp())] \(parsed.sender) → \(parsed.recipient): \(content)")
            if content.count > Self.messageCharCap {
                appendLog(workspaceID, "  (bounced: \(content.count) chars over the \(Self.messageCharCap) cap)")
                notify(memberNamed: parsed.sender, in: members,
                       text: "message to \(parsed.recipient) NOT delivered: \(content.count) chars, cap is \(Self.messageCharCap). Put details on the board or in commits and resend a pointer (file:line, board section).")
                continue
            }
            let targets = Self.resolve(parsed.recipient, from: parsed.sender, members: members)
            guard !targets.isEmpty else {
                // A dropped assignment deadlocks the team; bounce it so the
                // sender can correct the name instead of waiting forever.
                appendLog(workspaceID, "  (undelivered: no team member named '\(parsed.recipient)', bounced to sender)")
                let roster = members.map(Self.memberName).joined(separator: ", ")
                notify(memberNamed: parsed.sender, in: members,
                       text: "delivery FAILED: no member named '\(parsed.recipient)'. Members: \(roster). Resend as \(parsed.sender)__MEMBER__$RANDOM.md.")
                continue
            }
            for target in targets {
                if target.hibernated {
                    appendLog(workspaceID, "  (skipped \(Self.memberName(target)): hibernated, sender notified)")
                    notify(memberNamed: parsed.sender, in: members,
                           text: "\(Self.memberName(target)) is hibernated and did not receive your message. Ask the user to resume it, then resend.")
                    continue
                }
                perTarget[target.id, default: []].append("[team msg from \(parsed.sender)] \(content)")
            }
            if targets.contains(where: { !$0.hibernated }) {
                routedSummaries.append("\(parsed.sender) → \(parsed.recipient): \(content.prefix(56))")
            }
        }
        for (id, lines) in perTarget {
            store.wake(id)
            TerminalRegistry.shared.send(id, text: Self.bracketedPaste(lines.joined(separator: "\n")) + "\r")
        }
        for message in routedSummaries {
            EventFeed.shared.post(symbol: "bubble.left.and.bubble.right", text: message)
        }
    }

    /// System note typed into one member's terminal, waking it if frozen.
    func notify(memberNamed name: String, in members: [TerminalSession], text: String) {
        guard let session = members.first(where: { Self.memberName($0) == name }), !session.hibernated else { return }
        store?.wake(session.id)
        TerminalRegistry.shared.send(session.id, text: Self.bracketedPaste("[team] \(text)") + "\r")
    }

    static func userMessageFilename(to recipient: String) -> String {
        "user__\(recipient)__\(Int(Date().timeIntervalSince1970 * 1000)).md"
    }

    /// The user talks to the team through the same outbox as the agents, so
    /// delivery, logging and batching stay on one path.
    func sendFromUser(workspaceID: UUID, to recipient: String, text: String) {
        let url = Self.outboxURL(workspaceID).appendingPathComponent(Self.userMessageFilename(to: recipient))
        try? text.write(to: url, atomically: true, encoding: .utf8)
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
