import SwiftUI

@main
struct OrkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var settings = OrkSettings.shared

    init() {
        // Before any scene body renders, or SwiftUI resolves the custom font to a fallback.
        OrkMark.registerFonts()
    }

    private var colorScheme: ColorScheme {
        settings.appearance == .dark ? .dark : .light
    }

    var body: some Scene {
        // A unique Window, not a WindowGroup: terminal views are singletons
        // in TerminalRegistry, so a second main window would steal them from
        // the first (dead scroll, blank cards). openWindow(id:) now focuses
        // the existing window instead of minting another.
        Window("ork", id: "main") {
            RootView()
                .environmentObject(store)
                // Theme lives in OrkTheme statics: re-key the tree so a mode
                // change re-reads every color. Terminals survive in the registry.
                .id(settings.appearance)
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(colorScheme)
        }

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(store)
                .id(settings.appearance)
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
                // Opaque: behind-window vibrancy works per-region regardless
                // (Finder's sidebar does it), and a non-opaque full-screen
                // window makes the WindowServer alpha-blend every terminal
                // repaint against the desktop for nothing.
                window.isOpaque = true
                window.backgroundColor = .black
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
