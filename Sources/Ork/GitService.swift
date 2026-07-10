import Foundation

/// Read-only git plumbing for the history pane and session diff stats.
enum GitService {
    struct Stats: Equatable {
        var insertions = 0
        var deletions = 0
        var newFiles = 0
        var ahead = 0

        var isClean: Bool { insertions == 0 && deletions == 0 && newFiles == 0 }
    }

    struct Commit: Hashable, Identifiable {
        let sha: String
        let parents: [String]
        let author: String
        let date: Date
        let subject: String
        var id: String { sha }
        var shortSHA: String { String(sha.prefix(7)) }
    }

    struct Worktree: Hashable {
        let path: String
        let branch: String
        let isMain: Bool
    }

    struct FileChange: Hashable, Identifiable {
        let path: String
        let insertions: Int
        let deletions: Int
        var id: String { path }
    }

    static func run(_ args: [String], in repo: String) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repo] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return (false, "") }
        // Drain before waiting: a full 64 KB pipe buffer deadlocks waitUntilExit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }

    /// Uncommitted lines vs HEAD, untracked files, and commits ahead of the base branch.
    static func stats(worktree dir: String, baseBranch: String?) -> Stats {
        var stats = Stats()
        let numstat = run(["diff", "--numstat", "HEAD"], in: dir)
        if numstat.ok {
            for line in numstat.output.split(separator: "\n") {
                let cols = line.split(separator: "\t")
                guard cols.count >= 2 else { continue }
                stats.insertions += Int(cols[0]) ?? 0
                stats.deletions += Int(cols[1]) ?? 0
            }
        }
        let untracked = run(["ls-files", "--others", "--exclude-standard"], in: dir)
        if untracked.ok {
            stats.newFiles = untracked.output.split(separator: "\n").count
        }
        if let base = baseBranch {
            let ahead = run(["rev-list", "--count", "\(base)..HEAD"], in: dir)
            if ahead.ok {
                stats.ahead = Int(ahead.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
        }
        return stats
    }

    static func defaultBranch(repo: String) -> String? {
        let result = run(["symbolic-ref", "--short", "HEAD"], in: repo)
        guard result.ok else { return nil }
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func log(repo: String, limit: Int = 200) -> [Commit] {
        // Unit separators keep subjects with any punctuation parseable.
        let format = "%H%x1f%P%x1f%an%x1f%at%x1f%s%x1e"
        let result = run(["log", "--all", "--topo-order", "-n", "\(limit)", "--pretty=format:\(format)"], in: repo)
        guard result.ok else { return [] }
        return result.output.split(separator: "\u{1e}").compactMap { record in
            let fields = record
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\u{1f}")
            guard fields.count >= 5 else { return nil }
            return Commit(
                sha: fields[0],
                parents: fields[1].split(separator: " ").map(String.init),
                author: fields[2],
                date: Date(timeIntervalSince1970: TimeInterval(fields[3]) ?? 0),
                subject: fields[4]
            )
        }
    }

    /// sha of the tip -> branch names pointing at it.
    static func branchTips(repo: String) -> [String: [String]] {
        let result = run(["for-each-ref", "refs/heads", "--format", "%(objectname) %(refname:short)"], in: repo)
        guard result.ok else { return [:] }
        var map: [String: [String]] = [:]
        for line in result.output.split(separator: "\n") {
            guard let space = line.firstIndex(of: " ") else { continue }
            map[String(line[..<space]), default: []].append(String(line[line.index(after: space)...]))
        }
        return map
    }

    static func worktrees(repo: String) -> [Worktree] {
        let result = run(["worktree", "list", "--porcelain"], in: repo)
        guard result.ok else { return [] }
        var items: [Worktree] = []
        var path: String?
        for line in result.output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch refs/heads/"), let p = path {
                items.append(Worktree(path: p, branch: String(line.dropFirst("branch refs/heads/".count)), isMain: items.isEmpty))
                path = nil
            }
        }
        return items
    }

    static func changedFiles(repo: String, sha: String) -> [FileChange] {
        let result = run(["show", "--numstat", "--format=", sha], in: repo)
        guard result.ok else { return [] }
        return result.output.split(separator: "\n").compactMap { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { return nil }
            return FileChange(
                path: String(cols[2]),
                insertions: Int(cols[0]) ?? 0,
                deletions: Int(cols[1]) ?? 0
            )
        }
    }

    static func patch(repo: String, sha: String, file: String) -> String {
        run(["show", "--format=", sha, "--", file], in: repo).output
    }
}
