import SwiftUI

/// Deep-work overlay: one terminal isolated over a dimmed backdrop, framed in
/// its agent tint. The PTY is the same live NSView, reparented from the grid.
struct FocusModeView: View {
    @EnvironmentObject private var store: AppStore
    let session: TerminalSession

    var body: some View {
        ZStack {
            OrkTheme.ink.opacity(0.985)
                .ignoresSafeArea()
                .onTapGesture { exitFocus() }
            VStack(spacing: 14) {
                header
                terminal
            }
            .padding(28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                TerminalRegistry.shared.focusTerminal(session.id)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PulsingDot(
                color: session.exited ? OrkTheme.brick : OrkTheme.moss,
                size: 7,
                active: !session.exited
            )
            Text(session.agent.name)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(OrkTheme.cream)
            if let branch = session.worktreeBranch {
                Chip(text: branch, tint: session.agent.tint)
            }
            if let workspace = store.workspace(id: session.workspaceID) {
                Text(workspace.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(OrkTheme.stone)
            }
            Spacer()
            Text("deep work · click outside to leave")
                .font(.system(size: 10))
                .foregroundStyle(OrkTheme.faint)
            Button {
                exitFocus()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OrkTheme.stone)
                    .frame(width: 28, height: 28)
                    .background(OrkTheme.overlay)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .help("Exit focus mode (⌘⇧F)")
        }
    }

    private var terminal: some View {
        TerminalSurface(session: session)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(session.agent.tint.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(color: session.agent.tint.opacity(0.25), radius: 34)
            .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
    }

    private func exitFocus() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            store.focusModeSessionID = nil
        }
    }
}
