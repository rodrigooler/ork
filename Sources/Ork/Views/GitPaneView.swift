import SwiftUI

/// GitKraken-style history for the workspace repo: commit graph with lanes,
/// branch badges, ork worktree stats, and a diff panel for the selected commit.
struct GitPane: View {
    @EnvironmentObject private var store: AppStore
    let workspace: Workspace

    private enum Selection: Equatable {
        case commit(GitService.Commit)
        case worktree(GitService.Worktree)
    }

    private struct Snapshot {
        var rows: [GitGraph.Row] = []
        var maxLanes = 1
        var branchTips: [String: [String]] = [:]
        var worktrees: [GitService.Worktree] = []
        var worktreeStats: [String: GitService.Stats] = [:]
        var defaultBranch: String?
        var isGit = false
    }

    @State private var snapshot = Snapshot()
    @State private var selection: Selection?
    @State private var files: [GitService.FileChange] = []
    @State private var selectedFile: GitService.FileChange?
    @State private var patch: [PatchLine] = []
    @State private var confirmMerge = false
    @State private var confirmPrune = false
    @State private var actionBusy = false
    @State private var actionResult: (ok: Bool, text: String)?

    private let rowHeight: CGFloat = 26
    private let laneWidth: CGFloat = 13

    var body: some View {
        Group {
            if !snapshot.isGit {
                emptyState("Not a git repository")
            } else if snapshot.rows.isEmpty {
                emptyState("No commits yet")
            } else {
                HSplitView {
                    VStack(spacing: 0) {
                        worktreeStrip
                        Rectangle().fill(OrkTheme.hairline).frame(height: 1)
                        graphList
                    }
                    .frame(minWidth: 420)
                    detail
                        .frame(minWidth: 320)
                }
            }
        }
        .background(OrkTheme.ink)
        .task(id: workspace.id) {
            selection = nil
            files = []
            patch = []
            actionResult = nil
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 20))
                .foregroundStyle(OrkTheme.faint)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(OrkTheme.stone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func reload() async {
        let repo = workspace.path
        let fresh = await Task.detached(priority: .userInitiated) { () -> Snapshot in
            var snap = Snapshot()
            snap.isGit = WorktreeService.isGitRepo(repo)
            guard snap.isGit else { return snap }
            let commits = GitService.log(repo: repo, limit: 200)
            let graph = GitGraph(commits: commits)
            snap.rows = graph.rows
            snap.maxLanes = graph.maxLanes
            snap.branchTips = GitService.branchTips(repo: repo)
            snap.worktrees = GitService.worktrees(repo: repo)
            snap.defaultBranch = GitService.defaultBranch(repo: repo)
            for worktree in snap.worktrees where !worktree.isMain {
                snap.worktreeStats[worktree.path] = GitService.stats(worktree: worktree.path, baseBranch: snap.defaultBranch)
            }
            return snap
        }.value
        snapshot = fresh
    }

    private func select(_ commit: GitService.Commit) {
        selection = .commit(commit)
        files = []
        selectedFile = nil
        patch = []
        actionResult = nil
        let repo = workspace.path
        Task.detached(priority: .userInitiated) {
            let changed = GitService.changedFiles(repo: repo, sha: commit.sha)
            await MainActor.run {
                guard selection == .commit(commit) else { return }
                files = changed
                if let first = changed.first { selectFile(first) }
            }
        }
    }

    private func select(_ worktree: GitService.Worktree) {
        selection = .worktree(worktree)
        files = []
        selectedFile = nil
        patch = []
        actionResult = nil
        guard let base = snapshot.defaultBranch else { return }
        Task.detached(priority: .userInitiated) {
            let changed = GitService.worktreeDiffFiles(dir: worktree.path, base: base)
            await MainActor.run {
                guard selection == .worktree(worktree) else { return }
                files = changed
                if let first = changed.first { selectFile(first) }
            }
        }
    }

    private func selectFile(_ file: GitService.FileChange) {
        guard let current = selection else { return }
        selectedFile = file
        patch = []
        let repo = workspace.path
        let base = snapshot.defaultBranch ?? "HEAD"
        Task.detached(priority: .userInitiated) {
            let text: String
            switch current {
            case .commit(let commit):
                text = GitService.patch(repo: repo, sha: commit.sha, file: file.path)
            case .worktree(let worktree):
                text = GitService.worktreeDiffPatch(dir: worktree.path, base: base, file: file.path)
            }
            let lines = PatchLine.parse(text)
            await MainActor.run {
                guard selection == current, selectedFile?.path == file.path else { return }
                patch = lines
            }
        }
    }

    // MARK: - Janitor actions

    private func hasLiveSession(_ worktree: GitService.Worktree) -> Bool {
        store.sessions.contains { !$0.exited && $0.directory == worktree.path }
    }

    private func merge(_ worktree: GitService.Worktree) {
        actionBusy = true
        actionResult = nil
        let repo = workspace.path
        let base = snapshot.defaultBranch ?? "base"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                GitService.merge(repo: repo, branch: worktree.branch)
            }.value
            actionBusy = false
            actionResult = result.ok
                ? (true, "Merged into \(base).")
                : (false, String(result.output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300)))
            await reload()
        }
    }

    private func prune(_ worktree: GitService.Worktree) {
        actionBusy = true
        actionResult = nil
        let repo = workspace.path
        Task {
            await Task.detached(priority: .userInitiated) {
                WorktreeService.remove(repo: repo, worktreePath: worktree.path, branch: worktree.branch)
            }.value
            actionBusy = false
            selection = nil
            files = []
            patch = []
            await reload()
        }
    }

    // MARK: - Worktree strip

    private var worktreeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(snapshot.worktrees.filter { !$0.isMain }, id: \.path) { worktree in
                    let stats = snapshot.worktreeStats[worktree.path] ?? GitService.Stats()
                    Button {
                        select(worktree)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                                .foregroundStyle(branchTint(worktree.branch))
                            Text(worktree.branch)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(OrkTheme.cream)
                            statsLabel(stats)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .orkCard(radius: 7, fill: selection == .worktree(worktree) ? OrkTheme.overlay : OrkTheme.raised)
                    }
                    .buttonStyle(.plain)
                    .help(worktree.path)
                }
                if snapshot.worktrees.count <= 1 {
                    Text("No ork worktrees yet")
                        .font(.system(size: 10.5))
                        .foregroundStyle(OrkTheme.faint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func statsLabel(_ stats: GitService.Stats) -> some View {
        HStack(spacing: 4) {
            if stats.isClean && stats.ahead == 0 {
                Text("clean").foregroundStyle(OrkTheme.faint)
            } else {
                if stats.insertions > 0 || stats.deletions > 0 {
                    Text("+\(stats.insertions)").foregroundStyle(OrkTheme.moss)
                    Text("−\(stats.deletions)").foregroundStyle(OrkTheme.brick)
                }
                if stats.newFiles > 0 {
                    Text("\(stats.newFiles) new").foregroundStyle(OrkTheme.stone)
                }
                if stats.ahead > 0 {
                    Text("↑\(stats.ahead)").foregroundStyle(OrkTheme.clay)
                }
            }
        }
        .font(.system(size: 9.5, design: .monospaced))
    }

    // MARK: - Graph

    private var graphWidth: CGFloat {
        laneWidth * CGFloat(min(snapshot.maxLanes, 10)) + laneWidth / 2
    }

    private var graphList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(snapshot.rows) { row in
                    graphRow(row)
                        .contentShape(Rectangle())
                        .onTapGesture { select(row.commit) }
                }
            }
        }
    }

    private static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func graphRow(_ row: GitGraph.Row) -> some View {
        let isSelected = selection == .commit(row.commit)
        let branches = snapshot.branchTips[row.commit.sha] ?? []
        let worktreeBranches = Set(snapshot.worktrees.filter { !$0.isMain }.map(\.branch))
        return HStack(spacing: 8) {
            GraphRowCanvas(row: row, laneWidth: laneWidth, width: graphWidth)
                .frame(width: graphWidth, height: rowHeight)
            ForEach(branches, id: \.self) { branch in
                HStack(spacing: 3) {
                    if worktreeBranches.contains(branch) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 7.5))
                    }
                    Text(branch)
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(branchTint(branch))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(branchTint(branch).opacity(0.14), in: Capsule())
            }
            Text(row.commit.subject)
                .font(.system(size: 11.5))
                .foregroundStyle(isSelected ? OrkTheme.cream : OrkTheme.stone)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(Self.relativeDate.localizedString(for: row.commit.date, relativeTo: Date()))
                .font(.system(size: 9.5))
                .foregroundStyle(OrkTheme.faint)
            Text(row.commit.shortSHA)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(OrkTheme.faint)
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .background(isSelected ? OrkTheme.overlay : .clear)
    }

    private func branchTint(_ branch: String) -> Color {
        if branch.hasPrefix("ork/") {
            let slug = branch.dropFirst(4).split(separator: "-").first.map(String.init) ?? ""
            if let agent = AgentProfile.all.first(where: { $0.slug == slug }) {
                return agent.tint
            }
        }
        if branch == snapshot.defaultBranch { return OrkTheme.clay }
        return OrkTheme.stone
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        switch selection {
        case .commit(let commit):
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.subject)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OrkTheme.cream)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(commit.shortSHA).font(.system(size: 10, design: .monospaced))
                        Text(commit.author).font(.system(size: 10))
                        Text(commit.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10))
                    }
                    .foregroundStyle(OrkTheme.faint)
                }
                .padding(12)
                fileListAndPatch
            }
        case .worktree(let worktree):
            worktreeDetail(worktree)
        case nil:
            emptyState("Select a commit or a worktree")
        }
    }

    @ViewBuilder private var fileListAndPatch: some View {
        Rectangle().fill(OrkTheme.hairline).frame(height: 1)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(files) { file in
                    fileRow(file)
                }
            }
            .padding(6)
        }
        .frame(maxHeight: 150)
        Rectangle().fill(OrkTheme.hairline).frame(height: 1)
        patchView
    }

    private func worktreeDetail(_ worktree: GitService.Worktree) -> some View {
        let base = snapshot.defaultBranch
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundStyle(branchTint(worktree.branch))
                    Text(worktree.branch)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OrkTheme.cream)
                    if hasLiveSession(worktree) {
                        Text("live session")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(OrkTheme.moss)
                    }
                }
                Text(worktree.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OrkTheme.faint)
                    .lineLimit(1)
                    .truncationMode(.head)
                HStack(spacing: 8) {
                    Button("Merge into \(base ?? "?")") { confirmMerge = true }
                        .disabled(base == nil || actionBusy)
                    Button("Prune", role: .destructive) { confirmPrune = true }
                        .disabled(hasLiveSession(worktree) || actionBusy)
                        .help(hasLiveSession(worktree)
                            ? "A session is still running in this worktree"
                            : "Remove the worktree and delete its branch")
                    if actionBusy { ProgressView().controlSize(.small) }
                }
                .controlSize(.small)
                if let actionResult {
                    Text(actionResult.text)
                        .font(.system(size: 10))
                        .foregroundStyle(actionResult.ok ? OrkTheme.moss : OrkTheme.brick)
                        .textSelection(.enabled)
                }
                Text("Diff vs \(base ?? "?"), committed and uncommitted")
                    .font(.system(size: 9.5))
                    .foregroundStyle(OrkTheme.faint)
            }
            .padding(12)
            fileListAndPatch
        }
        .alert("Merge \(worktree.branch) into \(base ?? "?")?", isPresented: $confirmMerge) {
            Button("Merge") { merge(worktree) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Runs git merge --no-ff in the main worktree. On conflict the merge aborts and the repo stays clean.")
        }
        .alert("Prune \(worktree.branch)?", isPresented: $confirmPrune) {
            Button("Prune", role: .destructive) { prune(worktree) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the worktree directory and deletes the branch. Unmerged work is lost.")
        }
    }

    private func fileRow(_ file: GitService.FileChange) -> some View {
        Button {
            selectFile(file)
        } label: {
            HStack(spacing: 6) {
                Text(file.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(selectedFile?.path == file.path ? OrkTheme.cream : OrkTheme.stone)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 8)
                Text("+\(file.insertions)").foregroundStyle(OrkTheme.moss)
                Text("−\(file.deletions)").foregroundStyle(OrkTheme.brick)
            }
            .font(.system(size: 9.5, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selectedFile?.path == file.path ? OrkTheme.overlay : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private var patchView: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(patch.indices, id: \.self) { index in
                    let line = patch[index]
                    Text(line.text)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(line.kind.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(line.kind.background)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
    }
}

/// One row of the commit graph: pass-through lanes, converging edges, the
/// dot, and edges down to parents. Colors follow the lane index.
private struct GraphRowCanvas: View {
    let row: GitGraph.Row
    let laneWidth: CGFloat
    let width: CGFloat

    private static let palette: [Color] = [
        Color(hex: 0xF96B2F), Color(hex: 0x7FA3C4), Color(hex: 0x97B380), Color(hex: 0xA08FC9),
        Color(hex: 0xC7A566), Color(hex: 0xC96A5F), Color(hex: 0x6FBFB2), Color(hex: 0xB58CC9),
    ]

    private func laneColor(_ lane: Int) -> Color {
        Self.palette[lane % Self.palette.count]
    }

    var body: some View {
        Canvas { context, size in
            func x(_ lane: Int) -> CGFloat { laneWidth * CGFloat(lane) + laneWidth / 2 }
            let midY = size.height / 2

            for lane in row.through where x(lane) < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x(lane), y: 0))
                path.addLine(to: CGPoint(x: x(lane), y: size.height))
                context.stroke(path, with: .color(laneColor(lane)), lineWidth: 1.5)
            }
            for lane in row.incoming where x(lane) < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x(lane), y: 0))
                if lane == row.column {
                    path.addLine(to: CGPoint(x: x(lane), y: midY))
                } else {
                    path.addQuadCurve(
                        to: CGPoint(x: x(row.column), y: midY),
                        control: CGPoint(x: x(lane), y: midY)
                    )
                }
                context.stroke(path, with: .color(laneColor(lane)), lineWidth: 1.5)
            }
            for lane in row.outgoing where x(lane) < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x(row.column), y: midY))
                if lane == row.column {
                    path.addLine(to: CGPoint(x: x(lane), y: size.height))
                } else {
                    path.addQuadCurve(
                        to: CGPoint(x: x(lane), y: size.height),
                        control: CGPoint(x: x(lane), y: midY)
                    )
                }
                context.stroke(path, with: .color(laneColor(lane)), lineWidth: 1.5)
            }
            let dot = CGRect(x: x(row.column) - 4, y: midY - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dot), with: .color(laneColor(row.column)))
        }
    }
}

/// A parsed diff line with its render style.
struct PatchLine {
    enum Kind {
        case addition, deletion, hunk, meta, context

        var color: Color {
            switch self {
            case .addition: return OrkTheme.moss
            case .deletion: return OrkTheme.brick
            case .hunk: return OrkTheme.clay
            case .meta: return OrkTheme.faint
            case .context: return OrkTheme.stone
            }
        }

        var background: Color {
            switch self {
            case .addition: return OrkTheme.moss.opacity(0.08)
            case .deletion: return OrkTheme.brick.opacity(0.08)
            default: return .clear
            }
        }
    }

    let text: String
    let kind: Kind

    static func parse(_ patch: String, limit: Int = 3000) -> [PatchLine] {
        var lines: [PatchLine] = []
        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if lines.count >= limit {
                lines.append(PatchLine(text: "… diff truncated at \(limit) lines", kind: .meta))
                break
            }
            let text = String(raw)
            let kind: Kind
            if text.hasPrefix("+++") || text.hasPrefix("---") || text.hasPrefix("diff ") || text.hasPrefix("index ") {
                kind = .meta
            } else if text.hasPrefix("@@") {
                kind = .hunk
            } else if text.hasPrefix("+") {
                kind = .addition
            } else if text.hasPrefix("-") {
                kind = .deletion
            } else {
                kind = .context
            }
            lines.append(PatchLine(text: text.isEmpty ? " " : text, kind: kind))
        }
        return lines
    }
}
