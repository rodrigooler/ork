import SwiftUI

/// Warm palette in the spirit of Claude Desktop: quiet surfaces, one clay
/// accent. Two mirrored modes; views read the same names in both.
enum OrkTheme {
    /// ponytail: global flag + full tree rebuild on change (RootView .id), not per-view observation
    static var light = false

    static var ink: Color      { light ? L.ink : D.ink }           // window background
    static var well: Color     { light ? L.well : D.well }         // sidebar, terminal wells, inputs
    static var raised: Color   { light ? L.raised : D.raised }     // cards and panels
    static var overlay: Color  { light ? L.overlay : D.overlay }   // hover / selected surfaces
    static var hairline: Color { light ? L.hairline : D.hairline } // borders
    static var rail: Color     { light ? L.rail : D.rail }         // flow view connectors
    static var cream: Color    { light ? L.cream : D.cream }       // primary text
    static var stone: Color    { light ? L.stone : D.stone }       // secondary text
    static var faint: Color    { light ? L.faint : D.faint }       // tertiary text
    static var clay: Color     { light ? L.clay : D.clay }         // accent — the logo's neon frame
    static var moss: Color     { light ? L.moss : D.moss }         // running / ok
    static var brick: Color    { light ? L.brick : D.brick }       // exited / error

    private enum D {
        static let ink = Color(hex: 0x262624)
        static let well = Color(hex: 0x1E1D1B)
        static let raised = Color(hex: 0x2F2E2B)
        static let overlay = Color(hex: 0x383733)
        static let hairline = Color(hex: 0x3D3B36)
        static let rail = Color(hex: 0x4A463F)
        static let cream = Color(hex: 0xECEAE3)
        static let stone = Color(hex: 0xA5A096)
        static let faint = Color(hex: 0x6F6B62)
        static let clay = Color(hex: 0xF96B2F)
        static let moss = Color(hex: 0x97B380)
        static let brick = Color(hex: 0xC96A5F)
    }

    /// Warm paper mirror of the dark palette; same clay accent.
    private enum L {
        static let ink = Color(hex: 0xF2EFE8)
        static let well = Color(hex: 0xE9E5DB)
        static let raised = Color(hex: 0xFAF8F3)
        static let overlay = Color(hex: 0xE0DBCE)
        static let hairline = Color(hex: 0xD6D0C2)
        static let rail = Color(hex: 0xBFB8A8)
        static let cream = Color(hex: 0x2C2A26)
        static let stone = Color(hex: 0x6C675D)
        static let faint = Color(hex: 0x9C968A)
        static let clay = Color(hex: 0xF96B2F)
        static let moss = Color(hex: 0x5D7A43)
        static let brick = Color(hex: 0xA84B3E)
    }
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
