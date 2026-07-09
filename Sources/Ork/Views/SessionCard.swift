import SwiftTerm
import SwiftUI

struct SessionCard: View {
    @EnvironmentObject private var store: AppStore
    let session: TerminalSession

    @State private var showCloseConfirm = false

    private var isFocused: Bool {
        store.focusedSessionID == session.id && !session.exited
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
                }
                if session.exited {
                    exitedOverlay
                }
            }
        }
        .background(OrkTheme.well)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    session.agent.tint.opacity(session.exited ? 0.15 : (isFocused ? 0.85 : 0.28)),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if session.exited {
                Circle().fill(OrkTheme.brick).frame(width: 6, height: 6)
            } else {
                PulsingDot(color: OrkTheme.moss, size: 6)
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
            }
            Spacer()
            if isFocused {
                Text("focused")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(session.agent.tint)
            }
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    store.focusModeSessionID = session.id
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(OrkTheme.stone)
            }
            .buttonStyle(.plain)
            .help("Focus mode: isolate this terminal")
            Button {
                if session.worktreeBranch != nil && !session.exited {
                    showCloseConfirm = true
                } else {
                    store.closeSession(session.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(OrkTheme.stone)
            }
            .buttonStyle(.plain)
            .help("Close session")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(OrkTheme.raised)
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

    private var exitedOverlay: some View {
        ZStack {
            OrkTheme.ink.opacity(0.72)
            VStack(spacing: 10) {
                Text("Process exited")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OrkTheme.stone)
                Button("Close card") {
                    store.closeSession(session.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

struct TerminalSurface: NSViewRepresentable {
    @EnvironmentObject private var store: AppStore
    let session: TerminalSession

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let store = store
        let id = session.id
        return TerminalRegistry.shared.view(
            for: session,
            onExit: { store.markExited(id) },
            onFocus: { focused in store.setFocus(id, focused: focused) }
        )
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        TerminalRegistry.shared.observeWindowIfNeeded(nsView.window)
    }
}
