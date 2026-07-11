import SwiftUI

/// Card-tree canvas: the coordinator card sits on top (crown on the header),
/// every other agent hangs below in rows, connected by curved edges that
/// pulse when Ork routes a team message to that agent. Each live card embeds
/// the session's real terminal, small; the grid and the canvas are never on
/// screen together, so the registry's singleton views move freely between them.
struct AgentCanvasView: View {
    let workspace: Workspace
    let sessions: [TerminalSession]

    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing: Set<UUID> = []

    private var ordered: [TerminalSession] {
        guard let coordinatorID = store.teamMembers(in: workspace.id).first?.id,
              let coordinator = sessions.first(where: { $0.id == coordinatorID }) else { return sessions }
        return [coordinator] + sessions.filter { $0.id != coordinatorID }
    }

    private var hasRoot: Bool {
        store.teamMembers(in: workspace.id).first != nil && sessions.count > 1
    }

    var body: some View {
        let members = ordered
        let layout = CanvasLayout.layout(count: members.count, hasRoot: hasRoot)
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                if hasRoot {
                    edges(members: members, positions: layout.positions)
                }
                ForEach(Array(members.enumerated()), id: \.element.id) { index, session in
                    AgentCanvasCard(
                        session: session,
                        isCoordinator: hasRoot && index == 0,
                        pulsing: pulsing.contains(session.id)
                    )
                    .frame(width: CanvasLayout.cardSize.width, height: CanvasLayout.cardSize.height)
                    .position(layout.positions[index])
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .padding(28)
        }
        .background(DotGrid())
        .onAppear {
            TeamService.shared.onRoute = { _, recipient in pulse(recipient) }
        }
        .onDisappear { TeamService.shared.onRoute = nil }
    }

    /// One-shot highlight, never a standing animation: the canvas costs
    /// nothing while the team is quiet.
    private func pulse(_ id: UUID) {
        guard !reduceMotion else { return }
        withAnimation(OrkMotion.state) { _ = pulsing.insert(id) }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.6)) { _ = pulsing.remove(id) }
        }
    }

    private func edges(members: [TerminalSession], positions: [CGPoint]) -> some View {
        let root = positions[0]
        let start = CGPoint(x: root.x, y: root.y + CanvasLayout.cardSize.height / 2)
        return ForEach(Array(members.enumerated().dropFirst()), id: \.element.id) { index, session in
            let center = positions[index]
            let end = CGPoint(x: center.x, y: center.y - CanvasLayout.cardSize.height / 2)
            let lit = pulsing.contains(session.id)
            CanvasEdge(from: start, to: end)
                .stroke(
                    session.agent.tint.opacity(lit ? 0.9 : 0.3),
                    style: StrokeStyle(lineWidth: lit ? 2.5 : 1.5, lineCap: .round, dash: [6, 7])
                )
        }
    }
}

/// Cubic drop from the coordinator's bottom edge to a member's top edge.
struct CanvasEdge: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        let drop = max(36, (to.y - from.y) / 2)
        path.addCurve(
            to: to,
            control1: CGPoint(x: from.x, y: from.y + drop),
            control2: CGPoint(x: to.x, y: to.y - drop)
        )
        return path
    }
}

/// Fixed tree geometry so cards and edges share the same math; pure for tests.
enum CanvasLayout {
    static let cardSize = CGSize(width: 330, height: 236)
    static let hGap: CGFloat = 46
    static let vGap: CGFloat = 78
    static let columns = 3

    static func layout(count: Int, hasRoot: Bool) -> (positions: [CGPoint], size: CGSize) {
        guard count > 0 else { return ([], .zero) }
        let flock = hasRoot ? count - 1 : count
        let rows = flock == 0 ? [] : stride(from: 0, to: flock, by: columns).map {
            min(columns, flock - $0)
        }
        let widest = max(rows.max() ?? 1, hasRoot ? 1 : 0)
        let width = CGFloat(widest) * cardSize.width + CGFloat(max(0, widest - 1)) * hGap
        var positions: [CGPoint] = []
        var y = cardSize.height / 2
        if hasRoot {
            positions.append(CGPoint(x: width / 2, y: y))
            y += cardSize.height + vGap
        }
        for rowCount in rows {
            let rowWidth = CGFloat(rowCount) * cardSize.width + CGFloat(rowCount - 1) * hGap
            var x = (width - rowWidth) / 2 + cardSize.width / 2
            for _ in 0..<rowCount {
                positions.append(CGPoint(x: x, y: y))
                x += cardSize.width + hGap
            }
            y += cardSize.height + vGap
        }
        return (positions, CGSize(width: width, height: y - vGap))
    }
}

private struct AgentCanvasCard: View {
    @EnvironmentObject private var store: AppStore
    let session: TerminalSession
    let isCoordinator: Bool
    let pulsing: Bool

    private var asleep: Bool { store.frozenSessionIDs.contains(session.id) }
    private var live: Bool { !session.exited && !session.hibernated }
    private var running: Bool { live && !asleep }

    private var statusColor: Color {
        if session.exited { return OrkTheme.brick }
        if session.hibernated || asleep { return OrkTheme.faint }
        return OrkTheme.moss
    }

    private var statusText: String {
        if session.exited { return "exited" }
        if session.hibernated { return "hibernated" }
        if asleep { return "sleeping" }
        return "running"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OrkTheme.hairline).frame(height: 1)
            if live {
                TerminalSurface(session: session)
                    .clipped()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: session.hibernated ? "moon.zzz.fill" : "xmark.circle")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(OrkTheme.faint)
                    Text(statusText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(OrkTheme.stone)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OrkTheme.ink)
            }
            Rectangle().fill(OrkTheme.hairline).frame(height: 1)
            footer
        }
        .background(OrkTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    session.agent.tint.opacity(running ? (pulsing ? 1.0 : 0.65) : 0.2),
                    lineWidth: pulsing ? 2 : 1.5
                )
        )
        .shadow(
            color: running ? session.agent.tint.opacity(pulsing ? 0.5 : 0.22) : .clear,
            radius: pulsing ? 14 : 9
        )
        .opacity(session.exited ? 0.55 : 1)
        .animation(OrkMotion.state, value: pulsing)
    }

    private var header: some View {
        HStack(spacing: 7) {
            if let icon = OrkMark.agentIcon(slug: session.agent.slug) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 15, height: 15)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5))
            } else {
                Image(systemName: session.agent.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(session.agent.tint)
            }
            Text(session.displayName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(OrkTheme.cream)
                .lineLimit(1)
            if isCoordinator {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(red: 0.88, green: 0.64, blue: 0.35))
                    .help("Coordinator")
            }
            Spacer()
            PulsingDot(color: statusColor, size: 5)
            Text(statusText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OrkTheme.stone)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(OrkTheme.well)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 8.5))
                .foregroundStyle(OrkTheme.faint)
            Text(session.worktreeBranch ?? URL(fileURLWithPath: session.directory).lastPathComponent)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OrkTheme.stone)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(OrkTheme.well)
    }
}
