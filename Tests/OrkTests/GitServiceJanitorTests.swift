import XCTest
@testable import Ork

final class GitServiceJanitorTests: XCTestCase {
    private var base: URL!
    private var repo: String!
    private var worktree: String!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ork-git-test-\(UUID().uuidString.prefix(8))")
        repo = base.appendingPathComponent("repo").path
        worktree = base.appendingPathComponent("wt").path
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        git("init", "-b", "main")
        git("config", "user.email", "test@ork")
        git("config", "user.name", "ork test")
        try write("one\n", to: repo + "/file.txt")
        git("add", ".")
        git("commit", "-m", "init")
        git("worktree", "add", "-b", "ork/test", worktree)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func git(_ args: String..., in dir: String? = nil) {
        let result = GitService.runMerged(Array(args), in: dir ?? repo)
        XCTAssertTrue(result.ok, "git \(args.joined(separator: " ")): \(result.output)")
    }

    private func write(_ text: String, to path: String) throws {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func testWorktreeDiffSeesUncommittedChangesAndCleanMergeSucceeds() throws {
        try write("one\ntwo\n", to: worktree + "/file.txt")
        let files = GitService.worktreeDiffFiles(dir: worktree, base: "main")
        XCTAssertEqual(files.map(\.path), ["file.txt"])
        XCTAssertEqual(files.first?.insertions, 1)
        XCTAssertEqual(files.first?.deletions, 0)

        let patch = GitService.worktreeDiffPatch(dir: worktree, base: "main", file: "file.txt")
        XCTAssertTrue(patch.contains("+two"))

        git("add", ".", in: worktree)
        git("commit", "-m", "change", in: worktree)
        let merge = GitService.merge(repo: repo, branch: "ork/test")
        XCTAssertTrue(merge.ok, merge.output)
        XCTAssertEqual(GitService.stats(worktree: worktree, baseBranch: "main").ahead, 0)
    }

    func testConflictedMergeAbortsCleanly() throws {
        try write("main version\n", to: repo + "/file.txt")
        git("commit", "-am", "main change")
        try write("worktree version\n", to: worktree + "/file.txt")
        git("commit", "-am", "worktree change", in: worktree)

        let merge = GitService.merge(repo: repo, branch: "ork/test")
        XCTAssertFalse(merge.ok)

        let status = GitService.run(["status", "--porcelain"], in: repo)
        XCTAssertEqual(status.output.trimmingCharacters(in: .whitespacesAndNewlines), "",
                       "repo left dirty after aborted merge")
    }
}
