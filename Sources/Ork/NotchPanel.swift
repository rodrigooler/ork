import AppKit
import SwiftUI

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

        let panel = NSPanel(
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
    }

    func scheduleCollapse() {
        collapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.setExpanded(false)
        }
        collapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }
}

struct NotchOverlay: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var feed = EventFeed.shared
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool

    @State private var isExpanded = false

    private var live: [TerminalSession] {
        store.sessions.filter { !$0.exited }
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
    }

    // MARK: - Collapsed: event ticker in the wings, ember glow, never plain black

    private var collapsed: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                PulsingDot(color: live.isEmpty ? OrkTheme.faint : OrkTheme.moss, size: 5, active: !live.isEmpty)
                Text("\(live.count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Text(live.count == 1 ? "agent" : "agents")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 0)
            }
            .padding(.leading, 14)
            .frame(width: NotchPanelController.wingWidth)
            Color.clear.frame(width: notchWidth)
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                if let event = feed.latest {
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
        .background(
            ZStack(alignment: .bottom) {
                Color.black.opacity(hasNotch ? 1 : 0.94)
                // The ember wash: the logo-orange gradient sliding under the
                // glass, so the bar reads alive instead of dead black.
                RailLayer(animating: !live.isEmpty, tints: AnimatedRail.emberTints)
                    .opacity(live.isEmpty ? 0.10 : 0.22)
                    .blendMode(.screen)
                AnimatedRail(height: 2, tints: AnimatedRail.emberTints)
                    .opacity(live.isEmpty ? 0.35 : 0.9)
                    .shadow(color: OrkTheme.clay.opacity(0.55), radius: 4)
            }
        )
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 14, bottomTrailing: 14)))
        .overlay(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 14, bottomTrailing: 14))
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Expanded: sessions + timeline glance

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
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
                }
                .frame(maxHeight: 260)
            }
            timeline
        }
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
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(live.count) \(live.count == 1 ? "session" : "sessions")")
                .font(OrkFont.display(12))
                .foregroundStyle(OrkTheme.cream)
            if !store.frozenSessionIDs.isEmpty {
                Chip(text: "\(store.frozenSessionIDs.count) asleep", tint: OrkTheme.stone)
            }
            if !store.teamSessionIDs.isEmpty {
                Chip(text: "\(store.teamSessionIDs.count) in team", tint: OrkTheme.clay)
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

    private func sessionRow(_ session: TerminalSession) -> some View {
        let frozen = store.frozenSessionIDs.contains(session.id)
        return Button {
            openDeck()
        } label: {
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
                if session.hibernated {
                    stateBadge("moon.zzz", "hibernated")
                } else if frozen {
                    stateBadge("snowflake", "asleep")
                } else {
                    PulsingDot(color: OrkTheme.moss, size: 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

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
    }

    private func collapse() {
        withAnimation(OrkMotion.exit) { isExpanded = false }
        NotchPanelController.shared.scheduleCollapse()
    }
}
