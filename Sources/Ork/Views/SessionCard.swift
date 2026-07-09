import SwiftTerm
import SwiftUI

struct SessionCard: View {
    @EnvironmentObject private var store: AppStore
    let session: TerminalSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OrkTheme.hairline).frame(height: 1)
            ZStack {
                TerminalSurface(session: session)
                if session.exited {
                    exitedOverlay
                }
            }
        }
        .background(OrkTheme.well)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(session.agent.tint.opacity(session.exited ? 0.15 : 0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.exited ? OrkTheme.brick : OrkTheme.moss)
                .frame(width: 6, height: 6)
            Image(systemName: session.agent.symbol)
                .font(.system(size: 11))
                .foregroundStyle(session.agent.tint)
            Text(session.agent.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OrkTheme.cream)
            Text("#\(session.shortID)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OrkTheme.faint)
            if let branch = session.worktreeBranch {
                Chip(text: branch, tint: session.agent.tint)
            }
            Spacer()
            Button {
                store.closeSession(session.id)
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
        return TerminalRegistry.shared.view(for: session) {
            store.markExited(id)
        }
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
