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
        XCTAssertTrue(briefing.contains("\(name)__TEAMMATE__"))
        XCTAssertTrue(briefing.contains(workspace.id.uuidString))
    }
}
