import SwiftUI

enum OrkTheme {
    static let bg = Color(hex: 0x05070D)
    static let bgRaised = Color(hex: 0x0A0F1C)
    static let stroke = Color.white.opacity(0.08)
    static let cyan = Color(hex: 0x00E5FF)
    static let magenta = Color(hex: 0xFF2EC8)
    static let green = Color(hex: 0x3EF08A)
    static let amber = Color(hex: 0xFFB454)
    static let red = Color(hex: 0xFF5C7A)
    static let text = Color(hex: 0xE8EEF9)
    static let dim = Color(hex: 0x7C8698)
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
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(OrkTheme.stroke, lineWidth: 1))
    }
}

struct Backdrop: View {
    var body: some View {
        ZStack {
            OrkTheme.bg
            LinearGradient(
                colors: [OrkTheme.cyan.opacity(0.08), .clear, OrkTheme.magenta.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                let step: CGFloat = 46
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(.white.opacity(0.02)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }
}
