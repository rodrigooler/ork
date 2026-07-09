import SwiftUI

@main
struct OrkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    init() {
        // Before any scene body renders, or SwiftUI resolves the custom font to a fallback.
        OrkMark.registerFonts()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(store)
        } label: {
            Image(nsImage: OrkMark.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running as a bare SPM executable (swift run) needs this to get a real window with focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let icon = OrkMark.dockIcon {
            NSApp.applicationIconImage = icon
        }
        DispatchQueue.main.async {
            if let window = NSApp.windows.first, let screen = window.screen ?? NSScreen.main {
                // Non-opaque so the sidebar's behind-window glass can sample the desktop.
                window.isOpaque = false
                window.backgroundColor = .clear
                window.setFrame(screen.visibleFrame, display: true)
            }
        }
    }

    // Keep living in the menu bar when the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        // Stopped groups never see the PTY's SIGHUP; resume them so they exit.
        TerminalRegistry.shared.thawAll()
    }
}
