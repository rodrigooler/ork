import SwiftUI

/// Shared glance content: window stats up top, per-agent usage with an inline
/// chart, live sessions, quick actions. Used by the menu bar dropdown and the
/// notch overlay. Shows token volume for the 5h/7d windows; plan rate-limit
/// percentages are only visible to the agent CLIs themselves, so ork does not
/// guess them.
struct PanelContent: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var settings = OrkSettings.shared
    let openAction: () -> Void

    /// Privacy mode narrows everything to the selected project's organization.
    private var visibleSessions: [TerminalSession] {
        store.sessions.filter { store.isWorkspaceVisible($0.workspaceID) }
    }

    private var running: Int {
        visibleSessions.filter { !$0.exited }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            divider
            usageSection
            divider
            sessionsSection
            divider
            footer
        }
        .task { store.loadUsageIfNeeded() }
    }

    private var divider: some View {
        Rectangle().fill(OrkTheme.hairline).frame(height: 1)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(running > 0 ? OrkTheme.moss : OrkTheme.faint)
                    .frame(width: 6, height: 6)
                Text(running == 1 ? "1 session" : "\(running) sessions")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(OrkMotion.state, value: running)
                    .foregroundStyle(OrkTheme.cream)
            }
            Spacer()
            if let usage = store.claudeUsage {
                Text("5H \(TokenFormat.compact(usage.last5h)) · 7D \(TokenFormat.compact(usage.last7d))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OrkTheme.stone)
            }
        }
    }

    @ViewBuilder private var usageSection: some View {
        if let usage = store.claudeUsage {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(OrkTheme.clay)
                    Text("Claude Code")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OrkTheme.cream)
                    Text("\(TokenFormat.compact(usage.total)) · 14d")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OrkTheme.stone)
                    Spacer()
                    Text("today \(TokenFormat.compact(usage.today))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OrkTheme.stone)
                }
                UsageBars(days: usage.days, tint: OrkTheme.clay, height: 34)
            }
        } else if store.usageScanned {
            Text("No Claude Code usage found.")
                .font(.system(size: 11))
                .foregroundStyle(OrkTheme.stone)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning usage…")
                    .font(.system(size: 11))
                    .foregroundStyle(OrkTheme.stone)
            }
        }
    }

    @ViewBuilder private var sessionsSection: some View {
        if visibleSessions.isEmpty {
            Text("No active sessions.")
                .font(.system(size: 11))
                .foregroundStyle(OrkTheme.stone)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(visibleSessions) { row($0) }
            }
        }
    }

    private func row(_ session: TerminalSession) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.exited ? OrkTheme.brick : OrkTheme.moss)
                .frame(width: 5, height: 5)
            Image(systemName: session.agent.symbol)
                .font(.system(size: 10))
                .foregroundStyle(session.agent.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.agent.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(OrkTheme.cream)
                Text(context(session))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(OrkTheme.stone)
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

    private var footer: some View {
        HStack {
            Button("Open ork", action: openAction)
                .controlSize(.small)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
    }
}

struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PanelContent {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .padding(14)
        .frame(width: 340)
        .background(OrkTheme.ink)
        .preferredColorScheme(.dark)
    }
}
