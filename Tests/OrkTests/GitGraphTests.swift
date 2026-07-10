import XCTest
@testable import Ork

final class GitGraphTests: XCTestCase {
    private func commit(_ sha: String, parents: [String]) -> GitService.Commit {
        GitService.Commit(sha: sha, parents: parents, author: "t", date: Date(timeIntervalSince1970: 0), subject: sha)
    }

    func testLinearHistoryStaysOnLaneZero() {
        let graph = GitGraph(commits: [
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a", parents: []),
        ])
        XCTAssertEqual(graph.rows.map(\.column), [0, 0, 0])
        XCTAssertEqual(graph.maxLanes, 1)
        XCTAssertEqual(graph.rows[1].incoming, [0])
        XCTAssertEqual(graph.rows[2].outgoing, [])
    }

    func testMergeForksAndJoins() {
        // m merges b (first parent) and c; both branched from a.
        let graph = GitGraph(commits: [
            commit("m", parents: ["b", "c"]),
            commit("b", parents: ["a"]),
            commit("c", parents: ["a"]),
            commit("a", parents: []),
        ])
        XCTAssertEqual(graph.rows[0].column, 0)
        XCTAssertEqual(graph.rows[0].outgoing, [0, 1])   // fork: lane 0 to b, lane 1 to c
        XCTAssertEqual(graph.rows[1].column, 0)
        XCTAssertEqual(graph.rows[1].through, [1])       // c's lane passes through b's row
        XCTAssertEqual(graph.rows[2].column, 1)
        XCTAssertEqual(graph.rows[3].column, 0)
        XCTAssertEqual(graph.rows[3].incoming.sorted(), [0, 1])  // both lanes converge on a
        XCTAssertEqual(graph.maxLanes, 2)
    }

    func testSecondBranchTipTakesFreeLane() {
        // Two independent tips (main and ork/x) sharing history.
        let graph = GitGraph(commits: [
            commit("x", parents: ["a"]),
            commit("y", parents: ["a"]),
            commit("a", parents: []),
        ])
        XCTAssertEqual(graph.rows[0].column, 0)
        XCTAssertEqual(graph.rows[1].column, 1)          // second tip gets its own lane
        XCTAssertEqual(graph.rows[2].incoming.sorted(), [0, 1])
    }
}
