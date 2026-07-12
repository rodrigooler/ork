import AppKit
import SwiftUI

/// Borderless panel that can take keystrokes without activating the app,
/// Spotlight style, so prompt answers reach the notch while another app
/// stays frontmost.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Borderless always-on-top panel hugging the MacBook notch, AgentPeek style:
/// the collapsed bar wings out beside the notch showing the live event feed,
/// and hovering drops a glance panel with sessions and a timeline. There is
/// no official notch API; this is an NSPanel positioned over the notch using
/// the screen's safe area geometry.
final class NotchPanelController {
    static let shared = NotchPanelController()

    private var panel: NSPanel?
    private var collapsedFrame = NSRect.zero
    private var expandedFrame = NSRect.zero
    private(set) var isExpanded = false
    private var collapseWork: DispatchWorkItem?

    /// Text wings on each side of the physical notch.
    static let wingWidth: CGFloat = 210
    static let expandedSize = NSSize(width: 760, height: 560)

    func install(store: AppStore) {
        guard panel == nil, let screen = NSScreen.main else { return }

        let hasNotch = screen.safeAreaInsets.top > 0
        let notchHeight = hasNotch ? screen.safeAreaInsets.top : 30
        var notchWidth: CGFloat = 190
        if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width + 4
        }

        let collapsedWidth = notchWidth + Self.wingWidth * 2
        let top = screen.frame.maxY
        collapsedFrame = NSRect(
            x: screen.frame.midX - collapsedWidth / 2,
            y: top - notchHeight - 8,
            width: collapsedWidth,
            height: notchHeight + 8
        )
        expandedFrame = NSRect(
            x: screen.frame.midX - Self.expandedSize.width / 2,
            y: top - Self.expandedSize.height,
            width: Self.expandedSize.width,
            height: Self.expandedSize.height
        )

        let panel = KeyablePanel(
            contentRect: collapsedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: NotchOverlay(store: store, notchWidth: notchWidth, notchHeight: notchHeight, hasNotch: hasNotch)
        )
        panel.orderFrontRegardless()
        self.panel = panel
        // ponytail: main screen only; multi-display and screen-change handling when someone needs it
    }

    func setExpanded(_ expanded: Bool) {
        collapseWork?.cancel()
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        panel?.setFrame(expanded ? expandedFrame : collapsedFrame, display: true)
        if !expanded { releaseKeyIfHeld() }
    }

    func scheduleCollapse() {
        collapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.setExpanded(false)
        }
        collapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    /// Takes key focus so digits answer the pending prompt. Best effort: if
    /// the system declines, the option buttons still work on click.
    func grabKey() {
        guard isExpanded else { return }
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Ordering out while key hands focus back to the previously active app;
    /// regardless-front restores the bar without re-taking key.
    private func releaseKeyIfHeld() {
        guard let panel, panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }
}

struct NotchOverlay: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var feed = EventFeed.shared
    @ObservedObject private var settings = OrkSettings.shared
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var telemetry: [UUID: SessionTelemetry] = [:]
    @State private var pendingPrompts: [UUID: PendingPrompt] = [:]
    @State private var usage: AgentUsage?
    @State private var codexLimits: CodexLimits?
    @State private var limitsRefreshedAt: Date?
    @State private var hoveredRow: UUID?
    @State private var keyMonitor: Any?
    @State private var teamDraft = ""
    @State private var teamTarget: UUID?

    private var live: [TerminalSession] {
        store.sessions.filter { !$0.exited && store.isWorkspaceVisible($0.workspaceID) }
    }

    /// Actually working: not asleep, not hibernated.
    private var active: [TerminalSession] {
        live.filter { !$0.hibernated && !store.frozenSessionIDs.contains($0.id) }
    }

    /// Reduced motion swaps the state spring for a short fade, not nothing.
    private var stateAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : OrkMotion.state
    }

    var body: some View {
        Group {
            if isExpanded {
                expanded
            } else {
                collapsed
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onHover { inside in
            if inside {
                if !isExpanded { expand() }
            } else {
                if isExpanded { collapse() }
            }
        }
        .task {
            while !Task.isCancelled {
                scanPrompts()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    // MARK: - Collapsed: event ticker in the wings, ember glow, never plain black

    private var collapsed: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if pendingPrompts.isEmpty {
                    PulsingDot(color: active.isEmpty ? OrkTheme.faint : OrkTheme.moss, size: 5, active: !active.isEmpty)
                    Text("\(active.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("/ \(live.count)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("active")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    PulsingDot(color: OrkTheme.clay, size: 5)
                    Text("\(pendingPrompts.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OrkTheme.clay)
                    Text("waiting on you")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .animation(stateAnimation, value: pendingPrompts.isEmpty)
            .padding(.leading, 14)
            .frame(width: NotchPanelController.wingWidth)
            .help("\(active.count) working · \(live.count - active.count) asleep or hibernated · \(live.count) total")
            Color.clear.frame(width: notchWidth)
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                // Events cannot be attributed to a workspace, so privacy mode
                // silences the ticker entirely instead of leaking client names.
                if let event = feed.latest, !settings.privacyMode {
                    Image(systemName: event.symbol)
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color(hex: event.tintHex))
                    Text(event.text)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id(event.id)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                } else {
                    Text("ork")
                        .font(OrkFont.display(10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.trailing, 14)
            .frame(width: NotchPanelController.wingWidth)
            .animation(OrkMotion.state, value: feed.latest?.id)
        }
        .frame(height: notchHeight + 8)
        .background(Color.black.opacity(hasNotch ? 1 : 0.94))
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 14, bottomTrailing: 14)))
        .overlay(
            // grok.com/build border: one ember arc travels end to end.
            // The top edge sits at the screen edge, so the uniform-radius
            // beam path is indistinguishable from the uneven shape.
            BorderBeam(cornerRadius: 14, lineWidth: 1.5, active: !active.isEmpty || !pendingPrompts.isEmpty)
                .allowsHitTesting(false)
        )
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 14, bottomTrailing: 14))
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Expanded: sessions + limits + timeline glance

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if usage != nil || codexLimits != nil {
                limitsStrip
                    .transition(.opacity)
            }
            if live.isEmpty {
                Text("No active sessions. Spawn an agent from the deck.")
                    .font(.system(size: 11))
                    .foregroundStyle(OrkTheme.faint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(live) { session in
                            sessionRow(session)
                        }
                    }
                    .animation(stateAnimation, value: pendingPrompts)
                }
                .frame(maxHeight: 280)
            }
            if !teamWorkspaces.isEmpty {
                teamComposer
            }
            if !settings.privacyMode {
                timeline
            }
        }
        .animation(stateAnimation, value: usage == nil && codexLimits == nil)
        .padding(16)
        .padding(.top, hasNotch ? notchHeight : 8)
        .frame(width: NotchPanelController.expandedSize.width, alignment: .topLeading)
        .background(
            ZStack(alignment: .top) {
                Color.black
                RailLayer(animating: !live.isEmpty, tints: AnimatedRail.emberTints)
                    .frame(height: 120)
                    .opacity(0.10)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
        )
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24)))
        .overlay(
            // Light catching the glass edge: reads as material, costs one stroke.
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24))
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 26, y: 10)
        .contentShape(Rectangle())
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: isExpanded) {
            guard isExpanded else { return }
            while !Task.isCancelled {
                await refreshTelemetry()
                await refreshLimitsIfStale()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(live.count) \(live.count == 1 ? "session" : "sessions")")
                .font(OrkFont.display(12))
                .foregroundStyle(OrkTheme.cream)
            let asleep = live.filter { store.frozenSessionIDs.contains($0.id) }.count
            let inTeam = live.filter { store.teamSessionIDs.contains($0.id) }.count
            if asleep > 0 {
                Chip(text: "\(asleep) asleep", tint: OrkTheme.stone)
            }
            if inTeam > 0 {
                Chip(text: "\(inTeam) in team", tint: OrkTheme.clay)
            }
            if !pendingPrompts.isEmpty {
                Chip(text: "\(pendingPrompts.count) waiting", tint: OrkTheme.clay)
            }
            Spacer()
            Button {
                openDeck()
            } label: {
                Label("Open ork", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// Rate windows and spend, whatever each agent exposes: codex reports real
    /// percentages; claude has no persisted limits, so its side is local
    /// token counts and an estimated month cost from transcript math.
    private var limitsStrip: some View {
        HStack(spacing: 14) {
            if let usage {
                statCluster("claude", parts: claudeParts(usage))
            }
            if let codex = codexLimits {
                statCluster("codex", parts: codexParts(codex))
            }
            Spacer()
            if let usage {
                Text("Σ \(TokenFormat.compact(usage.total)) · 14d")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(OrkTheme.faint)
                    .help("All claude tokens across projects, last 14 days")
            }
        }
    }

    private func claudeParts(_ usage: AgentUsage) -> [String] {
        var parts = [
            "5h \(TokenFormat.compact(usage.last5h))",
            "7d \(TokenFormat.compact(usage.last7d))",
        ]
        if let cost = usage.monthCost {
            parts.append(String(format: "$%.0f mo est", cost))
        }
        return parts
    }

    private func codexParts(_ codex: CodexLimits) -> [String] {
        var parts: [String] = []
        if let primary = codex.primary {
            parts.append("\(windowLabel(primary.windowMinutes)) \(Int(primary.usedPercent))%")
        }
        if let secondary = codex.secondary {
            parts.append("\(windowLabel(secondary.windowMinutes)) \(Int(secondary.usedPercent))%")
        }
        return parts
    }

    private func windowLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "now"
        case ..<1440: return "\(minutes / 60)h"
        default: return "\(minutes / 1440)d"
        }
    }

    private func statCluster(_ name: String, parts: [String]) -> some View {
        HStack(spacing: 5) {
            Text(name)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(OrkTheme.stone)
            Text(parts.joined(separator: " · "))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(OrkTheme.cream.opacity(0.8))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
    }

    // MARK: - Session rows

    private func sessionRow(_ session: TerminalSession) -> some View {
        let frozen = store.frozenSessionIDs.contains(session.id)
        let prompt = pendingPrompts[session.id]
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: session.agent.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(session.agent.tint)
                    .frame(width: 16)
                Text(session.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(OrkTheme.cream)
                Text(store.workspace(id: session.workspaceID)?.name ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(OrkTheme.faint)
                if let persona = session.persona {
                    Image(systemName: "theatermasks")
                        .font(.system(size: 8.5))
                        .foregroundStyle(OrkTheme.stone)
                        .help(persona)
                }
                if store.teamSessionIDs.contains(session.id) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(OrkTheme.clay)
                }
                Spacer()
                if hoveredRow == session.id, !session.hibernated {
                    rowActions(session, frozen: frozen)
                } else {
                    if let stats = store.sessionStats[session.id], !stats.isClean || stats.ahead > 0 {
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
                    }
                    if let at = telemetry[session.id]?.lastActivity {
                        Text(relative(at))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(OrkTheme.faint)
                    }
                }
                if session.hibernated {
                    stateBadge("moon.zzz", "hibernated")
                } else if frozen {
                    stateBadge("snowflake", "asleep")
                } else {
                    PulsingDot(color: prompt == nil ? OrkTheme.moss : OrkTheme.clay, size: 5)
                }
            }
            if let entry = telemetry[session.id] {
                HStack(spacing: 8) {
                    if let tool = entry.lastTool {
                        Text("\(tool.tool)\(tool.detail.isEmpty ? "" : " · \(tool.detail)")")
                            .foregroundStyle(OrkTheme.stone)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let model = entry.model {
                        Text(shortModel(model))
                            .foregroundStyle(OrkTheme.faint)
                    }
                    if entry.outputTokens > 0 {
                        Text("↑\(TokenFormat.compact(entry.outputTokens)) / \(TokenFormat.compact(entry.contextTokens))")
                            .foregroundStyle(OrkTheme.faint)
                            .help("Output tokens this transcript / current context size")
                    }
                }
                .font(.system(size: 9, design: .monospaced))
                .padding(.leading, 24)
            }
            if let prompt {
                promptBox(session, prompt)
                    .padding(.leading, 24)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            prompt == nil
                ? Color.white.opacity(hoveredRow == session.id ? 0.07 : 0.04)
                : OrkTheme.clay.opacity(0.07)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(prompt == nil ? Color.clear : OrkTheme.clay.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { openDeck() }
        .onHover { inside in
            if inside {
                hoveredRow = session.id
            } else if hoveredRow == session.id {
                hoveredRow = nil
            }
        }
        .animation(OrkMotion.hover, value: hoveredRow == session.id)
    }

    private func rowActions(_ session: TerminalSession, frozen: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                frozen ? store.wake(session.id) : store.sleepSession(session.id)
            } label: {
                Image(systemName: frozen ? "sun.max" : "snowflake")
                    .font(.system(size: 9.5))
            }
            .help(frozen ? "Wake" : "Sleep (SIGSTOP)")
            Button {
                store.hibernate(session.id)
            } label: {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 9.5))
            }
            .help("Hibernate: end the process, resume the conversation on click")
        }
        .buttonStyle(.pressable)
        .foregroundStyle(OrkTheme.stone)
    }

    /// The agent's question, answerable in place: click an option, or use
    /// the number keys and esc while the panel has focus.
    private func promptBox(_ session: TerminalSession, _ prompt: PendingPrompt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prompt.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(OrkTheme.cream)
                .lineLimit(2)
            ForEach(prompt.options, id: \.key) { option in
                Button {
                    answer(session.id, key: option.key)
                } label: {
                    HStack(spacing: 6) {
                        Text(option.key)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(OrkTheme.clay)
                            .frame(width: 12)
                        Text(option.label)
                            .font(.system(size: 10))
                            .foregroundStyle(OrkTheme.cream.opacity(0.85))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
            Text("1–\(prompt.options.count) answers · esc declines")
                .font(.system(size: 8.5))
                .foregroundStyle(OrkTheme.faint)
        }
    }

    // MARK: - Prompt watch

    /// Claude renders choice prompts in the terminal; watch the visible tail
    /// of every live claude session and surface what is waiting on a key.
    private func scanPrompts() {
        var fresh: [UUID: PendingPrompt] = [:]
        for session in live
        where session.agent.slug == "claude" && !session.hibernated && !store.frozenSessionIDs.contains(session.id) {
            let lines = TerminalRegistry.shared.visibleTail(session.id)
            if let prompt = PromptWatchService.detect(lines: lines) {
                fresh[session.id] = prompt
            }
        }
        guard fresh != pendingPrompts else { return }
        for (id, prompt) in fresh where pendingPrompts[id]?.title != prompt.title {
            let name = store.sessions.first { $0.id == id }?.displayName ?? "agent"
            EventFeed.shared.post(symbol: "questionmark.bubble", tintHex: 0xC98F5F, text: "\(name) asks: \(prompt.title)")
        }
        pendingPrompts = fresh
        updateKeyRouting()
    }

    /// First pending prompt in row order; digits and esc go to this one.
    private var promptTarget: (id: UUID, prompt: PendingPrompt)? {
        for session in live {
            if let prompt = pendingPrompts[session.id] { return (session.id, prompt) }
        }
        return nil
    }

    private func answer(_ id: UUID, key: String) {
        // The prompt may have been answered in the terminal meanwhile; only
        // type into the PTY when it is still on screen.
        guard PromptWatchService.detect(lines: TerminalRegistry.shared.visibleTail(id)) != nil else {
            pendingPrompts[id] = nil
            updateKeyRouting()
            return
        }
        TerminalRegistry.shared.send(id, text: key)
        let name = store.sessions.first { $0.id == id }?.displayName ?? "agent"
        let choice = key == "\u{1b}" ? "esc" : key
        EventFeed.shared.post(symbol: "checkmark.bubble", tintHex: 0x7FA65A, text: "answered \(name): \(choice)")
        pendingPrompts[id] = nil
        updateKeyRouting()
    }

    /// The monitor closure captures view state by value, so it is torn down
    /// and reinstalled on every prompt change to stay current.
    private func updateKeyRouting() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        guard isExpanded, let target = promptTarget else { return }
        NotchPanelController.shared.grabKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            if event.keyCode == 53 {  // esc
                answer(target.id, key: "\u{1b}")
                return nil
            }
            if let chars = event.characters, let digit = Int(chars),
               (1...target.prompt.options.count).contains(digit) {
                answer(target.id, key: chars)
                return nil
            }
            return event
        }
    }

    // MARK: - Telemetry and limits

    /// Model, token counts and the latest tool call per claude session,
    /// polled only while the panel is open; transcripts are read off the
    /// main thread and only appended bytes are parsed after the first pass.
    private func refreshTelemetry() async {
        let targets = live.filter { $0.agent.slug == "claude" && !$0.hibernated }
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

    /// The usage scan reads every recent transcript, so it runs at most once
    /// every five minutes; daysBack stretches to cover the calendar month for
    /// the spend estimate.
    private func refreshLimitsIfStale() async {
        let stale = limitsRefreshedAt.map { Date().timeIntervalSince($0) > 300 } ?? true
        guard stale else { return }
        limitsRefreshedAt = Date()
        let day = Calendar.current.component(.day, from: Date())
        let fresh = await Task.detached(priority: .utility) {
            (usage: UsageService.claudeCode(daysBack: max(14, day)), codex: LimitsService.codex())
        }.value
        usage = fresh.usage
        codexLimits = fresh.codex
    }

    private func shortModel(_ model: String) -> String {
        model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: #"-20\d{6}$"#, with: "", options: .regularExpression)
    }

    // MARK: - Team composer

    private var teamWorkspaces: [Workspace] {
        var seen = Set<UUID>()
        var result: [Workspace] = []
        for session in live where store.teamSessionIDs.contains(session.id) {
            guard !seen.contains(session.workspaceID),
                  let workspace = store.workspace(id: session.workspaceID) else { continue }
            seen.insert(session.workspaceID)
            result.append(workspace)
        }
        return result
    }

    /// Message a live team as 'user' without opening the team pane; same
    /// outbox path as the pane composer, addressed to all members.
    private var teamComposer: some View {
        HStack(spacing: 8) {
            if teamWorkspaces.count > 1 {
                Picker("", selection: $teamTarget) {
                    ForEach(teamWorkspaces) { workspace in
                        Text(workspace.name).tag(Optional(workspace.id))
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 130)
            } else {
                Text(teamWorkspaces.first?.name ?? "")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(OrkTheme.stone)
            }
            TextField("Message the team as 'user'", text: $teamDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(OrkTheme.cream)
                .onSubmit(sendTeamMessage)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func sendTeamMessage() {
        let text = teamDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let workspaceID = teamTarget ?? teamWorkspaces.first?.id else { return }
        TeamService.shared.sendFromUser(workspaceID: workspaceID, to: "all", text: text)
        teamDraft = ""
    }

    // MARK: - Timeline

    private func stateBadge(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 8))
            Text(label).font(.system(size: 9))
        }
        .foregroundStyle(OrkTheme.faint)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TIMELINE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(OrkTheme.faint)
                .kerning(1.1)
            if feed.events.isEmpty {
                Text("Deck activity shows up here.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(OrkTheme.faint)
            } else {
                ForEach(feed.events.suffix(8).reversed()) { event in
                    HStack(spacing: 7) {
                        Image(systemName: event.symbol)
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: event.tintHex))
                            .frame(width: 14)
                        Text(event.text)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(OrkTheme.stone)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(relative(event.date))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(OrkTheme.faint)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(max(seconds, 0))s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }

    private func openDeck() {
        store.openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
        collapse()
    }

    private func expand() {
        NotchPanelController.shared.setExpanded(true)
        withAnimation(OrkMotion.overlay) { isExpanded = true }
        updateKeyRouting()
    }

    private func collapse() {
        withAnimation(OrkMotion.exit) { isExpanded = false }
        NotchPanelController.shared.scheduleCollapse()
        updateKeyRouting()
    }
}
