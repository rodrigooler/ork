import SwiftUI

/// Marquee gradient strip in the agent tints: the "agents at work" signature.
/// Lives on the notch and under the workspace header while sessions run.
struct AnimatedRail: View {
    var height: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                OrkTheme.clay,
                Color(hex: 0x97B380),
                Color(hex: 0x7FA3C4),
                Color(hex: 0xC7A566),
                OrkTheme.clay,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        Group {
            if reduceMotion {
                gradient
            } else {
                GeometryReader { geo in
                    let width = geo.size.width
                    HStack(spacing: 0) {
                        gradient.frame(width: width)
                        gradient.frame(width: width)
                    }
                    .offset(x: phase ? -width : 0)
                }
                .onAppear {
                    withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                        phase = true
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

/// Sonar dot: solid center with an expanding fading ring while active.
struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 6
    var active = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if active && !reduceMotion {
                Circle()
                    .stroke(color.opacity(pulse ? 0 : 0.5), lineWidth: 1.5)
                    .scaleEffect(pulse ? 2.6 : 1)
            }
            Circle().fill(color)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

/// The ork mark in color: clay hub, agent satellites. Same geometry as
/// Assets/logo.svg and the menu bar template icon.
struct OrkMarkView: View {
    var size: CGFloat = 28

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 18
            let center = CGPoint(x: 9 * s, y: 9 * s)
            let satellites: [(CGFloat, Color)] = [
                (90, Color(hex: 0x97B380)),
                (210, Color(hex: 0x7FA3C4)),
                (330, Color(hex: 0xC7A566)),
            ]
            for (angle, color) in satellites {
                let radians = angle * .pi / 180
                let tip = CGPoint(x: center.x + cos(radians) * 6 * s, y: center.y - sin(radians) * 6 * s)
                var spoke = Path()
                spoke.move(to: center)
                spoke.addLine(to: tip)
                context.stroke(spoke, with: .color(OrkTheme.rail), lineWidth: 1.3 * s)
                let dot = CGRect(x: tip.x - 1.8 * s, y: tip.y - 1.8 * s, width: 3.6 * s, height: 3.6 * s)
                context.fill(Path(ellipseIn: dot), with: .color(color))
            }
            let hub = CGRect(x: center.x - 2.7 * s, y: center.y - 2.7 * s, width: 5.4 * s, height: 5.4 * s)
            context.fill(Path(ellipseIn: hub), with: .color(OrkTheme.clay))
        }
        .frame(width: size, height: size)
    }
}
