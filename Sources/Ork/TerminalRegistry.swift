import AppKit
import SwiftTerm

/// Owns the live terminal views outside SwiftUI so a layout change (grid to flow,
/// workspace switch) reparents the NSView instead of killing the PTY.
/// Also tracks which terminal holds keyboard focus by observing the window's
/// firstResponder (SwiftTerm seals becomeFirstResponder, so no subclassing).
final class TerminalRegistry: NSObject {
    static let shared = TerminalRegistry()

    private var views: [UUID: LocalProcessTerminalView] = [:]
    private var exitHandlers: [ObjectIdentifier: () -> Void] = [:]
    private var focusCallbacks: [UUID: (Bool) -> Void] = [:]
    private var windowObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var focusedSession: UUID?

    private static let terminalFont: NSFont = {
        let candidates = [
            "JetBrainsMono Nerd Font Mono", "JetBrainsMonoNF-Regular", "JetBrains Mono", "JetBrainsMono-Regular",
            "FiraCode Nerd Font Mono", "Fira Code", "SF Mono", "SFMono-Regular", "Menlo",
        ]
        for name in candidates {
            if let font = NSFont(name: name, size: 12.5) { return font }
        }
        return .monospacedSystemFont(ofSize: 12.5, weight: .regular)
    }()

    func view(
        for session: TerminalSession,
        onExit: @escaping () -> Void,
        onFocus: @escaping (Bool) -> Void
    ) -> LocalProcessTerminalView {
        if let existing = views[session.id] {
            focusCallbacks[session.id] = onFocus
            return existing
        }

        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        terminal.processDelegate = self
        terminal.font = Self.terminalFont
        terminal.nativeBackgroundColor = NSColor(srgbRed: 0.118, green: 0.114, blue: 0.106, alpha: 1)
        terminal.nativeForegroundColor = NSColor(srgbRed: 0.925, green: 0.918, blue: 0.89, alpha: 1)

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"

        let escapedDir = session.directory.replacingOccurrences(of: "'", with: "'\\''")
        let bootstrap = "cd '\(escapedDir)' && \(session.agent.command)"
        terminal.startProcess(
            executable: "/bin/zsh",
            args: ["-l", "-c", bootstrap],
            environment: environment.map { "\($0.key)=\($0.value)" }
        )

        views[session.id] = terminal
        exitHandlers[ObjectIdentifier(terminal)] = onExit
        focusCallbacks[session.id] = onFocus
        return terminal
    }

    func close(_ id: UUID) {
        guard let terminal = views.removeValue(forKey: id) else { return }
        exitHandlers[ObjectIdentifier(terminal)] = nil
        focusCallbacks[id] = nil
        if focusedSession == id { focusedSession = nil }
        terminal.removeFromSuperview()
        // ponytail: dropping the last reference closes the PTY master and SIGHUPs the child
    }

    // MARK: - Focus tracking

    func observeWindowIfNeeded(_ window: NSWindow?) {
        guard let window else { return }
        let key = ObjectIdentifier(window)
        guard windowObservations[key] == nil else { return }
        windowObservations[key] = window.observe(\.firstResponder, options: [.initial, .new]) { [weak self] window, _ in
            DispatchQueue.main.async { self?.firstResponderChanged(in: window) }
        }
    }

    private func firstResponderChanged(in window: NSWindow) {
        let responder = window.firstResponder
        let newFocused = views.first { _, view in
            if responder === view { return true }
            if let respondingView = responder as? NSView { return respondingView.isDescendant(of: view) }
            return false
        }?.key
        guard newFocused != focusedSession else { return }
        if let old = focusedSession { focusCallbacks[old]?(false) }
        focusedSession = newFocused
        if let new = newFocused { focusCallbacks[new]?(true) }
    }
}

extension TerminalRegistry: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let key = ObjectIdentifier(source)
        DispatchQueue.main.async { [weak self] in
            self?.exitHandlers[key]?()
        }
    }
}
