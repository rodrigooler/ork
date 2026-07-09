import Foundation

enum WorktreeService {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func isGitRepo(_ path: String) -> Bool {
        run(["git", "-C", path, "rev-parse", "--is-inside-work-tree"]).ok
    }

    /// Creates `<parent>/.ork-worktrees/<repo>/<slug>-<id>` on a fresh `ork/<slug>-<id>` branch.
    static func add(repo: String, slug: String) throws -> (path: String, branch: String) {
        let suffix = String(UUID().uuidString.prefix(4)).lowercased()
        let name = "\(slug)-\(suffix)"
        let repoURL = URL(fileURLWithPath: repo)
        let base = repoURL.deletingLastPathComponent()
            .appendingPathComponent(".ork-worktrees")
            .appendingPathComponent(repoURL.lastPathComponent)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let worktree = base.appendingPathComponent(name)
        let branch = "ork/\(name)"
        // ponytail: blocks the calling thread; worktree add is subsecond on local repos
        let result = run(["git", "-C", repo, "worktree", "add", "-b", branch, worktree.path])
        guard result.ok else {
            throw Failure(message: result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (worktree.path, branch)
    }

    static func remove(repo: String, worktreePath: String, branch: String) {
        _ = run(["git", "-C", repo, "worktree", "remove", "--force", worktreePath])
        _ = run(["git", "-C", repo, "branch", "-D", branch])
    }

    static func orkWorktreeCount(_ repo: String) -> Int {
        let result = run(["git", "-C", repo, "worktree", "list", "--porcelain"])
        guard result.ok else { return 0 }
        return result.output.components(separatedBy: "\n")
            .filter { $0.hasPrefix("branch refs/heads/ork/") }
            .count
    }

    private static func run(_ arguments: [String]) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (false, error.localizedDescription)
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }
}
