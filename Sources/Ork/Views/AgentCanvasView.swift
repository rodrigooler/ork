import AppKit
import SwiftUI

/// Blueprints-style canvas: minimalist activity cards on the coordinator
/// tree, one traveling packet per routed team message, a golden flash when a
/// 'done' reaches the lead, and a GitHub PR/CI hub above the coordinator.
/// Terminals stay one click away: clicking a card opens Focus Mode.
struct AgentCanvasView: View {
    let workspace: Workspace
    let sessions: [TerminalSession]

    @EnvironmentObject private var store: AppStore
    @ObservedObject private var github = GitHubService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Arrival rings (golden done, moss approved, member color otherwise).
    @State private var rings: [UUID: Color] = [:]
    @State private var packets: [Packet] = []
    @State private var telemetry: [UUID: SessionTelemetry] = [:]
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1

    private var ordered: [TerminalSession] {
        guard let coordinatorID = store.teamMembers(in: workspace.id).first?.id,
              let coordinator = sessions.first(where: { $0.id == coordinatorID }) else { return sessions }
        return [coordinator] + sessions.filter { $0.id != coordinatorID }
    }

    private var hasRoot: Bool {
        store.teamMembers(in: workspace.id).first != nil && sessions.count > 1
    }

    private var hubPulls: [PullRequest] { github.pulls[workspace.id] ?? [] }
    private var showHub: Bool { hasRoot && !hubPulls.isEmpty }

    var body: some View {
        let members = ordered
        let layout = CanvasLayout.layout(count: members.count, hasRoot: hasRoot, hasHub: showHub)
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                if hasRoot {
                    edges(members: members, layout: layout)
                }
                if let hub = layout.hub {
                    hubEdge(hub: hub, root: layout.positions[0])
                    GitHubHubCard(pulls: hubPulls, members: members)
                        .frame(width: CanvasLayout.hubSize.width, height: CanvasLayout.hubSize.height)
                        .position(hub)
                }
                ForEach(Array(members.enumerated()), id: \.element.id) { index, session in
                    Button {
                        withAnimation(OrkMotion.overlay) { store.focusModeSessionID = session.id }
                    } label: {
                        AgentCanvasCard(
                            session: session,
                            isCoordinator: hasRoot && index == 0,
                            ring: rings[session.id],
                            telemetry: telemetry[session.id],
                            task: TeamService.shared.currentTask(
                                workspaceID: workspace.id,
                                member: TeamService.memberName(session)
                            )
                        )
                    }
                    .buttonStyle(.pressable)
                    .frame(width: CanvasLayout.cardSize.width, height: CanvasLayout.cardSize.height)
                    .position(layout.positions[index])
                    .help("Open in Focus Mode")
                }
                packetLayer
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .onTapGesture(count: 2) {
                withAnimation(OrkMotion.state) {
                    zoom = 1
                    zoomBase = 1
                }
            }
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(
                width: layout.size.width * zoom,
                height: layout.size.height * zoom,
                alignment: .topLeading
            )
            .padding(28)
        }
        .background(DotGrid())
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in zoom = min(1.5, max(0.5, zoomBase * value.magnification)) }
                .onEnded { _ in zoomBase = zoom }
        )
        .onAppear {
            TeamService.shared.onRoute = { sender, recipient, content in
                fire(sender: sender, recipient: recipient, content: content)
            }
        }
        .onDisappear { TeamService.shared.onRoute = nil }
        .task(id: workspace.id) {
            while !Task.isCancelled {
                if AppStore.deckWindowVisible {
                    github.refreshIfStale(workspace)
                    await refreshTelemetry()
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    // MARK: - Message traffic

    private static let gold = Color(red: 0.88, green: 0.64, blue: 0.35)

    /// One packet per routed message; completions land as a ring on the
    /// recipient. No standing animation: the canvas costs nothing while the
    /// team is quiet.
    private func fire(sender: UUID?, recipient: UUID, content: String) {
        let members = ordered
        let layout = CanvasLayout.layout(count: members.count, hasRoot: hasRoot, hasHub: showHub)
        let kind = TeamService.messageKind(content)
        let golden = kind == .done && hasRoot && recipient == members.first?.id
        let arrival: Color? = golden ? Self.gold : (kind == .approved ? OrkTheme.moss : nil)
        guard !reduceMotion,
              let sender,
              let fromIndex = members.firstIndex(where: { $0.id == sender }),
              let toIndex = members.firstIndex(where: { $0.id == recipient }) else {
            // User/app messages have no source card; reduced motion skips
            // travel. The arrival still shows, statically.
            if let color = arrival ?? senderlessRingColor(recipient, members: members) {
                ring(recipient, color: color)
            }
            return
        }
        let name = TeamService.memberName(members[fromIndex])
        let packet = Packet(
            from: layout.positions[fromIndex],
            to: layout.positions[toIndex],
            color: golden ? Self.gold : MemberPalette.color(for: name),
            golden: golden
        )
        packets.append(packet)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Packet.flight * 1_000_000_000))
            packets.removeAll { $0.id == packet.id }
            ring(recipient, color: arrival ?? packet.color)
        }
    }

    private func senderlessRingColor(_ recipient: UUID, members: [TerminalSession]) -> Color? {
        members.first(where: { $0.id == recipient })
            .map { MemberPalette.color(for: TeamService.memberName($0)) }
    }

    private func ring(_ id: UUID, color: Color) {
        withAnimation(OrkMotion.state) { rings[id] = color }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeOut(duration: 0.6)) { rings[id] = nil }
        }
    }

    /// Packets and their flight curves, redrawn per frame only while at
    /// least one packet is in the air.
    @ViewBuilder private var packetLayer: some View {
        if !packets.isEmpty {
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    for packet in packets {
                        let t = CGFloat(min(1, max(0, timeline.date.timeIntervalSince(packet.start) / Packet.flight)))
                        var curve = Path()
                        curve.move(to: packet.from)
                        let drop = CanvasLayout.curveDrop(from: packet.from, to: packet.to)
                        curve.addCurve(
                            to: packet.to,
                            control1: CGPoint(x: packet.from.x, y: packet.from.y + drop),
                            control2: CGPoint(x: packet.to.x, y: packet.to.y - drop)
                        )
                        context.stroke(curve, with: .color(packet.color.opacity(0.22)),
                                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        let point = CanvasLayout.cubicPoint(t: t, from: packet.from, to: packet.to)
                        let radius: CGFloat = packet.golden ? 5 : 3.5
                        let halo = CGRect(x: point.x - radius * 2.2, y: point.y - radius * 2.2,
                                          width: radius * 4.4, height: radius * 4.4)
                        context.fill(Path(ellipseIn: halo), with: .color(packet.color.opacity(0.25)))
                        let dot = CGRect(x: point.x - radius, y: point.y - radius,
                                         width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: dot), with: .color(packet.color))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Edges

    private func edges(members: [TerminalSession], layout: (positions: [CGPoint], hub: CGPoint?, size: CGSize)) -> some View {
        let root = layout.positions[0]
        let start = CGPoint(x: root.x, y: root.y + CanvasLayout.cardSize.height / 2)
        return ForEach(Array(members.enumerated().dropFirst()), id: \.element.id) { index, session in
            let center = layout.positions[index]
            let end = CGPoint(x: center.x, y: center.y - CanvasLayout.cardSize.height / 2)
            let lit = rings[session.id] != nil
            CanvasEdge(from: start, to: end)
                .stroke(
                    (rings[session.id] ?? MemberPalette.color(for: TeamService.memberName(session)))
                        .opacity(lit ? 0.9 : 0.3),
                    style: StrokeStyle(lineWidth: lit ? 2.5 : 1.5, lineCap: .round, dash: [6, 7])
                )
        }
    }

    private func hubEdge(hub: CGPoint, root: CGPoint) -> some View {
        CanvasEdge(
            from: CGPoint(x: hub.x, y: hub.y + CanvasLayout.hubSize.height / 2),
            to: CGPoint(x: root.x, y: root.y - CanvasLayout.cardSize.height / 2)
        )
        .stroke(OrkTheme.rail.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
    }

    // MARK: - Telemetry

    /// Same incremental transcript read as the notch; claude sessions only.
    private func refreshTelemetry() async {
        let targets = sessions.filter { $0.agent.slug == "claude" && !$0.hibernated && !$0.exited }
            .map { (id: $0.id, dir: $0.directory) }
        guard !targets.isEmpty else { return }
        let fresh = await Task.detached(priority: .utility) { () -> [UUID: SessionTelemetry] in
            var entries: [UUID: SessionTelemetry] = [:]
            for target in targets {
                entries[target.id] = SessionTelemetryService.snapshot(directory: target.dir)
            }
            return entries
        }.value
        telemetry = fresh
    }
}

/// One team message in flight between two cards.
private struct Packet: Identifiable {
    let id = UUID()
    let from: CGPoint
    let to: CGPoint
    let color: Color
    let golden: Bool
    let start = Date()

    static let flight: TimeInterval = 0.8
}

/// Cubic drop from the coordinator's bottom edge to a member's top edge.
struct CanvasEdge: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        let drop = CanvasLayout.curveDrop(from: from, to: to)
        path.addCurve(
            to: to,
            control1: CGPoint(x: from.x, y: from.y + drop),
            control2: CGPoint(x: to.x, y: to.y - drop)
        )
        return path
    }
}

/// Fixed tree geometry so cards, edges and packets share the same math;
/// pure for tests.
enum CanvasLayout {
    static let cardSize = CGSize(width: 260, height: 112)
    static let hubSize = CGSize(width: 320, height: 124)
    static let hGap: CGFloat = 46
    static let vGap: CGFloat = 78
    static let columns = 3

    static func layout(count: Int, hasRoot: Bool, hasHub: Bool = false)
        -> (positions: [CGPoint], hub: CGPoint?, size: CGSize) {
        guard count > 0 else { return ([], nil, .zero) }
        let flock = hasRoot ? count - 1 : count
        let rows = flock == 0 ? [] : stride(from: 0, to: flock, by: columns).map {
            min(columns, flock - $0)
        }
        let widest = max(rows.max() ?? 1, hasRoot ? 1 : 0)
        var width = CGFloat(widest) * cardSize.width + CGFloat(max(0, widest - 1)) * hGap
        let showHub = hasHub && hasRoot
        if showHub { width = max(width, hubSize.width) }
        var positions: [CGPoint] = []
        var hub: CGPoint?
        var y: CGFloat = 0
        if showHub {
            hub = CGPoint(x: width / 2, y: hubSize.height / 2)
            y = hubSize.height + vGap
        }
        y += cardSize.height / 2
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
        return (positions, hub, CGSize(width: width, height: y - vGap))
    }

    /// Same vertical drop for edges and packet flights, so a packet rides
    /// exactly along the drawn curve.
    static func curveDrop(from: CGPoint, to: CGPoint) -> CGFloat {
        max(36, (to.y - from.y) / 2)
    }

    /// Point at parameter t on the edge curve between two card centers.
    static func cubicPoint(t: CGFloat, from: CGPoint, to: CGPoint) -> CGPoint {
        let drop = curveDrop(from: from, to: to)
        let c1 = CGPoint(x: from.x, y: from.y + drop)
        let c2 = CGPoint(x: to.x, y: to.y - drop)
        let u = 1 - t
        let x = u * u * u * from.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * to.x
        let y = u * u * u * from.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * to.y
        return CGPoint(x: x, y: y)
    }
}

/// Minimalist activity card: live tool call, current task and tokens instead
/// of a mini terminal. Real activity, no synthetic motion.
private struct AgentCanvasCard: View {
    @EnvironmentObject private var store: AppStore
    let session: TerminalSession
    let isCoordinator: Bool
    let ring: Color?
    let telemetry: SessionTelemetry?
    let task: String?

    private var name: String { TeamService.memberName(session) }
    private var memberColor: Color { MemberPalette.color(for: name) }
    private var asleep: Bool { store.frozenSessionIDs.contains(session.id) }
    private var running: Bool { !session.exited && !session.hibernated && !asleep }

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
            activity
            Rectangle().fill(OrkTheme.hairline).frame(height: 1)
            footer
        }
        .background(OrkTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    ring ?? memberColor.opacity(running ? 0.55 : 0.2),
                    lineWidth: ring != nil ? 2 : 1.5
                )
        )
        .shadow(
            color: ring?.opacity(0.5) ?? (running ? memberColor.opacity(0.18) : .clear),
            radius: ring != nil ? 14 : 8
        )
        .opacity(session.exited ? 0.55 : 1)
        .animation(OrkMotion.state, value: ring)
    }

    private var header: some View {
        HStack(spacing: 7) {
            MemberAvatar(name: name, size: 18)
            Text(name)
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
        .frame(height: 28)
        .background(OrkTheme.well)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 8.5))
                    .foregroundStyle(OrkTheme.faint)
                if let tool = telemetry?.lastTool {
                    Text(tool.detail.isEmpty ? tool.tool : "\(tool.tool) · \(tool.detail)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(OrkTheme.stone)
                        .lineLimit(1)
                } else {
                    Text("no recent tool call")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(OrkTheme.faint)
                }
            }
            HStack(spacing: 6) {
                if let task {
                    Text("task \(task)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(memberColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(memberColor.opacity(0.14))
                        .clipShape(Capsule())
                }
                Spacer()
                if let tokens = telemetry?.outputTokens, tokens > 0 {
                    Text("↑ \(Self.compact(tokens))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(OrkTheme.stone)
                        .help("Output tokens this conversation")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            Text(telemetry?.model.map(SessionTelemetry.shortModel) ?? session.agent.name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OrkTheme.faint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 20)
        .background(OrkTheme.well)
    }

    private static func compact(_ tokens: Int) -> String {
        switch tokens {
        case ..<1000: return "\(tokens)"
        case ..<1_000_000: return String(format: "%.1fk", Double(tokens) / 1000)
        default: return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
    }
}

/// Deterministic identity disc: initials on the member's palette color.
struct MemberAvatar: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        Text(MemberPalette.initials(name))
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(OrkTheme.ink)
            .frame(width: size, height: size)
            .background(MemberPalette.color(for: name))
            .clipShape(Circle())
    }
}

/// Open PRs and their CI state above the lead: the work leaving the team.
private struct GitHubHubCard: View {
    let pulls: [PullRequest]
    let members: [TerminalSession]

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OrkTheme.hairline).frame(height: 1)
            VStack(spacing: 2) {
                ForEach(pulls.prefix(3)) { pull in
                    row(pull)
                }
                if pulls.count > 3 {
                    Text("+\(pulls.count - 3) more")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(OrkTheme.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(OrkTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(OrkTheme.rail.opacity(0.8), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 8)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(OrkTheme.cream)
            Text("GitHub")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(OrkTheme.cream)
            Spacer()
            Text("\(pulls.count) open")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OrkTheme.stone)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(OrkTheme.well)
    }

    private func row(_ pull: PullRequest) -> some View {
        Button {
            NSWorkspace.shared.open(pull.url)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(checksColor(pull.checks))
                    .frame(width: 6, height: 6)
                    .help(checksHelp(pull.checks))
                Text("#\(pull.number)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OrkTheme.stone)
                Text(pull.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(OrkTheme.cream)
                    .lineLimit(1)
                Spacer()
                if let owner = GitHubService.owner(of: pull.branch, among: members) {
                    MemberAvatar(name: TeamService.memberName(owner), size: 13)
                        .help(TeamService.memberName(owner))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(pull.title)
    }

    private func checksColor(_ checks: PullRequest.Checks) -> Color {
        switch checks {
        case .passing: OrkTheme.moss
        case .failing: OrkTheme.brick
        case .pending: Color(red: 0.88, green: 0.64, blue: 0.35)
        case .none: OrkTheme.faint
        }
    }

    private func checksHelp(_ checks: PullRequest.Checks) -> String {
        switch checks {
        case .passing: "CI passing"
        case .failing: "CI failing"
        case .pending: "CI running"
        case .none: "No checks"
        }
    }
}
