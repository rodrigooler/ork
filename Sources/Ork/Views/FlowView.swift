import SwiftUI

/// Topology rail: the workspace card feeds a vertical trunk, each agent hangs
/// off it on a horizontal stub with a tinted junction dot. Subway map, not spaghetti.
struct FlowView: View {
    let workspace: Workspace
    let sessions: [TerminalSession]

    @State private var focusedID: UUID?

    private var focused: TerminalSession? {
        sessions.first { $0.id == focusedID } ?? sessions.first
    }

    private let paneWidth: CGFloat = 300
    private let trunkX: CGFloat = 27
    private let nodeHeight: CGFloat = 54
    private let nodeStep: CGFloat = 66
    private let firstNodeY: CGFloat = 78

    private func nodeCenterY(_ index: Int) -> CGFloat {
        firstNodeY + CGFloat(index) * nodeStep + nodeHeight / 2
    }

    var body: some View {
        HStack(spacing: 0) {
            topology.frame(width: paneWidth)
            Rectangle().fill(OrkTheme.hairline).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(14)
        }
    }

    private var topology: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                DotGrid()
                Canvas { context, _ in
                    guard !sessions.isEmpty else { return }
                    var trunk = Path()
                    trunk.move(to: CGPoint(x: trunkX, y: 58))
                    trunk.addLine(to: CGPoint(x: trunkX, y: nodeCenterY(sessions.count - 1)))
                    context.stroke(trunk, with: .color(OrkTheme.rail), lineWidth: 1.5)
                    for (index, session) in sessions.enumerated() {
                        let y = nodeCenterY(index)
                        var stub = Path()
                        stub.move(to: CGPoint(x: trunkX, y: y))
                        stub.addLine(to: CGPoint(x: 42, y: y))
                        context.stroke(stub, with: .color(OrkTheme.rail), lineWidth: 1.5)
                        let dot = CGRect(x: trunkX - 2.5, y: y - 2.5, width: 5, height: 5)
                        context.fill(Path(ellipseIn: dot), with: .color(session.agent.tint))
                    }
                }
                workspaceNode.offset(x: 14, y: 12)
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    sessionNode(session)
                        .offset(x: 42, y: firstNodeY + CGFloat(index) * nodeStep)
                }
            }
            .frame(height: firstNodeY + CGFloat(sessions.count) * nodeStep + 20, alignment: .topLeading)
        }
    }

    private var workspaceNode: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(OrkTheme.clay)
            Text(workspace.name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(OrkTheme.cream)
                .lineLimit(1)
            Spacer()
            Text("\(sessions.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(OrkTheme.stone)
        }
        .padding(.horizontal, 12)
        .frame(width: paneWidth - 28, height: 44)
        .orkCard()
    }

    private func sessionNode(_ session: TerminalSession) -> some View {
        let isFocused = focused?.id == session.id
        return Button {
            focusedID = session.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: session.agent.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(session.agent.tint)
                    .frame(width: 28, height: 28)
                    .background(session.agent.tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.agent.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OrkTheme.cream)
                    Text(session.worktreeBranch ?? URL(fileURLWithPath: session.directory).lastPathComponent)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(OrkTheme.stone)
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(session.exited ? OrkTheme.brick : OrkTheme.moss)
                    .frame(width: 5, height: 5)
            }
            .padding(.horizontal, 11)
            .frame(width: paneWidth - 56, height: nodeHeight, alignment: .leading)
            .background(isFocused ? OrkTheme.overlay : OrkTheme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isFocused ? session.agent.tint.opacity(0.55) : OrkTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .animation(OrkMotion.hover, value: isFocused)
    }

    @ViewBuilder private var detail: some View {
        if let session = focused {
            SessionCard(session: session)
        } else {
            Text("Select an agent to focus its terminal")
                .font(.system(size: 12))
                .foregroundStyle(OrkTheme.stone)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
