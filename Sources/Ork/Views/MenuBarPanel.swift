import SwiftUI

/// Dropdown behind the menu bar icon: what ork is running right now.
/// Uses system colors because it sits on the system menu material.
struct MenuBarPanel: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow

    private var running: Int {
        store.sessions.filter { !$0.exited }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ork")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(running > 0 ? Color(hex: 0x97B380) : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(running == 1 ? "1 agent running" : "\(running) agents running")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if store.sessions.isEmpty {
                Text("No active sessions.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.sessions) { row($0) }
            }

            if let usage = store.claudeUsage {
                Divider()
                HStack {
                    Text("Claude Code today")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(TokenFormat.compact(usage.today)) tokens")
                        .font(.system(size: 11, design: .monospaced))
                }
            }

            Divider()

            HStack {
                Button("Open ork") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .controlSize(.small)
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 300)
        .task { store.loadUsageIfNeeded() }
    }

    private func row(_ session: TerminalSession) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.exited ? Color(hex: 0xC96A5F) : Color(hex: 0x97B380))
                .frame(width: 5, height: 5)
            Image(systemName: session.agent.symbol)
                .font(.system(size: 10))
                .foregroundStyle(session.agent.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.agent.name)
                    .font(.system(size: 11, weight: .medium))
                Text(context(session))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private func context(_ session: TerminalSession) -> String {
        let name = store.workspace(id: session.workspaceID)?.name ?? "?"
        if let branch = session.worktreeBranch {
            return "\(name) · \(branch)"
        }
        return name
    }
}
