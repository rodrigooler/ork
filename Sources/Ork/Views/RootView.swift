import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            ContentBackdrop().ignoresSafeArea()
            HStack(spacing: 0) {
                if !store.sidebarHidden {
                    SidebarView()
                        .frame(width: 232)
                        .background {
                            ZStack {
                                GlassBackground()
                                OrkTheme.well.opacity(0.45)
                            }
                            .ignoresSafeArea()
                        }
                        .transition(.move(edge: .leading))
                }
                // The work surface floats as a stage over the lit backdrop.
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OrkTheme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(OrkTheme.hairline.opacity(0.9), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.38), radius: 22, y: 8)
                    .padding([.top, .trailing, .bottom], 10)
                    .padding(.leading, 8)
            }
            .ignoresSafeArea(edges: .top)
            .animation(OrkMotion.overlay, value: store.sidebarHidden)
            if let focusID = store.focusModeSessionID,
               let session = store.sessions.first(where: { $0.id == focusID }) {
                FocusModeView(session: session)
                    .zIndex(10)
            }
        }
        .onAppear {
            store.openMainWindow = { openWindow(id: "main") }
            NotchPanelController.shared.install(store: store)
        }
    }

    @ViewBuilder private var content: some View {
        switch store.selection {
        case .workspace(let id):
            if let workspace = store.workspace(id: id) {
                WorkspaceView(workspace: workspace)
                    .id(workspace.id)
            } else {
                welcome
            }
        case .usage:
            UsageView()
        case nil:
            welcome
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            BrandLogo(height: 96)
                .shadow(color: OrkTheme.clay.opacity(0.35), radius: 26)
                .riseIn()
            VStack(spacing: 7) {
                Text("Welcome to ork")
                    .font(OrkFont.display(20))
                    .foregroundStyle(OrkTheme.cream)
                Text("Add a project and spawn agents, each in its own worktree.")
                    .font(.system(size: 12))
                    .foregroundStyle(OrkTheme.stone)
            }
            .riseIn(delay: 0.06)
            Button {
                pickWorkspaceFolder(store: store)
            } label: {
                Label("Add project", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(OrkTheme.clay)
            .padding(.top, 4)
            .riseIn(delay: 0.12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Without the sidebar there is no way to add or pick a project.
            withAnimation(OrkMotion.overlay) { store.sidebarHidden = false }
        }
    }
}

struct SidebarToggleButton: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Button {
            withAnimation(OrkMotion.overlay) { store.sidebarHidden.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(OrkTheme.stone)
        }
        .buttonStyle(.pressable)
        .keyboardShortcut("0", modifiers: .command)
        .help(store.sidebarHidden ? "Show sidebar (⌘0)" : "Hide sidebar (⌘0)")
    }
}
