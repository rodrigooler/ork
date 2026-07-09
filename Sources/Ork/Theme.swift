import SwiftUI

/// Warm charcoal palette in the spirit of Claude Desktop: quiet surfaces,
/// cream text, one clay accent. Agent tints stay muted so terminals dominate.
enum OrkTheme {
    static let ink = Color(hex: 0x262624)       // window background
    static let well = Color(hex: 0x1E1D1B)      // sidebar, terminal wells, inputs
    static let raised = Color(hex: 0x2F2E2B)    // cards and panels
    static let overlay = Color(hex: 0x383733)   // hover / selected surfaces
    static let hairline = Color(hex: 0x3D3B36)  // borders
    static let rail = Color(hex: 0x4A463F)      // flow view connectors
    static let cream = Color(hex: 0xECEAE3)     // primary text
    static let stone = Color(hex: 0xA5A096)     // secondary text
    static let faint = Color(hex: 0x6F6B62)     // tertiary text
    static let clay = Color(hex: 0xF96B2F)      // accent, primary actions — the logo's neon frame
    static let moss = Color(hex: 0x97B380)      // running / ok
    static let brick = Color(hex: 0xC96A5F)     // exited / error
}

/// Brand display face — the logo's techno geometry (Orbitron, OFL, bundled).
/// Headings and caps labels only; body text stays in SF for legibility.
enum OrkFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("Orbitron", size: size).weight(weight)
    }
}

/// One motion voice (Apple design springs): critically damped by default,
/// bounce reserved for the notch, exits always faster than entries.
enum OrkMotion {
    static let hover = Animation.easeOut(duration: 0.12)
    static let state = Animation.snappy(duration: 0.22, extraBounce: 0)
    static let layout = Animation.smooth(duration: 0.35)
    static let overlay = Animation.smooth(duration: 0.3)
    static let exit = Animation.easeOut(duration: 0.18)
}

/// Instant scale-down on press for plain icon/tile buttons.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(OrkMotion.hover, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    func orkField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(OrkTheme.cream)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(OrkTheme.well)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(OrkTheme.hairline, lineWidth: 1))
    }

    /// Raised card recipe shared by panels, tiles and list rows.
    func orkCard(radius: CGFloat = 10, fill: Color = OrkTheme.raised) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(OrkTheme.hairline, lineWidth: 1)
            )
    }
}
