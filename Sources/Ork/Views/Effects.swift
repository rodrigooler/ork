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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RailLayer(animating: !reduceMotion)
            .frame(height: height)
            .clipShape(Capsule())
    }
}

private struct RailLayer: NSViewRepresentable {
    let animating: Bool

    func makeNSView(context: Context) -> RailView { RailView() }
    func updateNSView(_ nsView: RailView, context: Context) { nsView.animating = animating }
}

/// A gradient layer twice the view's width, slid one width per loop.
private final class RailView: NSView {
    private let gradient = CAGradientLayer()
    var animating = true {
        didSet { if oldValue != animating { restart() } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let tints = [OrkTheme.clay, Color(hex: 0x97B380), Color(hex: 0x7FA3C4), Color(hex: 0xC7A566), OrkTheme.clay]
        let colors = tints.map { NSColor($0).cgColor }
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
