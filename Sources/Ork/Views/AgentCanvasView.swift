import SpriteKit
import SwiftUI

/// What the canvas needs to know about one agent. Equatable so the flow view
/// only resyncs the scene when something visible actually changed.
struct AgentVisual: Equatable, Identifiable {
    enum State: Equatable { case running, asleep, hibernated, exited }
    let id: UUID
    let name: String
    let slug: String
    let symbol: String
    let tintHex: UInt32
    let state: State
    let isCoordinator: Bool
}

/// Spatial constellation of the workspace fleet: agents orbit the workspace
/// core, running ones pulse and shed sparks, the coordinator wears a crown,
/// and routed team messages fly as comets between nodes. GPU scene capped at
/// 30fps, paused with the window, static under Reduce Motion.
final class AgentCanvasScene: SKScene {
    var onSelect: ((UUID) -> Void)?
    var reduceMotion = false

    private let orbit = SKNode()
    private var agentNodes: [UUID: SKNode] = [:]
    private var linkNodes: [UUID: SKShapeNode] = [:]
    private var visuals: [AgentVisual] = []
    private var coreLabel: SKLabelNode?

    private static let orbitDuration: TimeInterval = 150
    private static let gold = NSColor(hex: 0xE0A458)

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        if orbit.parent == nil {
            addChild(orbit)
            buildCore()
        }
        if !reduceMotion, orbit.action(forKey: "spin") == nil {
            orbit.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: Self.orbitDuration)), withKey: "spin")
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutOrbit(animated: false)
    }

    /// Evenly spaced ring, first slot at the top. Pure for tests.
    static func orbitPosition(index: Int, count: Int, radius: CGFloat) -> CGPoint {
        guard count > 0 else { return .zero }
        let angle = CGFloat.pi / 2 - 2 * .pi * CGFloat(index) / CGFloat(count)
        return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
    }

    private var orbitRadius: CGFloat {
        max(90, min(size.width, size.height) / 2 - 96)
    }

    func sync(_ new: [AgentVisual], workspaceName: String) {
        coreLabel?.text = workspaceName
        let old = visuals
        visuals = new
        for gone in old where !new.contains(where: { $0.id == gone.id }) {
            agentNodes.removeValue(forKey: gone.id)?.removeFromParent()
            linkNodes.removeValue(forKey: gone.id)?.removeFromParent()
        }
        for visual in new {
            let previous = old.first { $0.id == visual.id }
            if previous != visual {
                agentNodes.removeValue(forKey: visual.id)?.removeFromParent()
                let node = makeAgentNode(visual)
                orbit.addChild(node)
                agentNodes[visual.id] = node
            }
        }
        layoutOrbit(animated: true)
    }

    private func layoutOrbit(animated: Bool) {
        let radius = orbitRadius
        for (index, visual) in visuals.enumerated() {
            guard let node = agentNodes[visual.id] else { continue }
            let target = Self.orbitPosition(index: index, count: visuals.count, radius: radius)
            if animated, !reduceMotion, node.position != .zero {
                node.run(.move(to: target, duration: 0.5))
            } else {
                node.position = target
            }
            link(for: visual.id).path = {
                let path = CGMutablePath()
                path.move(to: .zero)
                path.addLine(to: target)
                return path
            }()
        }
    }

    private func link(for id: UUID) -> SKShapeNode {
        if let existing = linkNodes[id] { return existing }
        let line = SKShapeNode()
        line.strokeColor = NSColor(hex: 0x6F6B62, alpha: 0.25)
        line.lineWidth = 1
        line.zPosition = -1
        orbit.addChild(line)
        linkNodes[id] = line
        return line
    }

    private func buildCore() {
        let halo = SKShapeNode(circleOfRadius: 34)
        halo.fillColor = NSColor(hex: 0xF96B2F, alpha: 0.14)
        halo.strokeColor = .clear
        addChild(halo)
        if !reduceMotion {
            halo.run(.repeatForever(.sequence([
                .group([.scale(to: 1.18, duration: 2.4), .fadeAlpha(to: 0.5, duration: 2.4)]),
                .group([.scale(to: 1.0, duration: 2.4), .fadeAlpha(to: 1.0, duration: 2.4)]),
            ])))
        }
        let core = SKShapeNode(circleOfRadius: 26)
        core.fillColor = NSColor(hex: 0x1C1A17)
        core.strokeColor = NSColor(hex: 0xF96B2F)
        core.lineWidth = 1.5
        core.glowWidth = 2
        addChild(core)
        if let mark = OrkMark.appIcon {
            let sprite = SKSpriteNode(texture: SKTexture(image: mark))
            sprite.size = CGSize(width: 30, height: 30)
            core.addChild(sprite)
        }
        let label = SKLabelNode(text: "")
        label.fontName = NSFont.systemFont(ofSize: 11, weight: .semibold).fontName
        label.fontSize = 11
        label.fontColor = .textColor
        label.position = CGPoint(x: 0, y: -52)
        addChild(label)
        coreLabel = label
    }

    private func makeAgentNode(_ visual: AgentVisual) -> SKNode {
        let container = SKNode()
        container.name = visual.id.uuidString
        let tint = NSColor(hex: visual.tintHex)
        let dimmed: CGFloat = switch visual.state {
        case .running: 1.0
        case .asleep: 0.55
        case .hibernated: 0.32
        case .exited: 0.25
        }
        container.alpha = dimmed

        if visual.state == .running, !reduceMotion {
            let halo = SKShapeNode(circleOfRadius: 24)
            halo.fillColor = tint.withAlphaComponent(0.22)
            halo.strokeColor = .clear
            halo.run(.repeatForever(.sequence([
                .group([.scale(to: 1.35, duration: 1.6), .fadeAlpha(to: 0.15, duration: 1.6)]),
                .group([.scale(to: 1.0, duration: 1.6), .fadeAlpha(to: 1.0, duration: 1.6)]),
            ])))
            container.addChild(halo)

            let sparks = SKEmitterNode()
            sparks.particleTexture = Self.sparkTexture
            sparks.particleBirthRate = 5
            sparks.particleLifetime = 1.4
            sparks.particleSpeed = 14
            sparks.particleSpeedRange = 8
            sparks.emissionAngleRange = .pi * 2
            sparks.particleAlpha = 0.5
            sparks.particleAlphaSpeed = -0.4
            sparks.particleScale = 0.16
            sparks.particleScaleSpeed = -0.08
            sparks.particleColor = tint
            sparks.particleColorBlendFactor = 1
            sparks.zPosition = -0.5
            container.addChild(sparks)
        }

        let circle = SKShapeNode(circleOfRadius: 22)
        circle.fillColor = NSColor(hex: 0x1C1A17)
        circle.strokeColor = visual.state == .exited ? NSColor(hex: 0x6F6B62) : tint
        circle.lineWidth = 1.5
        circle.glowWidth = visual.state == .running ? 2 : 0
        container.addChild(circle)

        if let icon = Self.icon(for: visual, tint: tint) {
            container.addChild(icon)
        }

        let label = SKLabelNode(text: visual.name)
        label.fontName = NSFont.systemFont(ofSize: 10, weight: .medium).fontName
        label.fontSize = 10
        label.fontColor = visual.state == .running ? .textColor : .secondaryLabelColor
        label.position = CGPoint(x: 0, y: -40)
        container.addChild(label)

        if visual.state == .asleep || visual.state == .hibernated {
            if let moon = Self.symbolSprite("moon.zzz.fill", size: 11, color: .secondaryLabelColor) {
                moon.position = CGPoint(x: 18, y: 16)
                container.addChild(moon)
            }
        }

        if visual.isCoordinator, let crown = Self.symbolSprite("crown.fill", size: 15, color: Self.gold) {
            crown.position = CGPoint(x: 0, y: 36)
            if !reduceMotion {
                crown.run(.repeatForever(.sequence([
                    .moveBy(x: 0, y: 3, duration: 1.2),
                    .moveBy(x: 0, y: -3, duration: 1.2),
                ])))
            }
            container.addChild(crown)
        }

        // The orbit container spins; counter-spin each node so icons and
        // labels stay upright while they circle the core.
        if !reduceMotion {
            container.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: Self.orbitDuration)))
        }
        return container
    }

    private static func icon(for visual: AgentVisual, tint: NSColor) -> SKSpriteNode? {
        if let brand = OrkMark.agentIcon(slug: visual.slug) {
            let sprite = SKSpriteNode(texture: SKTexture(image: brand))
            sprite.size = CGSize(width: 22, height: 22)
            return sprite
        }
        return symbolSprite(visual.symbol, size: 15, color: tint)
    }

    private static func symbolSprite(_ name: String, size: CGFloat, color: NSColor) -> SKSpriteNode? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let sprite = SKSpriteNode(texture: SKTexture(image: image))
        sprite.color = color
        sprite.colorBlendFactor = 1
        let ratio = image.size.height > 0 ? image.size.width / image.size.height : 1
        sprite.size = CGSize(width: size * ratio, height: size)
        return sprite
    }

    /// A routed team message: a glowing dot arcs from sender to recipient.
    /// Sender nil means the user or the app spoke; the comet leaves the core.
    func comet(from sender: UUID?, to recipient: UUID) {
        guard let target = agentNodes[recipient] else { return }
        let start = sender.flatMap { agentNodes[$0]?.position } ?? .zero
        let end = target.position
        let path = CGMutablePath()
        path.move(to: start)
        let mid = CGPoint(x: (start.x + end.x) / 2 - (end.y - start.y) * 0.2,
                          y: (start.y + end.y) / 2 + (end.x - start.x) * 0.2)
        path.addQuadCurve(to: end, control: mid)

        let dot = SKShapeNode(circleOfRadius: 3)
        dot.fillColor = Self.gold
        dot.strokeColor = .clear
        dot.glowWidth = 4
        dot.position = start
        orbit.addChild(dot)
        let duration: TimeInterval = reduceMotion ? 0.01 : 0.8
        dot.run(.sequence([
            .follow(path, asOffset: false, orientToPath: false, duration: duration),
            .fadeOut(withDuration: 0.2),
            .removeFromParent(),
        ]))
    }

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)
        var node: SKNode? = atPoint(location)
        while let current = node {
            if let name = current.name, let id = UUID(uuidString: name) {
                onSelect?(id)
                return
            }
            node = current.parent
        }
    }
}

/// SwiftUI host: owns the scene, resyncs it when the fleet changes, pauses it
/// with the window, and feeds routed team messages in as comets.
struct AgentCanvasView: View {
    let workspace: Workspace
    let visuals: [AgentVisual]
    let onSelect: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = AgentCanvasScene(size: CGSize(width: 800, height: 600))
    @State private var paused = false

    var body: some View {
        SpriteView(scene: scene, isPaused: paused,
                   preferredFramesPerSecond: 30, options: [.allowsTransparency])
            .background(DotGrid())
            .onAppear {
                scene.reduceMotion = reduceMotion
                scene.scaleMode = .resizeFill
                scene.onSelect = onSelect
                scene.sync(visuals, workspaceName: workspace.name)
                TeamService.shared.onRoute = { [weak scene] sender, recipient in
                    scene?.comet(from: sender, to: recipient)
                }
            }
            .onDisappear { TeamService.shared.onRoute = nil }
            .onChange(of: visuals) { _, new in scene.sync(new, workspaceName: workspace.name) }
            .task {
                while !Task.isCancelled {
                    paused = !AppStore.deckWindowVisible
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

private extension AgentCanvasScene {
    static let sparkTexture: SKTexture = {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return SKTexture(image: image)
    }()
}
