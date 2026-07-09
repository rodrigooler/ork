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
                        .background(DotGrid())
                } else if layout == .grid {
                    grid
                        .background(DotGrid().opacity(0.55))
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
        HStack(spacing: 12) {
            SidebarToggleButton()
            HStack(spacing: 7) {
                Text(workspace.name)
                    .font(OrkFont.display(12.5))
                    .foregroundStyle(OrkTheme.cream)
                    .help(workspace.path)
                if isGitRepo {
                    Chip(text: "git", tint: OrkTheme.moss)
                    if worktreeCount > 0 {
                        Chip(text: "\(worktreeCount) wt", tint: OrkTheme.stone)
                    }
                }
            }
            Spacer()

            paneSwitcher

            HStack(spacing: 12) {
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
            .animation(OrkMotion.hover, value: pane)
        }
        .padding(.leading, store.sidebarHidden ? 74 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
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
                withAnimation(OrkMotion.state) { pane = .terminals }
            }
            switcherButton(label: "data", symbol: "cylinder.split.1x2", isOn: pane == .data, ns: paneNamespace) {
                withAnimation(OrkMotion.state) { pane = .data }
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
                withAnimation(OrkMotion.state) { layout = .grid }
            }
            switcherButton(label: nil, symbol: "point.3.connected.trianglepath.dotted", isOn: layout == .flow, ns: layoutNamespace) {
                withAnimation(OrkMotion.state) { layout = .flow }
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
        .animation(OrkMotion.layout, value: sessions.map(\.id))
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(OrkTheme.faint)
                Text("No active sessions")
                    .font(OrkFont.display(14))
                    .foregroundStyle(OrkTheme.cream)
                Text("Spawn an agent to start working on this project.")
                    .font(.system(size: 12))
                    .foregroundStyle(OrkTheme.stone)
            }
            .riseIn()
            HStack(spacing: 10) {
                ForEach(Array(AgentProfile.builtin.enumerated()), id: \.element.id) { index, agent in
                    AgentTile(agent: agent, delay: 0.05 + Double(index) * 0.04) {
                        spawn(agent)
                    }
                }
            }
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

/// Launcher tile for one agent CLI: tinted icon well, name, command hint.
struct AgentTile: View {
    let agent: AgentProfile
    var delay: Double = 0
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Group {
                    if let icon = OrkMark.agentIcon(slug: agent.slug) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: agent.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(agent.tint)
                            .frame(width: 44, height: 44)
                            .background(agent.tint.opacity(hovering ? 0.2 : 0.12))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hovering ? OrkTheme.cream : OrkTheme.stone)
                    Text(agent.command)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(OrkTheme.faint)
                }
            }
            .frame(width: 104)
            .padding(.vertical, 14)
            .background(OrkTheme.raised.opacity(hovering ? 1 : 0.78))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? agent.tint.opacity(0.5) : OrkTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .animation(OrkMotion.hover, value: hovering)
        .riseIn(delay: delay)
    }
}
