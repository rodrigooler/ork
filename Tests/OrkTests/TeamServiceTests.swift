import XCTest
@testable import Ork

final class TeamServiceTests: XCTestCase {
    func testParseMessageFilename() {
        XCTAssertEqual(TeamService.parseMessageFilename("claude-a1b2__codex-c3d4__123.md")?.sender, "claude-a1b2")
        XCTAssertEqual(TeamService.parseMessageFilename("claude-a1b2__codex-c3d4__123.md")?.recipient, "codex-c3d4")
        XCTAssertEqual(TeamService.parseMessageFilename("claude-a1b2__all__9.md")?.recipient, "all")
        XCTAssertEqual(TeamService.parseMessageFilename("a__b.md")?.sender, "a")
        XCTAssertNil(TeamService.parseMessageFilename("no-separator.md"))
        XCTAssertNil(TeamService.parseMessageFilename("a__b.txt"))
        XCTAssertNil(TeamService.parseMessageFilename(".DS_Store"))
    }

    func testBracketedPasteWrapsText() {
        let wrapped = TeamService.bracketedPaste("hello")
        XCTAssertTrue(wrapped.hasPrefix("\u{1B}[200~"))
        XCTAssertTrue(wrapped.hasSuffix("\u{1B}[201~"))
        XCTAssertTrue(wrapped.contains("hello"))
    }

    func testBriefingNamesEveryoneAndThePaths() {
        let workspace = Workspace(id: UUID(), name: "acme", path: "/tmp/acme", organizationID: nil)
        let session = TerminalSession(
            id: UUID(), workspaceID: workspace.id, agent: .builtin[0], directory: "/tmp/acme", worktreeBranch: nil
        )
        let name = TeamService.memberName(session)
        let briefing = TeamService.shared.briefing(for: session, workspace: workspace, teammates: ["codex-9f9f"])
        XCTAssertTrue(briefing.contains(name))
        XCTAssertTrue(briefing.contains("codex-9f9f"))
        XCTAssertTrue(briefing.contains("board.md"))
        XCTAssertTrue(briefing.contains("\(name)__MEMBER__"))
        XCTAssertTrue(briefing.contains(workspace.id.uuidString))
    }

    private func member(_ slug: String, _ ws: UUID, id: UUID = UUID()) -> TerminalSession {
        let agent = AgentProfile.builtin.first { $0.slug == slug } ?? .builtin[0]
        return TerminalSession(id: id, workspaceID: ws, agent: agent, directory: "/tmp", worktreeBranch: nil)
    }

    func testResolveExactAllFuzzyAndStrays() {
        let ws = UUID()
        // Fixed id: a random one can yield a digit-only shortID (~15% of
        // UUIDs), which resolve rejects by design and the fuzzy assertion
        // below would flake.
        let claude = member("claude", ws, id: UUID(uuidString: "ABCD1234-0000-4000-8000-000000000000")!)
        let codex = member("codex", ws)
        let members = [claude, codex]
        let claudeName = TeamService.memberName(claude)
        let codexName = TeamService.memberName(codex)

        XCTAssertEqual(TeamService.resolve(claudeName, from: codexName, members: members).map(TeamService.memberName), [claudeName])
        XCTAssertEqual(TeamService.resolve("all", from: claudeName, members: members).map(TeamService.memberName), [codexName])
        // Unique fuzzy: the short id alone finds its member.
        XCTAssertEqual(TeamService.resolve(claude.shortID, from: codexName, members: members).map(TeamService.memberName), [claudeName])
        // A bare $RANDOM (digits only) must never match anyone.
        XCTAssertTrue(TeamService.resolve("4687", from: claudeName, members: members).isEmpty)
        // Ambiguous needles resolve to nobody rather than guessing.
        let claude2 = member("claude", ws)
        XCTAssertTrue(TeamService.resolve("claude", from: codexName, members: [claude, claude2]).isEmpty)
    }

    func testMemberNameHonorsCustomNameAndResolveFindsIt() {
        let ws = UUID()
        var rodrigo = member("claude", ws)
        XCTAssertEqual(TeamService.memberName(rodrigo), "claude-\(rodrigo.shortID)")
        rodrigo.customName = "Rodrigo"
        XCTAssertEqual(TeamService.memberName(rodrigo), "Rodrigo")
        let codex = member("codex", ws)
        let members = [rodrigo, codex]
        XCTAssertEqual(TeamService.resolve("Rodrigo", from: "x", members: members).map(TeamService.memberName), ["Rodrigo"])
        // Case-insensitive fuzzy still lands on the renamed member.
        XCTAssertEqual(TeamService.resolve("rodrigo", from: "x", members: members).map(TeamService.memberName), ["Rodrigo"])
    }

    func testSanitizedNameKeepsFilenamesParseable() {
        XCTAssertEqual(TeamService.sanitizedName("Ro__dri/go:"), "Rodrigo")
        XCTAssertEqual(TeamService.sanitizedName("  Carlos Eduardo  "), "Carlos Eduardo")
        XCTAssertEqual(TeamService.sanitizedName("///"), "")
        XCTAssertEqual(TeamService.sanitizedName(String(repeating: "a", count: 40)).count, 24)
    }

    func testUserMessageFilenameRoundTrips() {
        let parsed = TeamService.parseMessageFilename(TeamService.userMessageFilename(to: "all"))
        XCTAssertEqual(parsed?.sender, "user")
        XCTAssertEqual(parsed?.recipient, "all")
    }

    func testBriefingCarriesTheEconomyProtocol() {
        let workspace = Workspace(id: UUID(), name: "acme", path: "/tmp/acme", organizationID: nil)
        let session = member("claude", workspace.id)
        let briefing = TeamService.shared.briefing(for: session, workspace: workspace, teammates: [])
        XCTAssertTrue(briefing.contains("under \(TeamService.messageCharCap) chars"))
        XCTAssertTrue(briefing.contains("never cut"))
        XCTAssertTrue(briefing.contains("straight to the teammate"))
        XCTAssertTrue(briefing.contains("done <id>"))
        XCTAssertTrue(briefing.contains("unverified"))
        XCTAssertTrue(briefing.contains("## Archive"))
    }

    func testProposalsListParseAndDecision() throws {
        let workspaceID = UUID()
        defer { try? FileManager.default.removeItem(at: TeamService.teamDir(workspaceID)) }
        let dir = TeamService.proposalsDir(workspaceID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# Add retry to the webhook consumer\n\nRationale...".write(
            to: dir.appendingPathComponent("100.md"), atomically: true, encoding: .utf8)
        try "no heading first line".write(
            to: dir.appendingPathComponent("200.md"), atomically: true, encoding: .utf8)

        let open = TeamService.openProposals(workspaceID)
        XCTAssertEqual(open.map(\.title), ["Add retry to the webhook consumer", "no heading first line"])

        TeamService.shared.decideProposal(workspaceID, proposal: open[0], approved: true)
        TeamService.shared.decideProposal(workspaceID, proposal: open[1], approved: false)
        XCTAssertTrue(TeamService.openProposals(workspaceID).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("approved/100.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("rejected/200.md").path))
    }

    func testSpillLongMessageKeepsTheWholeText() {
        let workspaceID = UUID()
        defer { try? FileManager.default.removeItem(at: TeamService.teamDir(workspaceID)) }
        let content = String(repeating: "y", count: TeamService.messageCharCap + 500)
        let url = TeamService.spillLongMessage(workspaceID, sender: "claude-1a2b", content: content)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), content)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("msg-claude-1a2b-"))
        XCTAssertTrue(url.path.contains("/artifacts/"))
    }

    func testBriefingCarriesThePersona() {
        let workspace = Workspace(id: UUID(), name: "acme", path: "/tmp/acme", organizationID: nil)
        var session = member("claude", workspace.id)
        session.persona = "security review only"
        let briefing = TeamService.shared.briefing(for: session, workspace: workspace, teammates: [])
        XCTAssertTrue(briefing.contains("Your standing role: security review only."))
        session.persona = nil
        let plain = TeamService.shared.briefing(for: session, workspace: workspace, teammates: [])
        XCTAssertFalse(plain.contains("standing role"))
    }

    func testBriefingCarriesTheReviewAndPullProtocol() {
        let workspace = Workspace(id: UUID(), name: "acme", path: "/tmp/acme", organizationID: nil)
        let coordinator = TeamService.shared.briefing(for: member("claude", workspace.id), workspace: workspace, teammates: [])
        for marker in ["claim <id>", "rework <id>", "approved <id>", "## Backlog", "members.md", "escalate <id>"] {
            XCTAssertTrue(coordinator.contains(marker), "coordinator briefing missing '\(marker)'")
        }
        let mate = TeamService.shared.briefing(for: member("codex", workspace.id), workspace: workspace, teammates: ["claude-1a2b"])
        XCTAssertTrue(mate.contains("claim <id>"))
        XCTAssertTrue(mate.contains("'sleep' to ork"))
    }

    func testBoardTemplateHasThePullQueue() {
        let board = TeamService.boardTemplate(workspaceName: "acme")
        for heading in ["## Backlog", "## Tasks", "## Status", "## Archive"] {
            XCTAssertTrue(board.contains(heading), "board template missing '\(heading)'")
        }
    }

    func testResetBoardKeepsDecisionsAndClearsTheDemand() {
        var board = TeamService.boardTemplate(workspaceName: "acme")
        board = board
            .replacingOccurrences(of: "## Tasks\n", with: "## Tasks\n- [x] 3: ship the parser — Rodrigo\n")
            .replacingOccurrences(of: "## Decisions\n", with: "## Decisions\n- use SQLite, not JSON files\n")
        let fresh = TeamService.resetBoard(previous: board, workspaceName: "acme")
        XCTAssertTrue(fresh.contains("- use SQLite, not JSON files"))
        XCTAssertFalse(fresh.contains("ship the parser"))
        for heading in ["## Backlog", "## Tasks", "## Status", "## Archive"] {
            XCTAssertTrue(fresh.contains(heading))
        }
        // A board without a Decisions section resets to the plain template.
        XCTAssertEqual(TeamService.resetBoard(previous: "no headings here", workspaceName: "acme"),
                       TeamService.boardTemplate(workspaceName: "acme"))
    }

    func testBriefingOffersTheArchiveCommandToTheCoordinator() {
        let workspace = Workspace(id: UUID(), name: "acme", path: "/tmp/acme", organizationID: nil)
        let coordinator = TeamService.shared.briefing(for: member("claude", workspace.id), workspace: workspace, teammates: [])
        XCTAssertTrue(coordinator.contains("archive <one-line summary>"))
        XCTAssertTrue(coordinator.contains("history/"))
    }

    func testProtocolFileCarriesTheRecoveryRecipe() {
        let text = TeamService.protocolText(dir: "/tmp/team")
        for marker in ["/tmp/team/outbox/YOURNAME__RECIPIENT__$RANDOM.md", "members.md", "'sleep'", "board.md",
                       "No acknowledgements"] {
            XCTAssertTrue(text.contains(marker), "protocol.md missing '\(marker)'")
        }
    }

    func testBoardTemplateAndBriefingPointAtTheProtocolFile() {
        XCTAssertTrue(TeamService.boardTemplate(workspaceName: "acme").contains("protocol.md"))
        let workspace = Workspace(id: UUID(), name: "acme", path: "/tmp/acme", organizationID: nil)
        let briefing = TeamService.shared.briefing(for: member("claude", workspace.id), workspace: workspace, teammates: [])
        XCTAssertTrue(briefing.contains("protocol.md"))
    }

    func testUserMessagesAreExemptFromTheCharCap() {
        let long = String(repeating: "x", count: TeamService.messageCharCap + 1)
        XCTAssertTrue(TeamService.overCap(long, from: "claude-1a2b"))
        XCTAssertFalse(TeamService.overCap(long, from: "user"))
        XCTAssertFalse(TeamService.overCap("short", from: "claude-1a2b"))
    }

    func testCoordinatorDelegatesEverythingAndReviewsForReal() {
        let role = TeamService.coordinatorRole
        XCTAssertTrue(role.contains("never implement"))
        XCTAssertFalse(role.contains("take your own share"))
        for marker in ["WHOLE demand", "run the build and tests yourself", "edge cases", "security"] {
            XCTAssertTrue(role.contains(marker), "coordinator role missing '\(marker)'")
        }
    }

    func testProtocolCarriesTheIntegrationGate() {
        let coordinator = TeamService.coordinatorRole
        XCTAssertTrue(coordinator.contains("gh pr create"))
        XCTAssertTrue(coordinator.contains("merge the branch into the base branch"))
        XCTAssertTrue(coordinator.contains("every approved task is integrated"))
        let mate = TeamService.memberRole(coordinator: "claude-1a2b")
        XCTAssertTrue(mate.contains("git rebase"))
        XCTAssertTrue(TeamService.protocolText(dir: "/tmp/team").contains("gh pr create"))
    }

    func testRebriefKeepsTheCoordinatorAndDoesNotStopWork() {
        let workspace = Workspace(id: UUID(), name: "acme", path: "/tmp/acme", organizationID: nil)
        let coordinator = TeamService.shared.briefing(
            for: member("claude", workspace.id), workspace: workspace,
            teammates: ["codex-9f9f"], asCoordinator: true, rebrief: true
        )
        XCTAssertTrue(coordinator.contains("COORDINATOR"))
        XCTAssertTrue(coordinator.contains("continue your current work"))
        XCTAssertFalse(coordinator.contains("Acknowledge this briefing"))

        let mate = TeamService.shared.briefing(
            for: member("codex", workspace.id), workspace: workspace,
            teammates: ["claude-1a2b"], asCoordinator: false, rebrief: true
        )
        XCTAssertTrue(mate.contains("Your coordinator is claude-1a2b"))
        XCTAssertTrue(mate.contains("continue your current work"))
    }

    func testDuplicateMessagesSuppressInsideTheWindowOnly() {
        let service = TeamService()
        let t0 = Date()
        XCTAssertFalse(service.suppressDuplicate(sender: "a", recipient: "b", content: "claim 3", now: t0))
        XCTAssertTrue(service.suppressDuplicate(sender: "a", recipient: "b", content: "claim 3", now: t0.addingTimeInterval(5)))
        // Different recipient or content is a different message.
        XCTAssertFalse(service.suppressDuplicate(sender: "a", recipient: "c", content: "claim 3", now: t0.addingTimeInterval(5)))
        XCTAssertFalse(service.suppressDuplicate(sender: "a", recipient: "b", content: "claim 4", now: t0.addingTimeInterval(5)))
        // Outside the window the same content delivers again.
        XCTAssertFalse(service.suppressDuplicate(sender: "a", recipient: "b", content: "claim 3",
                                                 now: t0.addingTimeInterval(TeamService.dedupWindow + 1)))
        // The user resends on purpose; never suppressed.
        XCTAssertFalse(service.suppressDuplicate(sender: "user", recipient: "b", content: "go", now: t0))
        XCTAssertFalse(service.suppressDuplicate(sender: "user", recipient: "b", content: "go", now: t0))
    }

    func testQuietThresholdMatchesTheIdleFreezeBar() {
        XCTAssertTrue(TeamService.isQuiet(cpuDelta: 0, window: 2))
        XCTAssertTrue(TeamService.isQuiet(cpuDelta: 0.1, window: 2))
        XCTAssertFalse(TeamService.isQuiet(cpuDelta: 0.5, window: 2))
    }

    func testProtocolCarriesDependenciesAndArtifacts() {
        XCTAssertTrue(TeamService.coordinatorRole.contains("(after <id>)"))
        XCTAssertTrue(TeamService.memberRole(coordinator: "claude-1a2b").contains("(after <id>)"))
        let recovery = TeamService.protocolText(dir: "/tmp/team")
        XCTAssertTrue(recovery.contains("/tmp/team/artifacts/"))
        XCTAssertTrue(recovery.contains("(after <id>)"))
        XCTAssertTrue(TeamService.boardTemplate(workspaceName: "acme").contains("(after <id>)"))
        let workspace = Workspace(id: UUID(), name: "acme", path: "/tmp/acme", organizationID: nil)
        let briefing = TeamService.shared.briefing(for: member("claude", workspace.id), workspace: workspace, teammates: [])
        XCTAssertTrue(briefing.contains("artifacts/"))
    }

    func testBoardColumnsSplitTheKanbanStrip() {
        var board = TeamService.boardTemplate(workspaceName: "acme")
        board = board
            .replacingOccurrences(of: "## Backlog\n", with: "## Backlog\n- [ ] 5: audit auth\n- [ ] 6: docs (after 5)\n")
            .replacingOccurrences(of: "## Tasks\n", with: "## Tasks\n- [ ] 3: parser — Rodrigo\n")
            .replacingOccurrences(of: "## Archive\n", with: "## Archive\n- 1: setup, PR #4\n")
        let columns = TeamService.boardColumns(board)
        XCTAssertEqual(columns.backlog, ["[ ] 5: audit auth", "[ ] 6: docs (after 5)"])
        XCTAssertEqual(columns.tasks, ["[ ] 3: parser — Rodrigo"])
        XCTAssertEqual(columns.archive, ["1: setup, PR #4"])
        let empty = TeamService.boardColumns("")
        XCTAssertTrue(empty.backlog.isEmpty && empty.tasks.isEmpty && empty.archive.isEmpty)
    }

    func testOpenTaskIDsFindOnlyTheDepartedOwnersUncheckedTasks() {
        let board = """
        # Team Board — acme

        ## Tasks
        - [ ] 3: ship the parser — Rodrigo
        - [x] 4: write docs — Rodrigo
        - [ ] 5: fix the tests — codex-9f9f
        - [ ] 7: audit auth — Rodrigo

        ## Status
        """
        XCTAssertEqual(TeamService.openTaskIDs(onBoard: board, owner: "Rodrigo"), ["3", "7"])
        XCTAssertEqual(TeamService.openTaskIDs(onBoard: board, owner: "codex-9f9f"), ["5"])
        XCTAssertTrue(TeamService.openTaskIDs(onBoard: board, owner: "ghost").isEmpty)
        XCTAssertTrue(TeamService.openTaskIDs(onBoard: "no sections", owner: "Rodrigo").isEmpty)
    }

    func testTaskClocksFollowTheMessageShapes() {
        let service = TeamService()
        let ws = UUID()
        let t0 = Date()
        service.trackTask(workspaceID: ws, sender: "codex-9f9f", recipient: "Rodrigo", content: "claim 3", now: t0)
        XCTAssertEqual(service.taskClocks[TeamService.clockKey(ws, "3")]?.owner, "codex-9f9f")
        service.trackTask(workspaceID: ws, sender: "Rodrigo", recipient: "codex-9f9f", content: "task 5: fix tests", now: t0)
        XCTAssertEqual(service.taskClocks[TeamService.clockKey(ws, "5")]?.owner, "codex-9f9f")
        service.trackTask(workspaceID: ws, sender: "codex-9f9f", recipient: "Rodrigo", content: "done 3: green", now: t0)
        XCTAssertNil(service.taskClocks[TeamService.clockKey(ws, "3")])
        // Broadcast assignments name nobody; no clock starts.
        service.trackTask(workspaceID: ws, sender: "Rodrigo", recipient: "all", content: "task 9: docs", now: t0)
        XCTAssertNil(service.taskClocks[TeamService.clockKey(ws, "9")])
        // Rework restarts the owner's clock.
        service.trackTask(workspaceID: ws, sender: "Rodrigo", recipient: "codex-9f9f", content: "rework 5: edge cases", now: t0)
        XCTAssertEqual(service.taskClocks[TeamService.clockKey(ws, "5")]?.owner, "codex-9f9f")
    }

    func testWatchdogNudgesOnceAfterTheThreshold() {
        let ws = UUID()
        let t0 = Date()
        var clocks = [TeamService.clockKey(ws, "3"): TeamService.TaskClock(owner: "a", started: t0)]
        XCTAssertTrue(TeamService.dueKeys(in: clocks, now: t0.addingTimeInterval(60)).isEmpty)
        let late = t0.addingTimeInterval(TeamService.watchdogThreshold + 1)
        XCTAssertEqual(TeamService.dueKeys(in: clocks, now: late), [TeamService.clockKey(ws, "3")])
        clocks[TeamService.clockKey(ws, "3")]?.nudged = true
        XCTAssertTrue(TeamService.dueKeys(in: clocks, now: late).isEmpty)
    }

    func testControlFilenameParsesToTheReservedRecipient() {
        let parsed = TeamService.parseMessageFilename("Rodrigo__ork__1234.md")
        XCTAssertEqual(parsed?.sender, "Rodrigo")
        XCTAssertEqual(parsed?.recipient, TeamService.controlRecipient)
    }

    func testFirstJoinerBriefsAsCoordinatorLaterOnesReportToThem() {
        let workspace = Workspace(id: UUID(), name: "acme", path: "/tmp/acme", organizationID: nil)
        let session = TerminalSession(
            id: UUID(), workspaceID: workspace.id, agent: .builtin[0], directory: "/tmp/acme", worktreeBranch: nil
        )
        let first = TeamService.shared.briefing(for: session, workspace: workspace, teammates: [])
        XCTAssertTrue(first.contains("COORDINATOR"))
        XCTAssertTrue(first.contains("## Tasks"))

        let second = TeamService.shared.briefing(for: session, workspace: workspace, teammates: ["claude-1a2b"])
        XCTAssertFalse(second.contains("COORDINATOR"))
        XCTAssertTrue(second.contains("Your coordinator is claude-1a2b"))
    }
}
