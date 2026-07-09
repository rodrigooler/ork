import SwiftUI

struct FlowView: View {
    let workspace: Workspace
    let sessions: [TerminalSession]

    @State private var focusedID: UUID?

    private var focused: TerminalSession? {
        sessions.first { $0.id == focusedID } ?? sessions.first
    }

    private let nodeWidth: CGFloat = 232

    private func nodeY(_ index: Int) -> CGFloat {
        104 + CGFloat(index) * 86
    }

    var body: some View {
        HStack(spacing: 0) {
            topology.frame(width: 320)
            Rectangle().fill(OrkTheme.stroke).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
        }
    }

    private var topology: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TOPOLOGY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(OrkTheme.dim)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        let origin = CGPoint(x: 44 + nodeWidth / 2, y: 64)
                        for (index, session) in sessions.enumerated() {
                            let target = CGPoint(x: 58, y: nodeY(index) + 30)
                            var path = Path()
                            path.move(to: origin)
                            path.addCurve(
                                to: target,
                                control1: CGPoint(x: origin.x, y: (origin.y + target.y) / 2),
                                control2: CGPoint(x: target.x - 36, y: target.y)
                            )
                            context.stroke(path, with: .color(session.agent.tint.opacity(0.45)), lineWidth: 1.5)
                        }
                    }
                    workspaceNode.offset(x: 44, y: 16)
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        sessionNode(session).offset(x: 60, y: nodeY(index))
                    }
                }
                .frame(height: nodeY(sessions.count) + 40, alignment: .topLeading)
            }
        }
    }

    private var workspaceNode: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(OrkTheme.cyan)
            Text(workspace.name)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(OrkTheme.text)
                .lineLimit(1)
            Spacer()
        }
        .padding(12)
        .frame(width: nodeWidth)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(OrkTheme.cyan.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: OrkTheme.cyan.opacity(0.2), radius: 8)
    }

    private func sessionNode(_ session: TerminalSession) -> some View {
        let isFocused = focused?.id == session.id
        return Button {
            focusedID = session.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.agent.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(session.agent.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.agent.name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OrkTheme.text)
                    Text(session.worktreeBranch ?? URL(fileURLWithPath: session.directory).lastPathComponent)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(OrkTheme.dim)
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(session.exited ? OrkTheme.red : OrkTheme.green)
                    .frame(width: 5, height: 5)
            }
            .padding(10)
            .frame(width: nodeWidth, alignment: .leading)
            .background(Color.white.opacity(isFocused ? 0.08 : 0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(session.agent.tint.opacity(isFocused ? 0.7 : 0.25), lineWidth: 1)
            )
            .shadow(color: isFocused ? session.agent.tint.opacity(0.25) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        if let session = focused {
            SessionCard(session: session)
        } else {
            Text("select a node")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(OrkTheme.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
