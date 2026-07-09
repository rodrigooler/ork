import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    let workspace: Workspace

    enum LayoutMode { case grid, flow }
    enum Pane { case terminals, data }

    @State private var pane: Pane = .terminals
    @State private var layout: LayoutMode = .grid
    @State private var useWorktree = true
    @State private var isGitRepo = false
    @State private var worktreeCount = 0
    @State private var errorMessage: String?
    @Namespace private var paneNamespace
    @Namespace private var layoutNamespace

    private var sessions: [TerminalSession] {
        store.sessions.filter { $0.workspaceID == workspace.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            headerDivider
            switch pane {
            case .terminals:
                if sessions.isEmpty {
                    emptyState
                } else if layout == .grid {
                    grid
                } else {
                    FlowView(workspace: workspace, sessions: sessions)
                }
            case .data:
                DataPane(workspace: workspace)
            }
        }
        .task(id: workspace.id) {
            let path = workspace.path
            let (isGit, wtCount) = await Task.detached {
                let git = WorktreeService.isGitRepo(path)
                let count = git ? WorktreeService.orkWorktreeCount(path) : 0
                return (git, count)
            }.value
            isGitRepo = isGit
            worktreeCount = wtCount
        }
        .alert(
            "Session failed",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(workspace.name)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundStyle(OrkTheme.cream)
                    if isGitRepo {
                        Chip(text: "git", tint: OrkTheme.moss)
                        if worktreeCount > 0 {
                            Chip(text: "\(worktreeCount) worktree\(worktreeCount == 1 ? "" : "s")", tint: OrkTheme.stone)
                        }
                    }
                }
                Text(workspace.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OrkTheme.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

            paneSwitcher

            // Ghosted instead of removed so switching panes never reflows the header.
            HStack(spacing: 14) {
                layoutSwitcher

                Toggle(isOn: $useWorktree) {
                    Label("worktree", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundStyle(OrkTheme.stone)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(OrkTheme.clay)
                .disabled(!isGitRepo)
                .help(isGitRepo ? "Run each session in an isolated git worktree" : "Not a git repository")

                Menu {
                    ForEach(AgentProfile.builtin) { agent in
                        Button {
                            spawn(agent)
                        } label: {
                            Label(agent.name, systemImage: agent.symbol)
                        }
                    }
                } label: {
                    Label("session", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(OrkTheme.clay)
            }
            .opacity(pane == .terminals ? 1 : 0)
            .allowsHitTesting(pane == .terminals)
            .animation(.easeOut(duration: 0.12), value: pane)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// While agents run, the divider becomes the animated agent-tint rail.
    @ViewBuilder private var headerDivider: some View {
        if sessions.contains(where: { !$0.exited }) {
            AnimatedRail(height: 1.5).opacity(0.75)
        } else {
            Rectangle().fill(OrkTheme.hairline).frame(height: 1)
        }
    }

    private var paneSwitcher: some View {
        HStack(spacing: 2) {
            switcherButton(label: "terminals", symbol: "terminal", isOn: pane == .terminals, ns: paneNamespace) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pane = .terminals }
            }
            switcherButton(label: "data", symbol: "cylinder.split.1x2", isOn: pane == .data, ns: paneNamespace) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pane = .data }
            }
        }
        .padding(3)
        .background(OrkTheme.well)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(OrkTheme.hairline, lineWidth: 1))
    }

    private var layoutSwitcher: some View {
        HStack(spacing: 2) {
            switcherButton(label: nil, symbol: "square.grid.2x2", isOn: layout == .grid, ns: layoutNamespace) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { layout = .grid }
            }
            switcherButton(label: nil, symbol: "point.3.connected.trianglepath.dotted", isOn: layout == .flow, ns: layoutNamespace) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { layout = .flow }
            }
        }
        .padding(3)
        .background(OrkTheme.well)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(OrkTheme.hairline, lineWidth: 1))
    }

    private func switcherButton(
        label: String?,
        symbol: String,
        isOn: Bool,
        ns: Namespace.ID,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                if let label {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(isOn ? OrkTheme.cream : OrkTheme.stone)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(OrkTheme.raised)
                        .matchedGeometryEffect(id: "selection", in: ns)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    // One flat ForEach keyed by session id: closing a card never re-keys the
    // survivors, so their PTY views move instead of remounting.
    // ponytail: no scrolling; 6+ sessions get small cells, revisit when someone actually runs that many
    private var grid: some View {
        GeometryReader { geo in
            let columns = sessions.count <= 1 ? 1 : 2
            let rowCount = max(1, (sessions.count + columns - 1) / columns)
            let spacing: CGFloat = 12
            let cellHeight = (geo.size.height - spacing * CGFloat(rowCount - 1)) / CGFloat(rowCount)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                ForEach(sessions) { session in
                    SessionCard(session: session)
                        .frame(height: cellHeight)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
        }
        .padding(14)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sessions.map(\.id))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(OrkTheme.faint)
            Text("No active sessions")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(OrkTheme.cream)
            Text("Spawn an agent to start working on this project.")
                .font(.system(size: 12))
                .foregroundStyle(OrkTheme.stone)
            HStack(spacing: 8) {
                ForEach(AgentProfile.builtin) { agent in
                    Button {
                        spawn(agent)
                    } label: {
                        Label(agent.name, systemImage: agent.symbol)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .tint(agent.tint)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func spawn(_ agent: AgentProfile) {
        do {
            try store.newSession(agent: agent, in: workspace, useWorktree: useWorktree && isGitRepo)
            refreshWorktreeCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshWorktreeCount() {
        let path = workspace.path
        Task {
            let count = await Task.detached { WorktreeService.orkWorktreeCount(path) }.value
            worktreeCount = count
        }
    }
}

struct Chip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }
}
