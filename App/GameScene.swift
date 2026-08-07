import SpriteKit
import GameEngine

final class GameScene: SKScene {
    /// Fired (on the main thread) shortly after the last NPC dies, once its
    /// death animation has played out.
    var onAllNPCsEliminated: (() -> Void)?
    /// Fired when the laser battery runs out while NPCs are still alive.
    var onBatteryEmpty: (() -> Void)?

    private var gameStarted = false
    private var world: World?
    private var playerNode: SKShapeNode?
    private var npcNodes: [BodyID: SKShapeNode] = [:]
    private var targetCrossNode: SKShapeNode?
    private var lastPlayerPosition: CGPoint?

    private var lastUpdateTime: TimeInterval?
    private var accumulator: Double = 0
    private let fixedStep: Double = 1.0 / 120.0

    private let playerRadius: Double = 16
    private let npcRadius: Double = 14
    private let npcCount = 8

    /// Movement targets sit this far above the touch point so the player
    /// circle stays visible above the fingertip instead of hiding under it.
    private let touchTargetOffset: CGFloat = 60

    private let rockCount = 3
    private let mirrorCount = 2
    private let mirrorHalfLength: Double = 70

    private let touchController = TouchController()
    private var laserAimPoint: CGPoint?   // set while the laser finger is down
    private var laserNode: SKShapeNode?
    private var sparkNode: SKShapeNode?

    /// Laser battery: seconds of firing time. Drains only while the beam is
    /// actually rendering; empty battery with NPCs alive means game over.
    private let laserCapacity: Double = 2
    private var laserCharge: Double = 2
    private var batteryLabel: SKLabelNode?
    private var frameDt: Double = 0   // last frame's clamped wall-clock dt
    private var beamVisible = false   // tracks show/fade state of beam + spark

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1)
        view.isMultipleTouchEnabled = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Rotation / first layout: keep engine bounds in sync; bodies re-clamp
        // on the next update.
        world?.size = Vector2(size.width, size.height)
        batteryLabel?.position = CGPoint(x: size.width / 2, y: size.height - 80)
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
        frameDt = dt

        accumulator += dt
        while accumulator >= fixedStep {
            world.update(dt: fixedStep)
            accumulator -= fixedStep
        }

        syncNodes()
        processLaser()
        updateBatteryLabel()
    }

    // MARK: - World setup

    /// Starts a fresh game: tears down any previous world/nodes and builds a
    /// new one (player centered, NPCs re-randomized). Called from the menu.
    func startGame() {
        removeAllChildren()
        world = nil
        playerNode = nil
        npcNodes = [:]
        targetCrossNode = nil
        lastPlayerPosition = nil
        laserNode = nil
        sparkNode = nil
        laserAimPoint = nil
        batteryLabel = nil
        laserCharge = laserCapacity
        beamVisible = false
        gameStarted = true
        ensureWorld() // builds now if the scene is laid out; else on next update
    }

    /// The scene's size is zero until SpriteView lays it out, so the world is
    /// created lazily on the first sized update after the game starts.
    private func ensureWorld() {
        guard gameStarted, world == nil, size.width > 0, size.height > 0 else { return }
        let world = World(size: Vector2(size.width, size.height))

        world.addPlayer(at: Vector2(size.width / 2, size.height / 2), radius: playerRadius)
        var rng = SystemRandomNumberGenerator()

        // Mirrors first, then rocks, then NPCs — each placement pass avoids
        // everything placed before it (spawn sampling checks bodies + mirrors).
        let middle = Rect(min: Vector2(size.width * 0.15, size.height * 0.28),
                          max: Vector2(size.width * 0.85, size.height * 0.72))
        for _ in 0..<mirrorCount {
            guard let center = world.randomFreePosition(radius: mirrorHalfLength + 10,
                                                        in: middle, using: &rng) else { break }
            let angle = Double.random(in: 0..<Double.pi, using: &rng)
            let along = Vector2(cos(angle), sin(angle)) * mirrorHalfLength
            world.addMirror(from: center - along, to: center + along)
        }
        for _ in 0..<rockCount {
            let radius = Double.random(in: 38...52, using: &rng)
            guard let position = world.randomFreePosition(radius: radius, in: middle,
                                                          using: &rng) else { break }
            world.addRock(at: position, radius: radius)
        }
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

        for body in world.bodies where body.kind == .rock {
            let node = makeRockNode(radius: body.radius)
            node.position = CGPoint(x: body.position.x, y: body.position.y)
            node.zPosition = 0
            addChild(node)
        }

        for mirror in world.mirrors {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: mirror.start.x, y: mirror.start.y))
            path.addLine(to: CGPoint(x: mirror.end.x, y: mirror.end.y))
            let node = SKShapeNode(path: path)
            node.strokeColor = SKColor(red: 0.75, green: 0.93, blue: 1, alpha: 1)
            node.lineWidth = 3.5
            node.glowWidth = 1.5
            node.lineCap = .round
            node.zPosition = 0
            addChild(node)
        }

        let laser = SKShapeNode()
        laser.strokeColor = SKColor(red: 1, green: 0.2, blue: 0.3, alpha: 1)
        laser.lineWidth = 1.5
        laser.isHidden = true
        laser.zPosition = -1 // beam under the circles
        addChild(laser)
        laserNode = laser

        let spark = makeSparkNode()
        spark.isHidden = true
        addChild(spark)
        sparkNode = spark

        // Destination marker: a small cross shown while the player is en route.
        let crossPath = CGMutablePath()
        crossPath.move(to: CGPoint(x: -6, y: 0))
        crossPath.addLine(to: CGPoint(x: 6, y: 0))
        crossPath.move(to: CGPoint(x: 0, y: -6))
        crossPath.addLine(to: CGPoint(x: 0, y: 6))
        let cross = SKShapeNode(path: crossPath)
        cross.strokeColor = SKColor(white: 1, alpha: 0.7)
        cross.lineWidth = 1.5
        cross.isHidden = true
        cross.zPosition = 0.5 // above the beam, below the circles
        addChild(cross)
        targetCrossNode = cross

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontSize = 15
        label.fontColor = SKColor(white: 1, alpha: 0.85)
        label.position = CGPoint(x: size.width / 2, y: size.height - 80)
        label.zPosition = 3
        addChild(label)
        batteryLabel = label
    }

    private func updateBatteryLabel() {
        let percent = Int((laserCharge / laserCapacity * 100).rounded())
        batteryLabel?.text = String(format: "%d%% · %.2fs", percent, laserCharge)
    }

    /// The pulsing yellow impact spark; used persistently at the beam's
    /// endpoint and as a transient burst where an NPC gets hit.
    private func makeSparkNode() -> SKShapeNode {
        let spark = SKShapeNode(circleOfRadius: 5)
        spark.fillColor = SKColor(red: 1, green: 0.9, blue: 0.4, alpha: 1)
        spark.strokeColor = .clear
        spark.glowWidth = 8
        spark.zPosition = 2 // above every circle
        spark.run(.repeatForever(.sequence([
            .scale(to: 1.4, duration: 0.08),
            .scale(to: 0.8, duration: 0.08),
        ])))
        return spark
    }

    /// A big immovable rock: an irregular polygon roughly tracing the engine's
    /// circular collider (vertex radii jittered slightly inside/outside it).
    private func makeRockNode(radius: Double) -> SKShapeNode {
        let vertexCount = 9
        let path = CGMutablePath()
        for i in 0..<vertexCount {
            let angle = Double(i) / Double(vertexCount) * 2 * .pi
            let r = radius * Double.random(in: 0.86...1.04)
            let point = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor = SKColor(red: 0.33, green: 0.34, blue: 0.4, alpha: 1)
        node.strokeColor = SKColor(red: 0.5, green: 0.52, blue: 0.6, alpha: 1)
        node.lineWidth = 2
        node.lineJoin = .round
        return node
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
                let position = CGPoint(x: body.position.x, y: body.position.y)
                // Face the direction of travel, derived from the actual
                // per-frame position delta — velocity is zero at frame end
                // whenever the engine's arrival branch snaps to a near target
                // (slow finger-follow re-targets within one step's travel), so
                // velocity can't be trusted for facing. processLaser() runs
                // after this and overrides with the firing direction while the
                // laser is held; when idle, the last direction persists.
                if let last = lastPlayerPosition {
                    let dx = position.x - last.x
                    let dy = position.y - last.y
                    if dx * dx + dy * dy > 0.01 {
                        rotatePlayer(toward: atan2(dy, dx))
                    }
                }
                lastPlayerPosition = position
                playerNode?.position = position
            case .npc:
                npcNodes[body.id]?.position = CGPoint(x: body.position.x, y: body.position.y)
            case .rock:
                break // static; the node was positioned once at build time
            }
        }

        // The engine clears moveTarget on arrival, so the cross hides itself.
        if let target = world.moveTarget {
            targetCrossNode?.position = CGPoint(x: target.x, y: target.y)
            targetCrossNode?.isHidden = false
        } else {
            targetCrossNode?.isHidden = true
        }
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            switch touchController.began(touch) {
            case .movement:
                world?.moveTarget = movementTarget(for: location)
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
                world?.moveTarget = movementTarget(for: location)
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

    /// Turns the player toward `angle` along the shortest arc with exponential
    /// smoothing — quick (about 90% there in 150ms) but never an instant jump.
    /// Called every frame while moving or firing, so a fixed rate tracks a
    /// continuously changing target naturally.
    private func rotatePlayer(toward angle: CGFloat) {
        guard let playerNode else { return }
        var delta = angle - playerNode.zRotation
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        let smoothingRate: CGFloat = 15 // per second
        playerNode.zRotation += delta * min(1, smoothingRate * CGFloat(frameDt))
    }

    /// Offsets the touch upward so the player rides above the fingertip. The
    /// engine clamps targets into the playable rect, so top-edge taps are safe.
    private func movementTarget(for location: CGPoint) -> Vector2 {
        Vector2(location.x, location.y + touchTargetOffset)
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

    // MARK: - Laser

    private func processLaser() {
        guard let world else { return }
        guard laserCharge > 0, let aim = laserAimPoint,
              let beam = world.castLaserPath(through: Vector2(aim.x, aim.y)),
              let endPoint = beam.points.last, beam.points.count >= 2 else {
            fadeOutBeamIfNeeded()
            return
        }

        // Rotate the aim line to the outgoing firing direction — the first
        // beam segment, not the (possibly mirror-bent) final one.
        let direction = beam.points[1] - beam.points[0]
        rotatePlayer(toward: CGFloat(atan2(direction.y, direction.x)))

        // Polyline through every bounce point to the final hit / bounds exit.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: beam.points[0].x, y: beam.points[0].y))
        for point in beam.points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        laserNode?.path = path
        sparkNode?.position = CGPoint(x: endPoint.x, y: endPoint.y)
        showBeamNodes()

        // Only NPCs die — rocks just absorb the beam.
        if let victimID = beam.bodyID, world.body(withID: victimID)?.kind == .npc {
            kill(npcID: victimID, at: endPoint)
        }

        // The beam rendered this frame, so it drains the battery. This runs
        // after the kill so a last-kill-on-last-drop tie counts as a win.
        laserCharge = max(0, laserCharge - frameDt)
        if laserCharge <= 0, gameStarted,
           world.bodies.contains(where: { $0.kind == .npc }) {
            gameStarted = false
            fadeOutBeamIfNeeded()
            DispatchQueue.main.async { [weak self] in
                self?.onBatteryEmpty?()
            }
        }
    }

    /// Beam/spark visibility: showing is instant (cancels any running fade);
    /// stopping fades both out over 500ms instead of vanishing abruptly.
    private func showBeamNodes() {
        beamVisible = true
        for node in [laserNode, sparkNode] {
            node?.removeAction(forKey: "beamFade")
            node?.alpha = 1
            node?.isHidden = false
        }
    }

    private func fadeOutBeamIfNeeded() {
        guard beamVisible else { return }
        beamVisible = false
        for node in [laserNode, sparkNode] {
            node?.run(.sequence([.fadeOut(withDuration: 0.5), .hide()]),
                      withKey: "beamFade")
        }
    }

    /// Instant kill: remove from the simulation immediately, let the node play
    /// a short grow-and-fade before leaving the scene.
    private func kill(npcID: BodyID, at hitPoint: Vector2) {
        world?.remove(bodyID: npcID)

        // Same impact spark as at the world's edge, as a short burst — the NPC
        // is gone instantly, so the spark lives just long enough to register.
        let burst = makeSparkNode()
        burst.position = CGPoint(x: hitPoint.x, y: hitPoint.y)
        addChild(burst)
        burst.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))

        guard let node = npcNodes.removeValue(forKey: npcID) else { return }
        node.run(.sequence([
            .group([
                .scale(to: 1.6, duration: 0.15),
                .fadeOut(withDuration: 0.15),
            ]),
            .removeFromParent(),
        ]))

        // Last one? Let the death animation play, then report the win.
        if world?.bodies.contains(where: { $0.kind == .npc }) == false {
            gameStarted = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.onAllNPCsEliminated?()
            }
        }
    }
}
