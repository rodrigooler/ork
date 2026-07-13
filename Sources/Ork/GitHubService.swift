import Foundation

/// One open pull request as the canvas hub node shows it.
struct PullRequest: Identifiable, Equatable {
    enum Checks: Equatable {
        case passing, failing, pending, none
    }

    let number: Int
    let title: String
    let branch: String
    let url: URL
    let checks: Checks

    var id: Int { number }
}

/// Open PRs and their CI state, read through the gh CLI in the workspace
/// directory. Polls only while the canvas is on screen, and every failure
/// (gh missing or unauthenticated, api.github.com unreachable) is silent:
/// the last good snapshot survives, the node hides when none ever loaded.
final class GitHubService: ObservableObject {
    static let shared = GitHubService()

    @Published private(set) var pulls: [UUID: [PullRequest]] = [:]
    private var lastPoll: [UUID: Date] = [:]
    private var inFlight: Set<UUID> = []

    static let pollInterval: TimeInterval = 60

    /// Launched from Finder the app inherits launchd's bare PATH, so gh is
    /// resolved against the usual install spots instead of the environment.
    private static let ghPath: String? = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    @MainActor
    func refreshIfStale(_ workspace: Workspace) {
        let now = Date()
        guard Self.ghPath != nil,
              !inFlight.contains(workspace.id),
              now.timeIntervalSince(lastPoll[workspace.id] ?? .distantPast) > Self.pollInterval else { return }
        lastPoll[workspace.id] = now
        inFlight.insert(workspace.id)
        Task.detached(priority: .utility) { [weak self] in
            let parsed = Self.runList(in: workspace.path).flatMap(Self.parsePulls)
            await MainActor.run {
                guard let self else { return }
                self.inFlight.remove(workspace.id)
                if let parsed { self.pulls[workspace.id] = parsed }
            }
        }
    }

    private static func runList(in directory: String) -> Data? {
        guard let gh = ghPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["pr", "list", "--state", "open", "--limit", "20",
                             "--json", "number,title,headRefName,url,statusCheckRollup"]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        // A blocked api.github.com hangs at TCP level for minutes; kill early.
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    static func parsePulls(_ data: Data) -> [PullRequest]? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return list.compactMap { item in
            guard let number = item["number"] as? Int,
                  let title = item["title"] as? String,
                  let branch = item["headRefName"] as? String,
                  let url = (item["url"] as? String).flatMap(URL.init(string:)) else { return nil }
            let rollup = item["statusCheckRollup"] as? [[String: Any]] ?? []
            return PullRequest(number: number, title: title, branch: branch, url: url,
                               checks: checks(fromRollup: rollup))
        }
    }

    /// The rollup mixes CheckRun (status/conclusion) and StatusContext
    /// (state) objects; any failure wins, then anything still running.
    static func checks(fromRollup rollup: [[String: Any]]) -> PullRequest.Checks {
        guard !rollup.isEmpty else { return .none }
        var pending = false
        for item in rollup {
            let verdict = (item["conclusion"] as? String ?? item["state"] as? String ?? "").uppercased()
            let status = (item["status"] as? String ?? "").uppercased()
            if ["FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE"].contains(verdict) { return .failing }
            if verdict.isEmpty || ["PENDING", "EXPECTED"].contains(verdict)
                || ["IN_PROGRESS", "QUEUED", "PENDING", "WAITING"].contains(status) { pending = true }
        }
        return pending ? .pending : .passing
    }

    /// Badges a PR with the member whose worktree branch matches.
    static func owner(of branch: String, among sessions: [TerminalSession]) -> TerminalSession? {
        sessions.first { $0.worktreeBranch == branch }
    }
}
