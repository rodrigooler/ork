import Foundation

/// Terminal-to-terminal messaging. Agents drop small files into a watched
/// outbox; Ork routes each one by typing its content straight into the
/// recipient's PTY. Kernel-push via DispatchSource, no polling, and the only
/// token cost is the message text itself in the recipient's context.
///
/// Layout under Application Support/Ork/team/<workspaceID>/:
///   board.md    shared context, agents read at task start and append after
///   members.md  roster with worktree paths, rewritten by Ork on join/leave/rename/exit
///   protocol.md standing copy of the messaging recipe, survives agent context compaction
///   log.md      audit trail of every routed message
///   outbox/     agents write <sender>__<recipient>__<n>.md, Ork consumes
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
    static func membersURL(_ workspaceID: UUID) -> URL { teamDir(workspaceID).appendingPathComponent("members.md") }
    static func protocolURL(_ workspaceID: UUID) -> URL { teamDir(workspaceID).appendingPathComponent("protocol.md") }
    static func historyDir(_ workspaceID: UUID) -> URL {
        teamDir(workspaceID).appendingPathComponent("history", isDirectory: true)
    }
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
    /// `asCoordinator` overrides the joined-first inference so an existing
    /// team can be rebriefed in place; `rebrief` swaps the closing line so a
    /// mid-task member carries on instead of stopping to wait.
    func briefing(for session: TerminalSession, workspace: Workspace, teammates: [String],
                  asCoordinator: Bool? = nil, rebrief: Bool = false) -> String {
        let dir = Self.teamDir(workspace.id).path
        let name = Self.memberName(session)
        let isCoordinator = asCoordinator ?? teammates.isEmpty
        let mates = teammates.isEmpty ? "none yet" : teammates.joined(separator: ", ")
        let role = isCoordinator ? Self.coordinatorRole : Self.memberRole(coordinator: teammates.first ?? "the first member")
        let persona = session.persona.map { " Your standing role: \($0)." } ?? ""
        let closing = rebrief
            ? "This protocol update replaces your earlier briefing; do not reply, continue your current work under it."
            : "Acknowledge this briefing briefly and wait."
        return """
        [ork team] You are '\(name)' on an agent team for '\(workspace.name)'. Teammates: \(mates). \
        Board: "\(dir)/board.md". Roster with each member's worktree path: "\(dir)/members.md". \
        If context compaction loses this briefing, re-read "\(dir)/protocol.md". \
        Past demands: "\(dir)/history/", read only when you need old context. \
        Send: echo "text" > "\(dir)/outbox/\(name)__MEMBER__$RANDOM.md" (MEMBER = teammate name, or 'all' to broadcast). \
        If your tools include the 'ork' MCP server (team_send, team_board, team_members), prefer those over the echo recipe. \
        Incoming messages appear in your input as [team msg from NAME]. Protocol, follow strictly: \
        (1) Message shapes: 'task <id>: one-line goal, spec stays in the Backlog' | 'claim <id>' | 'done <id>: one-line verified outcome' | 'rework <id>: concrete problems' | 'approved <id>: what was verified' | 'blocked <id>: reason'. \
        (2) Keep messages under \(Self.messageCharCap) chars; code, diffs and logs go in commits or on the board, messages carry pointers (file:line, board section). A longer message is never cut: ork saves it whole under "\(dir)/artifacts/" and delivers the file path instead, which costs the recipient an extra read, so inline brevity wins. Payloads too big for the board (full logs, long diffs) go to artifacts/ the same way. Never send bare acknowledgements ('ok', 'received', 'starting'): silence means received, every message costs the recipient a full turn. \
        (2b) Technical questions go straight to the teammate who owns that code, not through the coordinator; copy the coordinator only when the answer changes scope, schedule or the board. \
        (3) The board is the single source of truth: '## Backlog' holds unclaimed tasks and only the coordinator writes it; '## Tasks' holds claimed work as '- [ ] id: task — owner'; in '## Status' keep ONE line per member and overwrite your own; approved rounds move to '## Archive'; never restate board content in messages. \
        (4) Report only what you verified by running or reading; mark guesses 'unverified'; never invent or assume teammate results. \
        (5) 'ork' as MEMBER addresses the app itself, not a teammate: send it 'sleep' to park your terminal, 'escalate <id>: reason' to alert the human user, or (coordinator only) 'archive <one-line demand summary>' to snapshot the finished board into history/ and reset it ('## Decisions' survives). \
        \(role)\(persona) Keep messages short and factual. \(closing)
        """
    }

    static let coordinatorRole = """
    You are the COORDINATOR: you decompose, assign, review and decide, and you never implement \
    tasks yourself; if a task looks quick enough to just do, it goes in the Backlog like any other. \
    First decompose the WHOLE demand into '## Backlog' (every task: id, goal, files, done-criteria; \
    append '(after <id>)' when a task depends on another) \
    before assigning anything, then seed each member their first task by 'task <id>' message and \
    leave the rest for members to claim; never poll for status, and do not reply to 'claim' unless \
    the task is already taken. A 'done <id>' is a request for review, not proof: in the owner's \
    worktree (path in members.md) read the full diff, run the build and tests yourself, check every \
    done-criterion, and hunt for bugs, missed edge cases, regressions and security holes \
    (unvalidated input, leaked secrets, debug leftovers). Approve only work you would ship: reply \
    'approved <id>: what you verified' and archive the round, appending the member's next \
    'task <id>' to the same message while the Backlog has open tasks; otherwise reply 'rework <id>' \
    with concrete problems. After 2 rework rounds on one task, or on a decision only the user can \
    make, send 'escalate <id>: reason' to ork. Approved work must land, not sit in a worktree: \
    push the task branch and open a PR with 'gh pr create' (title: task id and goal; body: \
    done-criteria and what you verified), one PR per task, grouping tasks into one PR only when \
    they ship together; without a remote or gh, merge the branch into the base branch instead. \
    Note the PR link or merge in '## Archive'. Members claim work and sleep on their own; your \
    message wakes a sleeping member, so never assume a quiet teammate is gone. When the Backlog is \
    empty and every approved task is integrated, close the demand: send 'archive <one-line \
    summary>' to ork, then 'sleep'.
    """

    static func memberRole(coordinator: String) -> String {
        """
        Your coordinator is \(coordinator): act on assignments immediately and fix 'rework <id>' \
        feedback before anything else. Before reporting 'done <id>', rebase your branch onto the \
        base branch (git fetch origin && git rebase, usually origin/main) and resolve your own \
        conflicts while they are small, then verify the outcome yourself (build, tests, reading \
        the result); expect a real review, your diff will be read and your tests re-run. \
        Be proactive: when free, take the next open task from '## Backlog' \
        yourself, announce 'claim <id>' to the coordinator and start at once without waiting for \
        a reply; skip tasks marked '(after <id>)' until that task is approved; if told the task \
        is already taken, drop that work and claim another. When the \
        Backlog is empty and nothing is pending on you, send 'sleep' to ork without announcing it. \
        Sleeping or getting frozen is normal; any incoming message wakes you, just act on it.
        """
    }

    // MARK: - Lifecycle

    private var watchers: [UUID: DispatchSourceFileSystemObject] = [:]
    private var scanScheduled: Set<UUID> = []

    func ensureTeam(workspaceID: UUID, workspaceName: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.outboxURL(workspaceID), withIntermediateDirectories: true)
        try? fm.createDirectory(at: Self.teamDir(workspaceID).appendingPathComponent("artifacts", isDirectory: true),
                                withIntermediateDirectories: true)
        let board = Self.boardURL(workspaceID)
        if !fm.fileExists(atPath: board.path) {
            try? Self.boardTemplate(workspaceName: workspaceName).write(to: board, atomically: true, encoding: .utf8)
        }
        // Always rewritten so an old team dir picks up protocol changes.
        try? Self.protocolText(dir: Self.teamDir(workspaceID).path)
            .write(to: Self.protocolURL(workspaceID), atomically: true, encoding: .utf8)
        startWatcher(workspaceID)
    }

    /// Standing copy of the messaging recipe. The join briefing vanishes when
    /// an agent's CLI compacts its context; this file is what a member
    /// re-reads to recover (the board template points here).
    static func protocolText(dir: String) -> String {
        """
        # Team protocol (recovery card)

        Your team name is in members.md, in this folder. If your tools include the 'ork' MCP
        server, message teammates with team_send (team_board and team_members read the rest).
        Otherwise send a message by writing a file:

            echo "done 3: parser fixed, tests green" > "\(dir)/outbox/YOURNAME__RECIPIENT__$RANDOM.md"

        RECIPIENT is a member name from members.md, 'all' (broadcast), or 'ork' (the app itself:
        'sleep' parks your terminal, 'escalate <id>: reason' alerts the human user,
        'archive <summary>', coordinator only, closes the demand into history/).
        Incoming messages appear in your terminal as [team msg from NAME].

        Shapes: task <id> | claim <id> | done <id>: outcome | rework <id>: problems | approved <id> | blocked <id>: reason.
        Max \(messageCharCap) chars per message; details live on the board or in commits, messages carry pointers.
        Payloads too big for the board go to files under \(dir)/artifacts/; the message carries the path.
        Backlog tasks marked '(after <id>)' wait until that task is approved.
        No acknowledgements: silence means received; every message costs the recipient a full turn.
        board.md is the single source of truth; read it before starting any task.
        Members rebase onto the base branch before 'done'; the coordinator integrates approved
        work (push + 'gh pr create', or a local merge) before archiving the demand.
        """
    }

    static func boardTemplate(workspaceName: String) -> String {
        """
        # Team Board — \(workspaceName)

        Shared context for every agent on this team. Read before starting a task.
        Keep it small: this file is read often, so redundancy costs everyone.
        Forgot how to message teammates? Read protocol.md in this folder.

        ## Backlog
        <!-- unclaimed tasks, coordinator writes: - [ ] id: goal, files, done-criteria, '(after <id>)' if dependent -->

        ## Tasks
        <!-- claimed work only: - [ ] id: task — owner ; approved rounds move to Archive -->

        ## Decisions
        <!-- one line each, append-only -->

        ## Status
        <!-- ONE line per member, overwrite your own: name: current state -->

        ## Archive

        """
    }

    /// Roster with worktree paths, so the coordinator can review a member's
    /// diff without asking for it. A separate file keeps Ork's rewrites from
    /// racing agent edits to the board.
    func writeMembersFile(_ workspaceID: UUID) {
        guard let store else { return }
        let members = store.teamMembers(in: workspaceID)
        let lines = members.enumerated().map { index, member in
            "- \(Self.memberName(member))\(index == 0 ? " (coordinator)" : "") — worktree: \(member.directory)"
        }
        let content = "# Team members\n\n" + (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n")
        try? content.write(to: Self.membersURL(workspaceID), atomically: true, encoding: .utf8)
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
        startWatchdogIfNeeded()
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

    /// The cap disciplines agents; the user pastes a long demand on purpose.
    static func overCap(_ content: String, from sender: String) -> Bool {
        sender != "user" && content.count > messageCharCap
    }

    /// Writes an over-cap message whole to the team's artifacts dir and
    /// returns the file, so delivery can carry a pointer instead of a cut.
    static func spillLongMessage(_ workspaceID: UUID, sender: String, content: String) -> URL {
        let dir = teamDir(workspaceID).appendingPathComponent("artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("msg-\(sender)-\(Int(Date().timeIntervalSince1970 * 1000)).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The agent canvas highlights routed messages; nil sender means the
    /// user or the app spoke.
    var onRoute: ((UUID?, UUID) -> Void)?

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
            var content = (try? String(contentsOf: url, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Empty reads usually mean the writer has not flushed yet; the
            // next directory event retries this file.
            guard !content.isEmpty else { continue }
            try? fm.removeItem(at: url)

            if suppressDuplicate(sender: parsed.sender, recipient: parsed.recipient, content: content) {
                appendLog(workspaceID, "- [\(Self.timestamp())] \(parsed.sender) → \(parsed.recipient): duplicate within \(Int(Self.dedupWindow)) s, suppressed")
                continue
            }
            appendLog(workspaceID, "- [\(Self.timestamp())] \(parsed.sender) → \(parsed.recipient): \(content)")
            if Self.overCap(content, from: parsed.sender) {
                // Spill, never cut: the whole text lands in artifacts/ and the
                // recipient gets the path, so nothing is lost to summarizing.
                let spilled = Self.spillLongMessage(workspaceID, sender: parsed.sender, content: content)
                appendLog(workspaceID, "  (spilled: \(content.count) chars → \(spilled.lastPathComponent))")
                content = "long message (\(content.count) chars) saved whole to \(spilled.path). Read it before acting."
            }
            if parsed.recipient == Self.controlRecipient {
                handleControl(workspaceID, sender: parsed.sender, content: content, members: members)
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
            let canonicalRecipient = targets.count == 1 ? Self.memberName(targets[0]) : parsed.recipient
            trackTask(workspaceID: workspaceID, sender: parsed.sender, recipient: canonicalRecipient, content: content)
            let senderID = members.first(where: { Self.memberName($0) == parsed.sender })?.id
            for target in targets {
                if target.hibernated {
                    appendLog(workspaceID, "  (skipped \(Self.memberName(target)): hibernated, sender notified)")
                    notify(memberNamed: parsed.sender, in: members,
                           text: "\(Self.memberName(target)) is hibernated and did not receive your message. Ask the user to resume it, then resend.")
                    continue
                }
                perTarget[target.id, default: []].append("[team msg from \(parsed.sender)] \(content)")
                onRoute?(senderID, target.id)
            }
            if targets.contains(where: { !$0.hibernated }) {
                routedSummaries.append("\(parsed.sender) → \(parsed.recipient): \(content.prefix(56))")
            }
        }
        for (id, lines) in perTarget {
            inject(lines, into: id)
        }
        for message in routedSummaries {
            EventFeed.shared.post(symbol: "bubble.left.and.bubble.right", text: message)
        }
    }

    // MARK: - Dedup

    /// Agents occasionally fire the same echo twice (retry after compaction,
    /// shell history replay); each duplicate costs the recipient a full turn.
    private var recentMessages: [String: Date] = [:]
    static let dedupWindow: TimeInterval = 60

    /// True when this exact sender→recipient content already went out inside
    /// the window; records the message otherwise. The user resends on purpose.
    func suppressDuplicate(sender: String, recipient: String, content: String, now: Date = Date()) -> Bool {
        recentMessages = recentMessages.filter { now.timeIntervalSince($0.value) < Self.dedupWindow }
        guard sender != "user" else { return false }
        let key = "\(sender)|\(recipient)|\(content)"
        if recentMessages[key] != nil { return true }
        recentMessages[key] = now
        return false
    }

    // MARK: - Quiescence-gated injection

    /// Typing into a PTY while the CLI is mid-turn gets the text swallowed by
    /// a TUI repaint or spliced into the agent's own output. Delivery waits
    /// until the recipient's process group has been CPU-quiet for one window;
    /// messages arriving meanwhile pile onto the same batch. The check cap
    /// keeps a long-running build from starving delivery forever.
    private var holdQueues: [UUID: [String]] = [:]
    private var holding: Set<UUID> = []
    private static let quietWindow: TimeInterval = 2
    private static let maxHoldChecks = 30

    /// Same bar as idle freeze: below this CPU fraction the CLI is repainting
    /// a spinner or waiting at its prompt, not producing output.
    static func isQuiet(cpuDelta: Double, window: TimeInterval) -> Bool {
        cpuDelta / window <= 0.06
    }

    private func inject(_ lines: [String], into id: UUID) {
        pendingSleeps.removeValue(forKey: id)?.cancel()
        holdQueues[id, default: []].append(contentsOf: lines)
        guard !holding.contains(id) else { return }
        guard let pid = TerminalRegistry.shared.shellPid(for: id) else {
            flush(id)
            return
        }
        holding.insert(id)
        waitForQuiet(id, pid: pid, lastCPU: ProcessCPU.groupCPUSeconds(pgid: pid), checksLeft: Self.maxHoldChecks)
    }

    private func waitForQuiet(_ id: UUID, pid: pid_t, lastCPU: Double, checksLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.quietWindow) { [weak self] in
            guard let self, self.holding.contains(id) else { return }
            let cpu = ProcessCPU.groupCPUSeconds(pgid: pid)
            if !Self.isQuiet(cpuDelta: cpu - lastCPU, window: Self.quietWindow), checksLeft > 1 {
                self.waitForQuiet(id, pid: pid, lastCPU: cpu, checksLeft: checksLeft - 1)
            } else {
                self.holding.remove(id)
                self.flush(id)
            }
        }
    }

    private func flush(_ id: UUID) {
        guard let lines = holdQueues.removeValue(forKey: id), !lines.isEmpty else { return }
        store?.wake(id)
        TerminalRegistry.shared.send(id, text: Self.bracketedPaste(lines.joined(separator: "\n")) + "\r")
    }

    // MARK: - Orphaned tasks

    /// Open '## Tasks' entries owned by this member (shape: - [ ] id: task — owner).
    static func openTaskIDs(onBoard board: String, owner: String) -> [String] {
        guard let tasks = sectionBody("## Tasks", in: board) else { return [] }
        return tasks.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [ ]"),
                  trimmed.components(separatedBy: " — ").last?.trimmingCharacters(in: .whitespaces) == owner
            else { return nil }
            let body = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let id = body.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : id
        }
    }

    /// A departed member's open tasks deadlock the team: the coordinator
    /// waits forever for a 'done' that will never come.
    func alertOrphanedTasks(workspaceID: UUID, departed name: String) {
        guard let board = try? String(contentsOf: Self.boardURL(workspaceID), encoding: .utf8) else { return }
        let ids = Self.openTaskIDs(onBoard: board, owner: name)
        guard !ids.isEmpty, let members = store?.teamMembers(in: workspaceID),
              let coordinator = members.first else { return }
        let list = ids.joined(separator: ", ")
        notify(memberNamed: Self.memberName(coordinator), in: members,
               text: "\(name) left with open task(s) \(list) on the board. Move them back to '## Backlog' or reassign them.")
        appendLog(workspaceID, "  (orphaned task(s) \(list) from \(name) flagged to the coordinator)")
    }

    // MARK: - Task watchdog

    /// A claimed task with no done/blocked after this long usually means the
    /// owner stalled silently or forgot to report; one nudge un-sticks it.
    struct TaskClock {
        let owner: String
        let started: Date
        var nudged = false
    }

    static let watchdogThreshold: TimeInterval = 30 * 60
    private(set) var taskClocks: [String: TaskClock] = [:]
    private var watchdog: Timer?

    static func clockKey(_ workspaceID: UUID, _ taskID: String) -> String {
        "\(workspaceID.uuidString)|\(taskID)"
    }

    /// Message shapes drive the clocks: claim/task/rework start one,
    /// done/blocked/approved clear it. Broadcasts assign nobody.
    func trackTask(workspaceID: UUID, sender: String, recipient: String, content: String, now: Date = Date()) {
        let parts = content.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return }
        let id = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: ":,."))
        guard !id.isEmpty else { return }
        let key = Self.clockKey(workspaceID, id)
        switch parts[0].lowercased() {
        case "claim": taskClocks[key] = TaskClock(owner: sender, started: now)
        case "task", "rework": if recipient != "all" { taskClocks[key] = TaskClock(owner: recipient, started: now) }
        case "done", "blocked", "approved": taskClocks[key] = nil
        default: break
        }
    }

    static func dueKeys(in clocks: [String: TaskClock], now: Date) -> [String] {
        clocks.filter { !$0.value.nudged && now.timeIntervalSince($0.value.started) > watchdogThreshold }
            .map(\.key).sorted()
    }

    private func startWatchdogIfNeeded() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.sweepTaskClocks() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func sweepTaskClocks(now: Date = Date()) {
        for key in Self.dueKeys(in: taskClocks, now: now) {
            taskClocks[key]?.nudged = true
            guard let clock = taskClocks[key],
                  let wsID = UUID(uuidString: String(key.prefix(36))),
                  let members = store?.teamMembers(in: wsID),
                  members.contains(where: { Self.memberName($0) == clock.owner }) else {
                taskClocks[key] = nil
                continue
            }
            let taskID = String(key.dropFirst(37))
            notify(memberNamed: clock.owner, in: members,
                   text: "task \(taskID) has been open for 30+ min with no done/blocked. Update '## Status' on the board, or send 'blocked \(taskID): reason' so it can be reassigned.")
            appendLog(wsID, "  (watchdog nudged \(clock.owner) about task \(taskID))")
        }
    }

    /// System note typed into one member's terminal, waking it if frozen.
    /// The user has no terminal, so their bounces surface in the event feed
    /// instead of vanishing.
    func notify(memberNamed name: String, in members: [TerminalSession], text: String) {
        guard let session = members.first(where: { Self.memberName($0) == name }), !session.hibernated else {
            if name == "user" {
                EventFeed.shared.post(symbol: "exclamationmark.bubble", tintHex: 0xE0A458, text: String(text.prefix(120)))
            }
            return
        }
        inject(["[team] \(text)"], into: session.id)
    }

    // MARK: - Control channel

    /// Reserved recipient: messages addressed to 'ork' talk to the app itself.
    static let controlRecipient = "ork"

    private var pendingSleeps: [UUID: DispatchWorkItem] = [:]

    /// 'sleep' parks the sender's terminal (any team message wakes it, so a
    /// member can park without telling anyone); 'escalate <id>: reason'
    /// raises a macOS notification for the user.
    private func handleControl(_ workspaceID: UUID, sender: String, content: String, members: [TerminalSession]) {
        guard let session = members.first(where: { Self.memberName($0) == sender }) else {
            appendLog(workspaceID, "  (control from unknown sender '\(sender)' ignored)")
            return
        }
        let lowered = content.lowercased()
        if lowered == "sleep" {
            appendLog(workspaceID, "  (control: \(sender) sleeps until messaged)")
            // A short grace lets the CLI finish printing its turn before the
            // SIGSTOP; an incoming message meanwhile cancels the park so the
            // member is never frozen mid-task.
            let id = session.id
            let work = DispatchWorkItem { [weak self] in
                self?.pendingSleeps[id] = nil
                self?.store?.sleepSession(id)
            }
            pendingSleeps[id]?.cancel()
            pendingSleeps[id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        } else if lowered.hasPrefix("escalate") {
            let reason = String(content.dropFirst("escalate".count)).trimmingCharacters(in: .whitespaces)
            appendLog(workspaceID, "  (control: \(sender) escalated to the user)")
            EventFeed.shared.post(symbol: "exclamationmark.triangle.fill", tintHex: 0xE0A458,
                                  text: "\(sender) needs you: \(reason.prefix(56))")
            Notifier.notify(title: "\(sender) needs a decision", body: String(reason.prefix(120)))
        } else if lowered.hasPrefix("archive") {
            guard members.first.map(Self.memberName) == sender else {
                notify(memberNamed: sender, in: members,
                       text: "only the coordinator archives the board.")
                return
            }
            let summary = String(content.dropFirst("archive".count)).trimmingCharacters(in: .whitespaces)
            archiveBoard(workspaceID, summary: summary, by: sender, members: members)
        } else {
            notify(memberNamed: sender, in: members,
                   text: "unknown control command for 'ork'. Use 'sleep', 'escalate <id>: reason' or 'archive <summary>'.")
        }
    }

    /// Rotates a finished demand out of the hot board: full snapshot into
    /// history/, working sections reset from the template, '## Decisions'
    /// carried over. Every agent reads the board often, so history must not
    /// live inside it.
    private func archiveBoard(_ workspaceID: UUID, summary: String, by sender: String, members: [TerminalSession]) {
        let boardURL = Self.boardURL(workspaceID)
        guard let board = try? String(contentsOf: boardURL, encoding: .utf8),
              let workspaceName = store?.workspace(id: workspaceID)?.name else { return }
        let dir = Self.historyDir(workspaceID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Self.fileStampFormatter.string(from: Date())
        let slug = Self.sanitizedName(summary).lowercased().replacingOccurrences(of: " ", with: "-")
        let filename = slug.isEmpty ? "\(stamp).md" : "\(stamp)-\(slug).md"
        let header = "<!-- archived \(stamp) by \(sender): \(summary) -->\n\n"
        try? (header + board).write(to: dir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        try? Self.resetBoard(previous: board, workspaceName: workspaceName)
            .write(to: boardURL, atomically: true, encoding: .utf8)
        // Next demand reuses small task ids; stale clocks would nudge ghosts.
        taskClocks = taskClocks.filter { !$0.key.hasPrefix(workspaceID.uuidString) }
        appendLog(workspaceID, "  (control: \(sender) archived the board → history/\(filename))")
        EventFeed.shared.post(symbol: "archivebox", text: "\(sender) closed the demand: \(summary.prefix(48))")
        notify(memberNamed: sender, in: members,
               text: "board archived to history/\(filename) and reset; '## Decisions' kept.")
    }

    /// Fresh board for the next demand; only '## Decisions' survives, it is
    /// durable team context rather than per-demand state.
    static func resetBoard(previous: String, workspaceName: String) -> String {
        let fresh = boardTemplate(workspaceName: workspaceName)
        guard let kept = sectionBody("## Decisions", in: previous),
              let blank = sectionBody("## Decisions", in: fresh) else { return fresh }
        return fresh.replacingOccurrences(of: "## Decisions\n" + blank, with: "## Decisions\n" + kept)
    }

    /// Compact kanban read of the board: one entry per bullet line, bullet
    /// stripped. The team pane renders these as columns above the raw board.
    static func boardColumns(_ board: String) -> (backlog: [String], tasks: [String], archive: [String]) {
        func items(_ heading: String) -> [String] {
            (sectionBody(heading, in: board) ?? "").components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("- ") }
                .map { String($0.dropFirst(2)) }
        }
        return (items("## Backlog"), items("## Tasks"), items("## Archive"))
    }

    /// Lines between a '## Heading' and the next '## ', exclusive.
    static func sectionBody(_ heading: String, in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: heading) else { return nil }
        var end = start + 1
        while end < lines.count, !lines[end].hasPrefix("## ") { end += 1 }
        return lines[(start + 1)..<end].joined(separator: "\n")
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

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
