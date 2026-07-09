import SwiftUI

/// Deep-work overlay: one terminal isolated over a dimmed backdrop, framed in
/// its agent tint. The PTY is the same live NSView, reparented from the grid.
struct FocusModeView: View {
    @EnvironmentObject private var store: AppStore
    let session: TerminalSession

    var body: some View {
        ZStack {
            // ponytail: in-window blur of the live grid; swap to flat ink if it ever measures hot
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(OrkTheme.ink.opacity(0.55))
                .ignoresSafeArea()
                .onTapGesture { exitFocus() }
                .transition(.opacity)
            VStack(spacing: 14) {
                header
                terminal
            }
            .padding(28)
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
        .onAppear {
            store.wake(session.id)
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
                .font(OrkFont.display(15))
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
            .buttonStyle(.pressable)
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .help("Exit focus mode (⌘⇧F)")
        }
    }

    private var terminal: some View {
        TerminalSurface(session: session)
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 10)
            .background(OrkTheme.well)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(session.agent.tint.opacity(0.55), lineWidth: 1.5)
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(OrkTheme.well)
                    .shadow(color: session.agent.tint.opacity(0.25), radius: 34)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
            )
    }

    private func exitFocus() {
        withAnimation(OrkMotion.exit) {
            store.focusModeSessionID = nil
        }
    }
}
