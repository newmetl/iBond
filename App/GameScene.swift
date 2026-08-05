import SpriteKit
import GameEngine

final class GameScene: SKScene {
    private var world: World?
    private var playerNode: SKShapeNode?
    private var npcNodes: [BodyID: SKShapeNode] = [:]

    private var lastUpdateTime: TimeInterval?
    private var accumulator: Double = 0
    private let fixedStep: Double = 1.0 / 120.0

    private let playerRadius: Double = 16
    private let npcRadius: Double = 14
    private let npcCount = 8

    private let touchController = TouchController()
    private var laserAimPoint: CGPoint?   // set while the laser finger is down

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1)
        view.isMultipleTouchEnabled = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Rotation / first layout: keep engine bounds in sync; bodies re-clamp
        // on the next update.
        world?.size = Vector2(size.width, size.height)
    }

    override func update(_ currentTime: TimeInterval) {
        ensureWorld()
        guard let world else { return }

        let dt: Double
        if let last = lastUpdateTime {
            dt = min(currentTime - last, 0.1) // clamp long pauses (backgrounding)
        } else {
            dt = 0
        }
        lastUpdateTime = currentTime

        accumulator += dt
        while accumulator >= fixedStep {
            world.update(dt: fixedStep)
            accumulator -= fixedStep
        }

        syncNodes()
    }

    // MARK: - World setup

    /// The scene's size is zero until SpriteView lays it out, so the world is
    /// created lazily on the first sized update.
    private func ensureWorld() {
        guard world == nil, size.width > 0, size.height > 0 else { return }
        let world = World(size: Vector2(size.width, size.height))

        world.addPlayer(at: Vector2(size.width / 2, size.height / 2), radius: playerRadius)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<npcCount {
            guard let position = world.randomFreePosition(radius: npcRadius, using: &rng) else { break }
            world.addNPC(at: position, radius: npcRadius)
        }
        self.world = world
        buildNodes(for: world)
    }

    private func buildNodes(for world: World) {
        let player = makeCircleNode(radius: playerRadius,
                                    fill: SKColor(red: 0.2, green: 0.85, blue: 1, alpha: 1))
        player.zPosition = 1 // above NPCs so overlap during shoves renders stably
        player.addChild(makeAimLineNode())
        addChild(player)
        playerNode = player

        for body in world.bodies where body.kind == .npc {
            let node = makeCircleNode(radius: npcRadius,
                                      fill: SKColor(red: 1, green: 0.45, blue: 0.35, alpha: 1))
            node.zPosition = 0
            addChild(node)
            npcNodes[body.id] = node
        }
    }

    private func makeCircleNode(radius: Double, fill: SKColor) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: CGFloat(radius))
        node.fillColor = fill
        node.strokeColor = .white
        node.lineWidth = 1.5
        return node
    }

    /// The "gun barrel" line: drawn along +x from the rim outward; aiming rotates
    /// the whole player node.
    private func makeAimLineNode() -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: playerRadius * 2.2, y: 0))
        let line = SKShapeNode(path: path)
        line.strokeColor = .white
        line.lineWidth = 2
        return line
    }

    // MARK: - Render sync

    private func syncNodes() {
        guard let world else { return }
        for body in world.bodies {
            switch body.kind {
            case .player:
                playerNode?.position = CGPoint(x: body.position.x, y: body.position.y)
            case .npc:
                npcNodes[body.id]?.position = CGPoint(x: body.position.x, y: body.position.y)
            }
        }
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            switch touchController.began(touch) {
            case .movement:
                world?.moveTarget = Vector2(location.x, location.y)
            case .laser:
                laserAimPoint = location
            case nil:
                break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            switch touchController.role(of: touch) {
            case .movement:
                // Hold-to-follow: keep re-targeting the finger.
                world?.moveTarget = Vector2(location.x, location.y)
            case .laser:
                laserAimPoint = location
            case nil:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if touchController.ended(touch) == .laser {
                laserAimPoint = nil
            }
            // A lifted movement finger leaves its last target in place — a tap
            // means "go there", so the player keeps gliding to it.
        }
    }
}
