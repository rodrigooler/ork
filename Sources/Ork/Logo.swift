import AppKit

enum OrkMark {
    /// Monochrome template version of the ork mark for the menu bar:
    /// an orchestrator hub with three agent spokes. Vector source: Assets/logo.svg.
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let center = CGPoint(x: 9, y: 9)
            let angles: [CGFloat] = [90, 210, 330]
            NSColor.black.setStroke()
            NSColor.black.setFill()
            for angle in angles {
                let radians = angle * .pi / 180
                let tip = CGPoint(x: center.x + cos(radians) * 6.2, y: center.y + sin(radians) * 6.2)
                let spoke = NSBezierPath()
                spoke.move(to: center)
                spoke.line(to: tip)
                spoke.lineWidth = 1.4
                spoke.stroke()
                NSBezierPath(ovalIn: CGRect(x: tip.x - 1.9, y: tip.y - 1.9, width: 3.8, height: 3.8)).fill()
            }
            NSBezierPath(ovalIn: CGRect(x: center.x - 2.7, y: center.y - 2.7, width: 5.4, height: 5.4)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
