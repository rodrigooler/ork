import SwiftTerm
import SwiftUI

struct SessionCard: View {
    @EnvironmentObject private var store: AppStore
    let session: TerminalSession

    @State private var showCloseConfirm = false

    private var isFocused: Bool {
        store.focusedSessionID == session.id && !session.exited
    }

    private var isFrozen: Bool {
        store.frozenSessionIDs.contains(session.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OrkTheme.hairline).frame(height: 1)
            ZStack {
                if store.focusModeSessionID == session.id {
                    inFocusPlaceholder
                } else {
                    TerminalSurface(session: session)
                        .padding(.leading, 10)
                        .padding(.trailing, 4)
                        .padding(.vertical, 8)
                }
                if session.exited {
                    exitedOverlay
                } else if isFrozen {
                    frozenOverlay
                }
            }
        }
        .background(OrkTheme.well)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            // Agent identity lives in the frame: tint pours in from the top edge.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            session.agent.tint.opacity(session.exited ? 0.18 : (isFocused ? 0.9 : 0.55)),
                            session.agent.tint.opacity(session.exited ? 0.06 : 0.12),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .background(
            // Shadows live on a static shape so terminal redraws never re-rasterize them.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(OrkTheme.well)
                .shadow(color: .black.opacity(0.32), radius: 14, y: 5)
                .shadow(color: session.agent.tint.opacity(isFocused && !session.exited ? 0.2 : 0), radius: 22)
        )
        .animation(OrkMotion.hover, value: isFocused)
        .animation(OrkMotion.layout, value: session.exited)
        .animation(OrkMotion.state, value: isFrozen)
    }

    /// Idle session parked with SIGSTOP: content stays readable behind a
    /// light veil; any click resumes the process instantly.
    private var frozenOverlay: some View {
        ZStack {
            OrkTheme.ink.opacity(0.45)
            HStack(spacing: 6) {
                Image(systemName: "snowflake")
                    .font(.system(size: 10, weight: .medium))
                Text("Sleeping · click to wake")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(OrkTheme.cream)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(OrkMotion.state) { store.wake(session.id) }
        }
        .transition(.opacity)
    }

    /// Uncommitted diff and commits ahead of base, from AppStore's 10 s poll.
    @ViewBuilder private var statsChips: some View {
        if let stats = store.sessionStats[session.id] {
            HStack(spacing: 4) {
                if !stats.isClean {
                    Text("+\(stats.insertions)").foregroundStyle(OrkTheme.moss)
                    Text("−\(stats.deletions)").foregroundStyle(OrkTheme.brick)
                }
                if stats.ahead > 0 {
                    Text("↑\(stats.ahead)").foregroundStyle(OrkTheme.clay)
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .help("Uncommitted: +\(stats.insertions) −\(stats.deletions), \(stats.newFiles) new files · \(stats.ahead) commits ahead of base")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if session.exited {
                Circle().fill(OrkTheme.brick).frame(width: 6, height: 6)
            } else {
                PulsingDot(color: isFrozen ? OrkTheme.faint : OrkTheme.moss, size: 6, active: !isFrozen)
            }
            Image(systemName: session.agent.symbol)
                .font(.system(size: 11))
                .foregroundStyle(session.agent.tint)
            Text(session.agent.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFocused ? OrkTheme.cream : OrkTheme.stone)
            Text("#\(session.shortID)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OrkTheme.faint)
            if let branch = session.worktreeBranch {
                Chip(text: branch, tint: session.agent.tint)
                    .help("Worktree: \(session.directory)")
                statsChips
            }
            Spacer()
            if isFocused {
                Text("focused")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(session.agent.tint)
            }
            Button {
                withAnimation(OrkMotion.overlay) {
                    store.focusModeSessionID = session.id
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(OrkTheme.stone)
            }
            .buttonStyle(.pressable)
            .help("Focus mode: isolate this terminal")
            Button {
                if session.worktreeBranch != nil && !session.exited && OrkSettings.shared.confirmCloseRunning {
                    showCloseConfirm = true
                } else {
                    store.closeSession(session.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(OrkTheme.stone)
            }
            .buttonStyle(.pressable)
            .help("Close session")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            ZStack {
                OrkTheme.raised
                LinearGradient(
                    colors: [session.agent.tint.opacity(0.09), .clear],
                    startPoint: .leading,
                    endPoint: UnitPoint(x: 0.6, y: 0.5)
                )
            }
        )
        .alert("Close \(session.agent.name)?", isPresented: $showCloseConfirm) {
            Button("Remove worktree", role: .destructive) {
                store.closeSessionAndRemoveWorktree(session.id)
            }
            Button("Keep worktree") {
                store.closeSession(session.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Branch \(session.worktreeBranch ?? "") and its worktree directory will be permanently removed if you choose \"Remove worktree\".")
        }
    }

    private var inFocusPlaceholder: some View {
        ZStack {
            OrkTheme.well
            VStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 18))
                    .foregroundStyle(session.agent.tint.opacity(0.8))
                Text("In focus mode")
                    .font(.system(size: 11))
                    .foregroundStyle(OrkTheme.stone)
            }
        }
    }

    // Frosts the dead terminal instead of hiding it: the last output stays
    // faintly readable behind the glass.
    private var exitedOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            OrkTheme.ink.opacity(0.45)
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(OrkTheme.brick).frame(width: 6, height: 6)
                    Text("Process exited")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OrkTheme.cream)
                }
                Button("Close card") {
                    store.closeSession(session.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .transition(.opacity)
    }
}

struct TerminalSurface: NSViewRepresentable {
    @EnvironmentObject private var store: AppStore
    let session: TerminalSession

    func makeNSView(context: Context) -> TerminalDropContainer {
        let store = store
        let id = session.id
        let terminal = TerminalRegistry.shared.view(
            for: session,
            resume: store.restoredSessionIDs.contains(session.id),
            onExit: { store.markExited(id) },
            onFocus: { focused in store.setFocus(id, focused: focused) }
        )
        return TerminalDropContainer(terminal: terminal)
    }

    func updateNSView(_ nsView: TerminalDropContainer, context: Context) {
        TerminalRegistry.shared.observeWindowIfNeeded(nsView.window)
    }
}
