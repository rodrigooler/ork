import XCTest
@testable import Ork

final class CanvasHubLayoutTests: XCTestCase {
    func testHubSitsAboveTheRootAndShiftsTheTree() {
        let with = CanvasLayout.layout(count: 4, hasRoot: true, hasHub: true)
        let without = CanvasLayout.layout(count: 4, hasRoot: true, hasHub: false)
        XCTAssertNotNil(with.hub)
        XCTAssertNil(without.hub)
        XCTAssertEqual(with.hub?.y, CanvasLayout.hubSize.height / 2)
        XCTAssertEqual(with.hub?.x, with.size.width / 2)
        // Every card moves down by the hub band; the tree shape is unchanged.
        let shift = CanvasLayout.hubSize.height + CanvasLayout.vGap
        for (a, b) in zip(with.positions, without.positions) {
            XCTAssertEqual(a.x, b.x, accuracy: 0.001)
            XCTAssertEqual(a.y, b.y + shift, accuracy: 0.001)
        }
        XCTAssertEqual(with.size.height, without.size.height + shift, accuracy: 0.001)
    }

    func testHubNeedsARoot() {
        XCTAssertNil(CanvasLayout.layout(count: 3, hasRoot: false, hasHub: true).hub)
    }

    func testCubicPointHitsBothEndpoints() {
        let from = CGPoint(x: 100, y: 50)
        let to = CGPoint(x: 400, y: 300)
        let start = CanvasLayout.cubicPoint(t: 0, from: from, to: to)
        let end = CanvasLayout.cubicPoint(t: 1, from: from, to: to)
        XCTAssertEqual(start.x, from.x, accuracy: 0.001)
        XCTAssertEqual(start.y, from.y, accuracy: 0.001)
        XCTAssertEqual(end.x, to.x, accuracy: 0.001)
        XCTAssertEqual(end.y, to.y, accuracy: 0.001)
        // Midflight lies between the extremes horizontally.
        let mid = CanvasLayout.cubicPoint(t: 0.5, from: from, to: to)
        XCTAssertGreaterThan(mid.x, from.x)
        XCTAssertLessThan(mid.x, to.x)
    }
}

final class MessageKindTests: XCTestCase {
    func testShapesClassify() {
        XCTAssertEqual(TeamService.messageKind("done 3: parser fixed, tests green"), .done)
        XCTAssertEqual(TeamService.messageKind("Done R2: vite build ok"), .done)
        XCTAssertEqual(TeamService.messageKind("approved 3: verified build and tests"), .approved)
        XCTAssertEqual(TeamService.messageKind("task 4: fix the flaky test"), .other)
        XCTAssertEqual(TeamService.messageKind("donesday plans"), .other)
        XCTAssertEqual(TeamService.messageKind("done"), .other)
    }
}

final class TeamChatParserTests: XCTestCase {
    func testMessagesSystemAnnotationsAndContinuations() {
        let entries = TeamChat.parse([
            "- [18:13:31] Oler - Lead joined",
            "- [18:15:58] Oler - Lead → Chester - Engineer: task R1: review the app.",
            "Context: branch feat/backoffice, 39 files changed",
            "  (bounced: 1470 chars over the 1200 cap)",
            "- [18:16:17] user → all: please rebase",
        ])
        XCTAssertEqual(entries.count, 3)

        XCTAssertEqual(entries[0].kind, .system)
        XCTAssertEqual(entries[0].time, "18:13:31")
        XCTAssertEqual(entries[0].content, "Oler - Lead joined")

        XCTAssertEqual(entries[1].sender, "Oler - Lead")
        XCTAssertEqual(entries[1].recipient, "Chester - Engineer")
        // The continuation line stays attached, the annotation lands aside.
        XCTAssertTrue(entries[1].content.hasPrefix("task R1: review the app."))
        XCTAssertTrue(entries[1].content.contains("39 files changed"))
        XCTAssertEqual(entries[1].annotations, ["bounced: 1470 chars over the 1200 cap"])

        XCTAssertEqual(entries[2].sender, "user")
        XCTAssertEqual(entries[2].recipient, "all")
    }

    func testOrphanContinuationFromATailCutIsDropped() {
        let entries = TeamChat.parse([
            "leftover continuation from a cut entry",
            "  (orphan annotation)",
            "- [09:00:00] a → b: hello",
        ])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].content, "hello")
    }

    func testArrowInsideContentDoesNotConfuseTheSplit() {
        let entries = TeamChat.parse(["- [10:00:00] a → b: rename foo → bar everywhere"])
        XCTAssertEqual(entries[0].sender, "a")
        XCTAssertEqual(entries[0].recipient, "b")
        XCTAssertEqual(entries[0].content, "rename foo → bar everywhere")
    }
}

final class MemberPaletteTests: XCTestCase {
    func testColorIsStableAndInitialsRead() {
        XCTAssertEqual(MemberPalette.hash("Oler - Lead"), MemberPalette.hash("Oler - Lead"))
        XCTAssertNotEqual(MemberPalette.hash("Rose"), MemberPalette.hash("Carl"))
        XCTAssertEqual(MemberPalette.initials("Oler - Lead"), "OL")
        XCTAssertEqual(MemberPalette.initials("claude-8037"), "CL")
        XCTAssertEqual(MemberPalette.initials("Roger - Tests and QA"), "RT")
    }
}

final class LogRotationTests: XCTestCase {
    func testSplitKeepsTheTailOnEntryBoundaries() {
        var lines: [String] = []
        for index in 0..<300 {
            lines.append("- [10:00:\(String(format: "%02d", index % 60))] a → b: message \(index)")
            lines.append("  (annotation \(index))")
        }
        let text = lines.joined(separator: "\n")
        let split = TeamService.splitForRotation(text, keep: 100)
        XCTAssertNotNil(split)
        guard let split else { return }
        // The tail starts at an entry, never at an annotation.
        XCTAssertTrue(split.tail.hasPrefix("- ["))
        XCTAssertTrue(split.archive.hasSuffix("\n"))
        // Nothing is lost across the cut.
        XCTAssertEqual(split.archive + split.tail, text)
        // The tail holds at least the asked-for lines.
        XCTAssertGreaterThanOrEqual(split.tail.components(separatedBy: "\n").count, 100)
    }

    func testSmallLogsDoNotRotate() {
        XCTAssertNil(TeamService.splitForRotation("- [10:00:00] a → b: hi", keep: 200))
    }
}

final class GitHubServiceTests: XCTestCase {
    func testParsePullsAndChecksRollup() throws {
        let json = """
        [
          {"number": 12, "title": "Fix login", "headRefName": "ork/claude-1a2b",
           "url": "https://github.com/acme/app/pull/12",
           "statusCheckRollup": [
             {"status": "COMPLETED", "conclusion": "SUCCESS"},
             {"state": "SUCCESS"}
           ]},
          {"number": 13, "title": "Refactor api", "headRefName": "ork/claude-9d19",
           "url": "https://github.com/acme/app/pull/13",
           "statusCheckRollup": [{"status": "IN_PROGRESS", "conclusion": null}]},
          {"number": 14, "title": "Broken", "headRefName": "main",
           "url": "https://github.com/acme/app/pull/14",
           "statusCheckRollup": [
             {"status": "COMPLETED", "conclusion": "SUCCESS"},
             {"status": "COMPLETED", "conclusion": "FAILURE"}
           ]},
          {"number": 15, "title": "No checks", "headRefName": "chore/x",
           "url": "https://github.com/acme/app/pull/15",
           "statusCheckRollup": []}
        ]
        """
        let pulls = try XCTUnwrap(GitHubService.parsePulls(Data(json.utf8)))
        XCTAssertEqual(pulls.map(\.number), [12, 13, 14, 15])
        XCTAssertEqual(pulls[0].checks, .passing)
        XCTAssertEqual(pulls[1].checks, .pending)
        XCTAssertEqual(pulls[2].checks, .failing)
        XCTAssertEqual(pulls[3].checks, .none)
    }

    func testGarbageIsNil() {
        XCTAssertNil(GitHubService.parsePulls(Data("not json".utf8)))
        XCTAssertNil(GitHubService.parsePulls(Data("{\"a\":1}".utf8)))
    }

    func testOwnerMatchesByWorktreeBranch() {
        let ws = UUID()
        let session = TerminalSession(
            id: UUID(), workspaceID: ws, agent: .builtin[0],
            directory: "/tmp", worktreeBranch: "ork/claude-1a2b"
        )
        XCTAssertEqual(GitHubService.owner(of: "ork/claude-1a2b", among: [session])?.id, session.id)
        XCTAssertNil(GitHubService.owner(of: "main", among: [session]))
    }
}

final class CurrentTaskTests: XCTestCase {
    func testNewestClockWinsAndClearsOnDone() {
        let service = TeamService.shared
        let ws = UUID()
        service.trackTask(workspaceID: ws, sender: "lead", recipient: "rose", content: "task 3: fix parser",
                          now: Date(timeIntervalSince1970: 1000))
        service.trackTask(workspaceID: ws, sender: "rose", recipient: "lead", content: "claim 7",
                          now: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(service.currentTask(workspaceID: ws, member: "rose"), "7")
        service.trackTask(workspaceID: ws, sender: "rose", recipient: "lead", content: "done 7: fixed")
        XCTAssertEqual(service.currentTask(workspaceID: ws, member: "rose"), "3")
        service.trackTask(workspaceID: ws, sender: "rose", recipient: "lead", content: "done 3: fixed")
        XCTAssertNil(service.currentTask(workspaceID: ws, member: "rose"))
    }
}
