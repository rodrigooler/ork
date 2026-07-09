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
    @State private var errorMessage: String?

    private var sessions: [TerminalSession] {
        store.sessions.filter { $0.workspaceID == workspace.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OrkTheme.hairline).frame(height: 1)
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
            isGitRepo = await Task.detached { WorktreeService.isGitRepo(path) }.value
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

            if pane == .terminals {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var paneSwitcher: some View {
        HStack(spacing: 2) {
            switcherButton(label: "terminals", symbol: "terminal", isOn: pane == .terminals) { pane = .terminals }
            switcherButton(label: "data", symbol: "cylinder.split.1x2", isOn: pane == .data) { pane = .data }
        }
        .padding(3)
        .background(OrkTheme.well)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(OrkTheme.hairline, lineWidth: 1))
    }

    private var layoutSwitcher: some View {
        HStack(spacing: 2) {
            switcherButton(label: nil, symbol: "square.grid.2x2", isOn: layout == .grid) { layout = .grid }
            switcherButton(label: nil, symbol: "point.3.connected.trianglepath.dotted", isOn: layout == .flow) { layout = .flow }
        }
        .padding(3)
        .background(OrkTheme.well)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(OrkTheme.hairline, lineWidth: 1))
    }

    private func switcherButton(label: String?, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
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
            .background(isOn ? OrkTheme.raised : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var grid: some View {
        let columns = sessions.count <= 1 ? 1 : 2
        return VStack(spacing: 12) {
            ForEach(rows(columns: columns), id: \.first!.id) { row in
                HStack(spacing: 12) {
                    ForEach(row) { session in
                        SessionCard(session: session)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(14)
    }

    // ponytail: no scrolling; 6+ sessions get small cells, revisit when someone actually runs that many
    private func rows(columns: Int) -> [[TerminalSession]] {
        stride(from: 0, to: sessions.count, by: columns).map {
            Array(sessions[$0 ..< min($0 + columns, sessions.count)])
        }
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
        } catch {
            errorMessage = error.localizedDescription
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
