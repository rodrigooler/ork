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

    private static func resolveFont() -> NSFont {
        let size = CGFloat(OrkSettings.shared.terminalFontSize)
        let picked = OrkSettings.shared.terminalFontName
        if !picked.isEmpty, let font = NSFont(name: picked, size: size) { return font }
        let candidates = [
            "JetBrainsMono Nerd Font Mono", "JetBrainsMonoNF-Regular", "JetBrains Mono", "JetBrainsMono-Regular",
            "FiraCode Nerd Font Mono", "Fira Code", "SF Mono", "SFMono-Regular", "Menlo",
        ]
        for name in candidates {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static var background: NSColor {
        OrkTheme.light
            ? NSColor(srgbRed: 0.914, green: 0.898, blue: 0.859, alpha: 1)
            : NSColor(srgbRed: 0.118, green: 0.114, blue: 0.106, alpha: 1)
    }

    private static var foreground: NSColor {
        OrkTheme.light
            ? NSColor(srgbRed: 0.173, green: 0.165, blue: 0.149, alpha: 1)
            : NSColor(srgbRed: 0.925, green: 0.918, blue: 0.89, alpha: 1)
    }

    private var keyMonitor: Any?

    override init() {
        super.init()
        // SwiftTerm seals keyDown (public, not open), so the keys agent TUIs
        // expect are remapped here, before AppKit dispatches to the view.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let terminal = self.terminalOwningFirstResponder(in: event.window) else { return event }
            return self.remap(event, to: terminal) ? nil : event
        }
    }

    func view(
        for session: TerminalSession,
        resume: Bool = false,
        onExit: @escaping () -> Void,
        onFocus: @escaping (Bool) -> Void
    ) -> LocalProcessTerminalView {
        if let existing = views[session.id] {
            focusCallbacks[session.id] = onFocus
            return existing
        }

        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        terminal.processDelegate = self
        terminal.font = Self.resolveFont()
        terminal.nativeBackgroundColor = Self.background
        terminal.nativeForegroundColor = Self.foreground

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"

        let escapedDir = session.directory.replacingOccurrences(of: "'", with: "'\\''")
        let command = resume ? (session.agent.resumeCommand ?? session.agent.command) : session.agent.command
        let bootstrap = "cd '\(escapedDir)' && \(command)"
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

    // MARK: - Freeze (SIGSTOP/SIGCONT on the PTY process group)

    private var frozenPids: [UUID: pid_t] = [:]

    func shellPid(for id: UUID) -> pid_t? {
        guard let pid = views[id]?.process.shellPid, pid > 0 else { return nil }
        return pid
    }

    /// Parks the whole group (zsh, CLI, children): CPU drops to zero, memory
    /// stays resident but compresses. The forkpty child is its session leader,
    /// so -pid addresses the group.
    func freeze(_ id: UUID) -> Bool {
        guard frozenPids[id] == nil, let pid = shellPid(for: id) else { return false }
        guard kill(-pid, SIGSTOP) == 0 else { return false }
        frozenPids[id] = pid
        return true
    }

    func thaw(_ id: UUID) {
        guard let pid = frozenPids.removeValue(forKey: id) else { return }
        kill(-pid, SIGCONT)
    }

    /// A stopped process never delivers SIGTERM/SIGHUP, so every teardown
    /// path must resume the group first or it leaks a suspended CLI forever.
    func thawAll() {
        for id in Array(frozenPids.keys) { thaw(id) }
    }

    func close(_ id: UUID) {
        thaw(id)
        guard let terminal = views.removeValue(forKey: id) else { return }
        exitHandlers[ObjectIdentifier(terminal)] = nil
        focusCallbacks[id] = nil
        if focusedSession == id { focusedSession = nil }
        terminal.removeFromSuperview()
        // ponytail: dropping the last reference closes the PTY master and SIGHUPs the child
    }

    /// Ends the process group deterministically and frees the terminal view
    /// (hibernate path). SIGHUP goes out before close so memory returns now,
    /// not whenever the view deallocates.
    func terminate(_ id: UUID) {
        thaw(id)
        if let pid = shellPid(for: id) { kill(-pid, SIGHUP) }
        close(id)
    }

    // MARK: - Settings

    /// Live-applies the Settings font to every open terminal.
    func applyFont() {
        let font = Self.resolveFont()
        for view in views.values { view.font = font }
    }

    /// Live-applies the theme's terminal colors to every open terminal.
    func applyAppearance() {
        for view in views.values {
            view.nativeBackgroundColor = Self.background
            view.nativeForegroundColor = Self.foreground
        }
    }

    // MARK: - Keyboard remaps

    /// Shift+Enter, Ctrl/Cmd+Backspace and image paste: what agent TUIs
    /// expect from a modern terminal. Returns true when the event is consumed.
    private func remap(_ event: NSEvent, to terminal: LocalProcessTerminalView) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 36 where flags == .shift:
            // ESC CR: the newline Claude Code's /terminal-setup teaches iTerm and VSCode.
            terminal.send(txt: "\u{1B}\r")
            return true
        case 51 where flags == .control:
            terminal.send(txt: "\u{17}")  // ^W, delete word
            return true
        case 51 where flags == .command:
            terminal.send(txt: "\u{15}")  // ^U, kill line
            return true
        default:
            break
        }
        // Paste with an image on the clipboard: agents take file paths, so the
        // bitmap lands in a temp PNG and its path is typed. Cmd+V keeps normal
        // text paste; Ctrl+V with text passes through to the CLI as ^V.
        if event.charactersIgnoringModifiers == "v", flags == .command || flags == .control,
           !(flags == .command && NSPasteboard.general.string(forType: .string) != nil),
           let path = Self.writeImageToTempPNG(from: NSPasteboard.general) {
            terminal.send(txt: shellQuoted(path) + " ")
            return true
        }
        return false
    }

    private func terminalOwningFirstResponder(in window: NSWindow?) -> LocalProcessTerminalView? {
        guard let window, let responder = window.firstResponder else { return nil }
        return views.values.first { view in
            responder === view || ((responder as? NSView)?.isDescendant(of: view) ?? false)
        }
    }

    /// Saves the pasteboard's bitmap to a temp PNG; nil when there is no image.
    static func writeImageToTempPNG(from pasteboard: NSPasteboard) -> String? {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ork-paste-\(UUID().uuidString.prefix(8)).png")
        do { try png.write(to: url) } catch { return nil }
        return url.path
    }

    // MARK: - Focus tracking

    /// Hands keyboard focus to a session's terminal (used when entering focus mode).
    func focusTerminal(_ id: UUID) {
        guard let view = views[id] else { return }
        view.window?.makeFirstResponder(view)
    }

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

/// Hosts a terminal and accepts the drops SwiftTerm ignores: files type their
/// quoted paths, raw bitmaps land in a temp PNG first (iTerm behavior).
final class TerminalDropContainer: NSView {
    private weak var terminal: LocalProcessTerminalView?

    var onSleep: (() -> Void)?
    var onHibernate: (() -> Void)?

    init(terminal: LocalProcessTerminalView) {
        super.init(frame: terminal.frame)
        self.terminal = terminal
        terminal.frame = bounds
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) { nil }

    // SwiftTerm never overrides rightMouseDown, so the click bubbles here.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let sleep = NSMenuItem(title: "Sleep", action: #selector(sleepAction), keyEquivalent: "")
        sleep.target = self
        sleep.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: nil)
        menu.addItem(sleep)
        let hibernate = NSMenuItem(title: "Hibernate (Free Memory)", action: #selector(hibernateAction), keyEquivalent: "")
        hibernate.target = self
        hibernate.image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: nil)
        menu.addItem(hibernate)
        return menu
    }

    @objc private func sleepAction() { onSleep?() }
    @objc private func hibernateAction() { onHibernate?() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let terminal else { return false }
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            terminal.send(txt: urls.map { shellQuoted($0.path) }.joined(separator: " ") + " ")
            return true
        }
        if let path = TerminalRegistry.writeImageToTempPNG(from: pasteboard) {
            terminal.send(txt: shellQuoted(path) + " ")
            return true
        }
        return false
    }
}

func shellQuoted(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
