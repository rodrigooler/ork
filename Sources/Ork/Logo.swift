import AppKit

enum OrkMark {
    /// Bundled Orbitron (OFL) — the techno face of the wordmark, exposed to
    /// SwiftUI as OrkFont.display. Must run before any view renders.
    static func registerFonts() {
        guard let url = Bundle.module.url(forResource: "Orbitron", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// The official ork icon (Sources/Ork/Resources/ork-icon.png): neon
    /// rounded frame with the techno wordmark. Used in-app and as Dock icon.
    static let appIcon: NSImage? = Bundle.module
        .url(forResource: "ork-icon", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    /// Dock icon: the art composited into the macOS icon grid — transparent
    /// margins and squircle clip so it sits like a native icon.
    static let dockIcon: NSImage? = {
        guard let art = appIcon else { return nil }
        let size: CGFloat = 512
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let content = NSRect(
                x: size * 0.098, y: size * 0.098,
                width: size * 0.804, height: size * 0.804
            )
            NSBezierPath(roundedRect: content, xRadius: size * 0.18, yRadius: size * 0.18).addClip()
            art.draw(in: content)
            return true
        }
    }()

    /// Official agent brand icons bundled as agent-<slug>.png (128px squares).
    /// Main-thread cache; nil for agents without a brand mark (shell).
    private static var agentIconCache: [String: NSImage?] = [:]

    static func agentIcon(slug: String) -> NSImage? {
        if let hit = agentIconCache[slug] { return hit }
        let image = Bundle.module
            .url(forResource: "agent-\(slug)", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        agentIconCache[slug] = image
        return image
    }

    /// Monochrome template for the menu bar: the logo's rounded frame with
    /// the "o" hub. The wordmark itself is illegible at 18pt.
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let frame = NSBezierPath(
                roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 15),
                xRadius: 4.8,
                yRadius: 4.8
            )
            frame.lineWidth = 1.5
            frame.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7.1, y: 7.1, width: 3.8, height: 3.8)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
