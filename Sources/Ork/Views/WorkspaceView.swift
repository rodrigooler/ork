import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    let workspace: Workspace

    enum LayoutMode: String, CaseIterable { case grid, flow }

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
            Rectangle().fill(OrkTheme.stroke).frame(height: 1)
            if sessions.isEmpty {
                emptyState
            } else if layout == .grid {
                grid
            } else {
                FlowView(workspace: workspace, sessions: sessions)
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

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(workspace.name)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(OrkTheme.text)
                    if isGitRepo {
                        Chip(text: "git", tint: OrkTheme.green)
                    }
                }
                Text(workspace.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OrkTheme.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

            Picker("Layout", selection: $layout) {
                Image(systemName: "square.grid.2x2").tag(LayoutMode.grid)
                Image(systemName: "point.3.connected.trianglepath.dotted").tag(LayoutMode.flow)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 96)

            Toggle(isOn: $useWorktree) {
                Label("worktree", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11, design: .monospaced))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
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
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .buttonStyle(.borderedProminent)
            .tint(OrkTheme.cyan.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

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
        .padding(12)
    }

    // ponytail: no scrolling; 6+ sessions get small cells, revisit when someone actually runs that many
    private func rows(columns: Int) -> [[TerminalSession]] {
        stride(from: 0, to: sessions.count, by: columns).map {
            Array(sessions[$0 ..< min($0 + columns, sessions.count)])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(OrkTheme.cyan.opacity(0.6))
            Text("no active sessions")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(OrkTheme.text)
            Text("Spawn an agent to start orchestrating this workspace.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(OrkTheme.dim)
            HStack(spacing: 8) {
                ForEach(AgentProfile.builtin) { agent in
                    Button {
                        spawn(agent)
                    } label: {
                        Label(agent.name, systemImage: agent.symbol)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .tint(agent.tint)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                .foregroundStyle(OrkTheme.stroke)
                .padding(12)
        )
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
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }
}
