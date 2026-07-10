import XCTest
@testable import Ork

final class TerminalSessionDecodingTests: XCTestCase {
    func testDecodesStateWrittenBeforeHibernatedExisted() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "workspaceID":"22222222-2222-2222-2222-222222222222",
         "agent":{"slug":"claude","name":"Claude Code","command":"claude","symbol":"sparkles","tintHex":14251863},
         "directory":"/tmp","worktreeBranch":null,"exited":false}
        """
        let session = try JSONDecoder().decode(TerminalSession.self, from: Data(json.utf8))
        XCTAssertFalse(session.hibernated)
        XCTAssertFalse(session.exited)
        XCTAssertEqual(session.agent.slug, "claude")
    }

    func testHibernatedRoundTrips() throws {
        var session = TerminalSession(
            id: UUID(), workspaceID: UUID(), agent: .builtin[0], directory: "/tmp", worktreeBranch: "ork/claude-abcd"
        )
        session.hibernated = true
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: JSONEncoder().encode(session))
        XCTAssertTrue(decoded.hibernated)
        XCTAssertEqual(decoded.worktreeBranch, "ork/claude-abcd")
    }
}
