import SwiftTerm
import SwiftUI

struct SessionCard: View {
    @EnvironmentObject private var store: AppStore
    let session: TerminalSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OrkTheme.stroke).frame(height: 1)
            ZStack {
                TerminalSurface(session: session)
                if session.exited {
                    exitedOverlay
                }
            }
        }
        .background(Color(.sRGB, red: 0.016, green: 0.024, blue: 0.047, opacity: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(session.agent.tint.opacity(session.exited ? 0.25 : 0.5), lineWidth: 1)
        )
        .shadow(color: session.agent.tint.opacity(0.15), radius: 14, y: 2)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.exited ? OrkTheme.red : OrkTheme.green)
                .frame(width: 6, height: 6)
                .shadow(color: session.exited ? OrkTheme.red : OrkTheme.green, radius: 3)
            Image(systemName: session.agent.symbol)
                .font(.system(size: 11))
                .foregroundStyle(session.agent.tint)
            Text(session.agent.name)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(OrkTheme.text)
            Text("#\(session.shortID)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OrkTheme.dim)
            if let branch = session.worktreeBranch {
                Chip(text: branch, tint: session.agent.tint)
            }
            Spacer()
            Button {
                store.closeSession(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(OrkTheme.dim)
            }
            .buttonStyle(.plain)
            .help("Close session")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.03))
    }

    private var exitedOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                Text("process exited")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OrkTheme.dim)
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
