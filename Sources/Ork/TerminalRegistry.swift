import AppKit
import SwiftTerm

/// Owns the live terminal views outside SwiftUI so a layout change (grid to flow,
/// workspace switch) reparents the NSView instead of killing the PTY.
final class TerminalRegistry: NSObject {
    static let shared = TerminalRegistry()

    private var views: [UUID: LocalProcessTerminalView] = [:]
    private var exitHandlers: [ObjectIdentifier: () -> Void] = [:]

    func view(for session: TerminalSession, onExit: @escaping () -> Void) -> LocalProcessTerminalView {
        if let existing = views[session.id] { return existing }

        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        terminal.processDelegate = self
        terminal.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
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
        return terminal
    }

    func close(_ id: UUID) {
        guard let terminal = views.removeValue(forKey: id) else { return }
        exitHandlers[ObjectIdentifier(terminal)] = nil
        terminal.removeFromSuperview()
        // ponytail: dropping the last reference closes the PTY master and SIGHUPs the child
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
