import AppKit
import SwiftUI

/// Borderless always-on-top panel hugging the MacBook notch, AgentPeek style:
/// hover the notch and a quick glance panel drops down while ork stays out of
/// the way. There is no official notch API; this is an NSPanel positioned over
/// the notch using the screen's safe area geometry.
final class NotchPanelController {
    static let shared = NotchPanelController()

    private var panel: NSPanel?
    private var collapsedFrame = NSRect.zero
    private var expandedFrame = NSRect.zero
    private(set) var isExpanded = false
    private var collapseWork: DispatchWorkItem?

    func install(store: AppStore) {
        guard panel == nil, let screen = NSScreen.main else { return }

        let hasNotch = screen.safeAreaInsets.top > 0
        let notchHeight = hasNotch ? screen.safeAreaInsets.top : 30
        var notchWidth: CGFloat = 190
        if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width + 4
        }

        let expandedSize = NSSize(width: 660, height: 460)
        let top = screen.frame.maxY
        collapsedFrame = NSRect(
            x: screen.frame.midX - notchWidth / 2,
            y: top - notchHeight - 8,
            width: notchWidth,
            height: notchHeight + 8
        )
        expandedFrame = NSRect(
            x: screen.frame.midX - expandedSize.width / 2,
            y: top - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
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
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool

    @State private var isExpanded = false

    private var running: Int {
        store.sessions.filter { !$0.exited }.count
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

    private var collapsed: some View {
        UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 12, bottomTrailing: 12))
            .fill(Color.black.opacity(hasNotch ? 1 : 0.92))
            .frame(width: notchWidth, height: notchHeight)
            .overlay(alignment: .bottom) {
                if running > 0 {
                    AnimatedRail(height: 2.5)
                        .frame(width: notchWidth * 0.6)
                        .padding(.bottom, 2.5)
                        .shadow(color: OrkTheme.clay.opacity(0.55), radius: 4)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 34, height: 3)
                        .padding(.bottom, 3)
                }
            }
            .contentShape(Rectangle())
    }

    private var expanded: some View {
        PanelContent {
            store.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
            collapse()
        }
        .environmentObject(store)
        .padding(16)
        .padding(.top, hasNotch ? notchHeight : 8)
        .frame(width: 660, alignment: .top)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24)))
        .shadow(color: .black.opacity(0.55), radius: 26, y: 10)
        .contentShape(Rectangle())
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func expand() {
        NotchPanelController.shared.setExpanded(true)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { isExpanded = true }
    }

    private func collapse() {
        withAnimation(.easeOut(duration: 0.14)) { isExpanded = false }
        NotchPanelController.shared.scheduleCollapse()
    }
}
