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
        XCTAssertTrue(briefing.contains("Max \(TeamService.messageCharCap) chars"))
        XCTAssertTrue(briefing.contains("done <id>"))
        XCTAssertTrue(briefing.contains("unverified"))
        XCTAssertTrue(briefing.contains("## Archive"))
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
