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

    private func member(_ slug: String, _ ws: UUID) -> TerminalSession {
        let agent = AgentProfile.builtin.first { $0.slug == slug } ?? .builtin[0]
        return TerminalSession(id: UUID(), workspaceID: ws, agent: agent, directory: "/tmp", worktreeBranch: nil)
    }

    func testResolveExactAllFuzzyAndStrays() {
        let ws = UUID()
        let claude = member("claude", ws)
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
