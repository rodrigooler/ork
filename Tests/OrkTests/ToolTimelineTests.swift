import XCTest
@testable import Ork

final class ToolTimelineTests: XCTestCase {
    func testEncodedProjectDirMatchesClaudeConvention() {
        XCTAssertEqual(ToolTimelineService.encodedProjectDir("/Users/me/www/ork"), "-Users-me-www-ork")
        XCTAssertEqual(ToolTimelineService.encodedProjectDir("/Users/me/www/.ork-worktrees/ork/claude-a1b2"),
                       "-Users-me-www--ork-worktrees-ork-claude-a1b2")
    }

    func testParsePullsToolUseBlocksInOrder() {
        let lines = """
        {"type":"user","timestamp":"2026-07-11T10:00:00.000Z","message":{"content":"hi"}}
        {"type":"assistant","timestamp":"2026-07-11T10:00:05.000Z","message":{"content":[{"type":"text","text":"ok"},{"type":"tool_use","name":"Bash","input":{"command":"swift test"}}]}}
        {"type":"assistant","timestamp":"2026-07-11T10:00:09.000Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/a.swift"}}]}}
        not json at all
        """
        let events = ToolTimelineService.parse(lines)
        XCTAssertEqual(events.map(\.tool), ["Bash", "Read"])
        XCTAssertEqual(events[0].detail, "swift test")
        XCTAssertEqual(events[1].detail, "/tmp/a.swift")
        XCTAssertTrue(events[0].time < events[1].time)
    }

    func testDetailPicksTheHumanFieldAndFlattensNewlines() {
        XCTAssertEqual(ToolTimelineService.detail(from: ["command": "git\nstatus"]), "git status")
        XCTAssertEqual(ToolTimelineService.detail(from: ["irrelevant": 1]), "")
        XCTAssertEqual(ToolTimelineService.detail(from: nil), "")
        let long = String(repeating: "x", count: 100)
        XCTAssertEqual(ToolTimelineService.detail(from: ["query": long]).count, 64)
    }
}
