import AppKit
import SwiftUI

/// Behind-window vibrancy: the desktop glows through the sidebar like every
/// native macOS app. Window-server compositing, no per-frame cost for us.
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The window's canvas: warm ink lit from above, with a faint clay bloom in
/// the top-left corner. Three static layers, drawn once.
struct ContentBackdrop: View {
    var body: some View {
        ZStack {
            OrkTheme.ink
            LinearGradient(
                colors: [Color.white.opacity(0.07), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.45)
            )
            RadialGradient(
                colors: [OrkTheme.clay.opacity(0.12), .clear],
                center: UnitPoint(x: 0.12, y: -0.1),
                startRadius: 0,
                endRadius: 1100
            )
        }
    }
}

/// Static blueprint dot grid for the flow topology. Drawn once per size.
struct DotGrid: View {
    var spacing: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 10
            while y < size.height {
                var x: CGFloat = 10
                while x < size.width {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                        with: .color(OrkTheme.faint.opacity(0.32))
                    )
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

/// Marquee gradient strip in the agent tints: the "agents at work" signature.
/// Driven entirely by Core Animation — the render server slides the gradient,
/// so there is zero app-side per-frame work and it pauses when occluded.
struct AnimatedRail: View {
    var height: CGFloat = 2.5
    /// nil = the multi-agent tint marquee; pass a set for a themed rail
    /// (the notch uses the logo-orange family).
    var tints: [Color]? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ember gradient for the notch: clay family only, no rainbow.
    static let emberTints = [
        OrkTheme.clay, Color(hex: 0xFFA25E), Color(hex: 0xB84A1B), Color(hex: 0xFFC08A), OrkTheme.clay,
    ]

    var body: some View {
        RailLayer(animating: !reduceMotion, tints: tints)
            .frame(height: height)
            .clipShape(Capsule())
    }
}

struct RailLayer: NSViewRepresentable {
    let animating: Bool
    var tints: [Color]? = nil

    func makeNSView(context: Context) -> RailView { RailView(tints: tints) }
    func updateNSView(_ nsView: RailView, context: Context) { nsView.animating = animating }
}

/// Traveling ember along a rounded border, grok.com/build style: a conic
/// gradient spins under a stroked rounded-rect mask, so one bright arc
/// chases itself end to end. Core Animation only, zero app-side frames.
struct BorderBeam: NSViewRepresentable {
    var cornerRadius: CGFloat = 14
    var lineWidth: CGFloat = 1.5
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> BorderBeamView {
        BorderBeamView(cornerRadius: cornerRadius, lineWidth: lineWidth)
    }

    func updateNSView(_ nsView: BorderBeamView, context: Context) {
        nsView.animating = active && !reduceMotion
        nsView.alphaValue = active ? 1 : 0.3
    }
}

final class BorderBeamView: NSView {
    private let gradient = CAGradientLayer()
    private let borderMask = CAShapeLayer()
    private let cornerRadius: CGFloat
    private let lineWidth: CGFloat
    var animating = true {
        didSet { if oldValue != animating { restart() } }
    }

    init(cornerRadius: CGFloat, lineWidth: CGFloat) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        super.init(frame: .zero)
        wantsLayer = true
        gradient.type = .conic
        let clear = NSColor(OrkTheme.clay).withAlphaComponent(0)
        gradient.colors = [
            clear, clear,
            NSColor(OrkTheme.clay).withAlphaComponent(0.7),
            NSColor(Color(hex: 0xFFC08A)),
            NSColor(OrkTheme.clay).withAlphaComponent(0.7),
            clear,
        ].map(\.cgColor)
        gradient.locations = [0, 0.58, 0.76, 0.84, 0.92, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        borderMask.fillColor = nil
        borderMask.strokeColor = NSColor.white.cgColor
        borderMask.lineWidth = lineWidth
        layer?.addSublayer(gradient)
        layer?.mask = borderMask
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        // Oversized square centered on the view so the spin always covers it.
        let side = sqrt(bounds.width * bounds.width + bounds.height * bounds.height)
        gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradient.position = CGPoint(x: bounds.midX, y: bounds.midY)
        borderMask.frame = bounds
        borderMask.path = CGPath(
            roundedRect: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
            cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
        )
        restart()
    }

    private func restart() {
        gradient.removeAnimation(forKey: "spin")
        guard animating, bounds.width > 0 else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 3.6
        spin.repeatCount = .infinity
        gradient.add(spin, forKey: "spin")
    }
}

/// A gradient layer twice the view's width, slid one width per loop.
final class RailView: NSView {
    private let gradient = CAGradientLayer()
    var animating = true {
        didSet { if oldValue != animating { restart() } }
    }

    init(tints: [Color]?) {
        super.init(frame: .zero)
        wantsLayer = true
        let resolved = tints ?? [OrkTheme.clay, Color(hex: 0x97B380), Color(hex: 0x7FA3C4), Color(hex: 0xC7A566), OrkTheme.clay]
        let colors = resolved.map { NSColor($0).cgColor }
        gradient.colors = colors + colors
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        gradient.frame = CGRect(x: 0, y: 0, width: bounds.width * 2, height: bounds.height)
        restart()
    }

    private func restart() {
        gradient.removeAnimation(forKey: "slide")
        guard animating, bounds.width > 0 else { return }
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = 0
        slide.toValue = -bounds.width
        slide.duration = 3.2
        slide.repeatCount = .infinity
        gradient.add(slide, forKey: "slide")
    }
}

/// Sonar dot: solid center with an expanding fading ring while active.
/// The ring loop is Core Animation — no SwiftUI re-render per frame.
struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 6
    var active = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if active && !reduceMotion {
                PulseRing(color: color)
            }
            Circle().fill(color)
        }
        .frame(width: size, height: size)
    }
}

private struct PulseRing: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> PulseRingView { PulseRingView() }
    func updateNSView(_ nsView: PulseRingView, context: Context) { nsView.color = NSColor(color) }
}

private final class PulseRingView: NSView {
    private let ring = CAShapeLayer()
    var color: NSColor = .white {
        didSet { ring.strokeColor = color.cgColor }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ring.fillColor = nil
        ring.lineWidth = 1.5
        ring.opacity = 0
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        ring.frame = bounds
        ring.path = CGPath(ellipseIn: bounds, transform: nil)
        restart()
    }

    private func restart() {
        ring.removeAnimation(forKey: "pulse")
        guard bounds.width > 0 else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 2.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.5
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.8
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "pulse")
    }
}

/// One-shot entrance: fade + small rise. Rare surfaces only (welcome, empty
/// states); reduced motion keeps the fade and drops the movement.
struct RiseIn: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(.smooth(duration: 0.4).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func riseIn(delay: Double = 0) -> some View { modifier(RiseIn(delay: delay)) }
}

/// The official ork logo art, clipped to its frame corners so the dark
/// canvas never reads as a stray square over glass surfaces.
struct BrandLogo: View {
    var height: CGFloat

    var body: some View {
        if let icon = OrkMark.appIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: height * 0.2, style: .continuous))
        }
    }
}
