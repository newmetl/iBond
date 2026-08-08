import SpriteKit
import GameEngine

final class GameScene: SKScene {
    /// Fired (on the main thread) shortly after the last NPC dies, once its
    /// death animation has played out.
    var onAllNPCsEliminated: (() -> Void)?
    /// Fired when the player dies — shot by a shooter, touched by a runner,
    /// or hit by their own reflected laser.
    var onPlayerKilled: (() -> Void)?

    private var gameStarted = false
    private var world: World?
    private var playerNode: SKShapeNode?
    private var npcNodes: [BodyID: SKShapeNode] = [:]
    private var lastPlayerPosition: CGPoint?
    private var cameraNode: SKCameraNode?
    private var joystickBase: SKShapeNode?
    private var joystickKnob: SKShapeNode?
    private var fireButton: SKShapeNode?

    private var shooterAimStart: [BodyID: TimeInterval] = [:]
    private var shooterAimNodes: [BodyID: SKShapeNode] = [:]
    private var batteryCarrierIDs: Set<BodyID> = []
    private var batteryPickups: [(position: CGPoint, node: SKShapeNode)] = []

    private var lastUpdateTime: TimeInterval?
    private var accumulator: Double = 0
    private let fixedStep: Double = 1.0 / 120.0

    private let playerRadius: Double = 16
    private let npcRadius: Double = 14

    /// The map spans this many screens in each dimension; the camera scrolls.
    private let mapScale: CGFloat = 3
    /// Camera follow box: the camera scrolls once the player crosses these
    /// margins. Generous side/top margins reveal enemies early; the bottom
    /// edge sits at 50% of the screen so downward movement scrolls from the
    /// center line (the corner controls live below it).
    private let cameraMarginX: CGFloat = 175
    private let cameraMarginTop: CGFloat = 280
    private let litterCount = 200

    private let shooterCount = 8
    private let batteryDropCount = 4
    private let runnerCount = 8
    private let shooterMinPlayerDistance: Double = 300
    /// Runners start hunting immediately, so they spawn farther out than
    /// shooters — closer spawns ended games before the first screenshot.
    private let runnerMinPlayerDistance: Double = 520
    /// Seconds a shooter aims (green telegraph line) before the killing shot.
    private let telegraphDuration: TimeInterval = 1.5

    /// Virtual joystick (lower-left): knob travel radius, touch-capture zone,
    /// and the base's offset from the screen corner.
    private let joystickRadius: CGFloat = 70
    private let steeringZoneRadius: CGFloat = 120
    private let joystickCornerOffset = CGPoint(x: 95, y: 110)

    /// Fire button (lower-right): tap = burst, hold = continuous. The beam
    /// fires along the player's current facing.
    private let fireButtonRadius: CGFloat = 44
    private let fireZoneRadius: CGFloat = 100
    private let fireButtonCornerOffset = CGPoint(x: 85, y: 115)

    private let rockCount = 16
    private let mirrorCount = 8
    private let mirrorHalfLength: Double = 70

    private let touchController = TouchController()
    private var fireButtonHeld = false
    private var laserNode: SKShapeNode?
    private var sparkNode: SKShapeNode?

    /// Laser battery: seconds of firing time. Drains only while the beam is
    /// actually rendering; empty battery with NPCs alive means game over.
    private let laserCapacity: Double = 2
    private var laserCharge: Double = 2
    private var batteryLabel: SKLabelNode?
    private var batteryHUDNode: SKNode?
    private var batteryFillBar: SKSpriteNode?
    private var enemyDotsNode: SKNode?
    private var lastEnemyDotCounts: (shooters: Int, runners: Int) = (-1, -1)
    private var frameDt: Double = 0   // last frame's clamped wall-clock dt
    private var beamVisible = false   // tracks show/fade state of beam + spark

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1)
        view.isMultipleTouchEnabled = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // The map is larger than the screen and fixed at game start — resizes
        // only change the viewport. Keep the HUD pinned inside the camera frame.
        batteryHUDNode?.position = CGPoint(x: 0, y: size.height / 2 - 80)
        joystickBase?.position = joystickCenter
        fireButton?.position = fireButtonCenter
    }

    /// Joystick base center in camera coordinates (lower-left corner).
    private var joystickCenter: CGPoint {
        CGPoint(x: -size.width / 2 + joystickCornerOffset.x,
                y: -size.height / 2 + joystickCornerOffset.y)
    }

    /// Fire button center in camera coordinates (lower-right corner).
    private var fireButtonCenter: CGPoint {
        CGPoint(x: size.width / 2 - fireButtonCornerOffset.x,
                y: -size.height / 2 + fireButtonCornerOffset.y)
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
        updateCamera()
        activateVisibleRunners()
        processLaser()
        processShooters(currentTime)
        checkRunnerTouches()
        checkBatteryPickups()
        updateBatteryHUD()
        updateEnemyDots()
    }

    /// Runners wait in ambush until they first scroll into view, then chase
    /// forever — without this, every runner would converge on spawn.
    private func activateVisibleRunners() {
        guard gameStarted, let world else { return }
        for body in world.bodies
        where body.kind == .runner
            && !world.activeRunnerIDs.contains(body.id)
            && isOnScreen(position: body.position, radius: body.radius) {
            world.activateRunner(body.id)
        }
    }

    // MARK: - World setup

    /// Starts a fresh game: tears down any previous world/nodes and builds a
    /// new one (player centered, NPCs re-randomized). Called from the menu.
    func startGame() {
        removeAllChildren()
        camera = nil
        cameraNode = nil
        world = nil
        playerNode = nil
        npcNodes = [:]
        joystickBase = nil
        joystickKnob = nil
        fireButton = nil
        lastPlayerPosition = nil
        laserNode = nil
        sparkNode = nil
        fireButtonHeld = false
        batteryLabel = nil
        batteryHUDNode = nil
        batteryFillBar = nil
        enemyDotsNode = nil
        lastEnemyDotCounts = (-1, -1)
        laserCharge = laserCapacity
        beamVisible = false
        shooterAimStart = [:]
        shooterAimNodes = [:]
        batteryCarrierIDs = []
        batteryPickups = []
        gameStarted = true
        ensureWorld() // builds now if the scene is laid out; else on next update
    }

    /// The scene's size is zero until SpriteView lays it out, so the world is
    /// created lazily on the first sized update after the game starts.
    private func ensureWorld() {
        guard gameStarted, world == nil, size.width > 0, size.height > 0 else { return }
        let mapSize = Vector2(size.width * mapScale, size.height * mapScale)
        let world = World(size: mapSize)

        let playerStart = mapSize * 0.5
        world.addPlayer(at: playerStart, radius: playerRadius)
        var rng = SystemRandomNumberGenerator()

        // Mirrors first, then rocks, then enemies — each placement pass avoids
        // everything placed before it (spawn sampling checks bodies + mirrors).
        let inset = 120.0
        let field = Rect(min: Vector2(inset, inset),
                         max: Vector2(mapSize.x - inset, mapSize.y - inset))
        for _ in 0..<mirrorCount {
            guard let center = world.randomFreePosition(radius: mirrorHalfLength + 10,
                                                        in: field, using: &rng) else { break }
            let angle = Double.random(in: 0..<Double.pi, using: &rng)
            let along = Vector2(cos(angle), sin(angle)) * mirrorHalfLength
            world.addMirror(from: center - along, to: center + along)
        }
        for _ in 0..<rockCount {
            let radius = Double.random(in: 38...56, using: &rng)
            guard let position = world.randomFreePosition(radius: radius, in: field,
                                                          using: &rng) else { break }
            world.addRock(at: position, radius: radius)
        }

        // Shooters lurk right next to rocks (their cover), never near the
        // player's spawn. The first `batteryDropCount` carry spare batteries.
        let rocks = world.rockIDs.compactMap { world.body(withID: $0) }
        var placedShooters = 0
        var attempts = 0
        while placedShooters < shooterCount, attempts < 300, let rock = rocks.randomElement(using: &rng) {
            attempts += 1
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let dist = rock.radius + npcRadius + Double.random(in: 4...26, using: &rng)
            let candidate = rock.position + Vector2(cos(angle), sin(angle)) * dist
            guard candidate.x > 20, candidate.x < mapSize.x - 20,
                  candidate.y > 20, candidate.y < mapSize.y - 20,
                  candidate.distance(to: playerStart) > shooterMinPlayerDistance,
                  world.bodies.allSatisfy({ $0.position.distance(to: candidate) >= $0.radius + npcRadius + 6 })
            else { continue }
            let id = world.addShooter(at: candidate, radius: npcRadius)
            // "Behind these obstacles": a shooter must start HIDDEN — reject
            // spots with a clear line to the player's spawn.
            if let pid = world.playerID, world.hasLineOfSight(from: id, to: pid) {
                world.remove(bodyID: id)
                continue
            }
            if batteryCarrierIDs.count < batteryDropCount { batteryCarrierIDs.insert(id) }
            placedShooters += 1
        }

        var placedRunners = 0
        attempts = 0
        while placedRunners < runnerCount, attempts < 300 {
            attempts += 1
            guard let position = world.randomFreePosition(radius: npcRadius, using: &rng),
                  position.distance(to: playerStart) > runnerMinPlayerDistance else { continue }
            world.addRunner(at: position, radius: npcRadius)
            placedRunners += 1
        }

        self.world = world
        buildNodes(for: world)
    }

    private func buildNodes(for world: World) {
        // Camera: follows the player near screen edges; carries the HUD.
        let camera = SKCameraNode()
        camera.position = CGPoint(x: world.size.x / 2, y: world.size.y / 2)
        addChild(camera)
        self.camera = camera
        cameraNode = camera

        // Decorative ground litter — small translucent stones/rubbish that
        // make the camera scroll visible. Purely cosmetic, no interaction.
        for _ in 0..<litterCount {
            let litter: SKShapeNode
            if Bool.random() {
                litter = SKShapeNode(circleOfRadius: CGFloat(Double.random(in: 1.5...3.5)))
            } else {
                litter = SKShapeNode(rectOf: CGSize(width: Double.random(in: 3...7),
                                                    height: Double.random(in: 2...5)))
                litter.zRotation = CGFloat(Double.random(in: 0..<(2 * .pi)))
            }
            let tone = Double.random(in: 0.5...0.75)
            litter.fillColor = SKColor(red: tone, green: tone * 0.95, blue: tone * 0.85,
                                       alpha: Double.random(in: 0.12...0.28))
            litter.strokeColor = .clear
            litter.position = CGPoint(x: Double.random(in: 0...world.size.x),
                                      y: Double.random(in: 0...world.size.y))
            litter.zPosition = -2
            addChild(litter)
        }

        let player = makeCircleNode(radius: playerRadius,
                                    fill: SKColor(red: 0.2, green: 0.85, blue: 1, alpha: 1))
        player.zPosition = 1 // above NPCs so overlap during shoves renders stably
        player.addChild(makeAimLineNode())
        addChild(player)
        playerNode = player

        for body in world.bodies where body.kind.isHostile {
            let fill: SKColor = body.kind == .runner
                ? SKColor(red: 0.75, green: 0.42, blue: 1, alpha: 1)  // purple: chases
                : SKColor(red: 1, green: 0.45, blue: 0.35, alpha: 1)  // red: shoots
            let node = makeCircleNode(radius: body.radius, fill: fill)
            node.zPosition = 0
            addChild(node)
            npcNodes[body.id] = node
        }

        for body in world.bodies where body.kind == .shooter {
            let aim = SKShapeNode()
            aim.strokeColor = SKColor(red: 0.3, green: 1, blue: 0.4, alpha: 0.55)
            aim.lineWidth = 1
            aim.isHidden = true
            aim.zPosition = -0.5
            addChild(aim)
            shooterAimNodes[body.id] = aim
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

        // Virtual joystick, pinned to the camera's lower-left corner.
        let base = SKShapeNode(circleOfRadius: joystickRadius)
        base.fillColor = SKColor(white: 1, alpha: 0.05)
        base.strokeColor = SKColor(white: 1, alpha: 0.25)
        base.lineWidth = 1.5
        base.position = joystickCenter
        base.zPosition = 3
        camera.addChild(base)
        joystickBase = base

        let knob = SKShapeNode(circleOfRadius: 26)
        knob.fillColor = SKColor(white: 1, alpha: 0.28)
        knob.strokeColor = SKColor(white: 1, alpha: 0.5)
        knob.lineWidth = 1
        base.addChild(knob)
        joystickKnob = knob

        // Fire button, pinned to the camera's lower-right corner.
        let fire = SKShapeNode(circleOfRadius: fireButtonRadius)
        fire.fillColor = SKColor(red: 1, green: 0.25, blue: 0.3, alpha: 0.22)
        fire.strokeColor = SKColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.6)
        fire.lineWidth = 2
        fire.position = fireButtonCenter
        fire.zPosition = 3
        camera.addChild(fire)
        fireButton = fire

        // Battery HUD (rides the camera): icon with a color-coded charge bar
        // plus the remaining firing time.
        let hud = SKNode()
        hud.position = CGPoint(x: 0, y: size.height / 2 - 80)
        hud.zPosition = 3
        camera.addChild(hud)
        batteryHUDNode = hud

        let iconBody = SKShapeNode(rectOf: CGSize(width: 26, height: 13), cornerRadius: 2.5)
        iconBody.strokeColor = SKColor(white: 1, alpha: 0.85)
        iconBody.lineWidth = 1.5
        iconBody.fillColor = .clear
        iconBody.position = CGPoint(x: -28, y: 0)
        hud.addChild(iconBody)

        let iconTip = SKShapeNode(rectOf: CGSize(width: 3, height: 6), cornerRadius: 1)
        iconTip.strokeColor = .clear
        iconTip.fillColor = SKColor(white: 1, alpha: 0.85)
        iconTip.position = CGPoint(x: -28 + 13 + 2.5, y: 0)
        hud.addChild(iconTip)

        let fill = SKSpriteNode(color: .green, size: CGSize(width: 22, height: 9))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: -28 - 11, y: 0)
        hud.addChild(fill)
        batteryFillBar = fill

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontSize = 15
        label.fontColor = SKColor(white: 1, alpha: 0.85)
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: -2, y: 0)
        hud.addChild(label)
        batteryLabel = label

        // One dot per remaining enemy, in the enemy's color (see updateEnemyDots).
        let dots = SKNode()
        dots.position = CGPoint(x: 0, y: -18)
        hud.addChild(dots)
        enemyDotsNode = dots
    }

    /// Rebuilds the HUD dot row whenever the remaining-enemy counts change:
    /// red dots for shooters, purple for runners, matching their map colors.
    private func updateEnemyDots() {
        guard let world, let enemyDotsNode else { return }
        var shooters = 0
        var runners = 0
        for body in world.bodies {
            if body.kind == .shooter { shooters += 1 }
            if body.kind == .runner { runners += 1 }
        }
        guard (shooters, runners) != lastEnemyDotCounts else { return }
        lastEnemyDotCounts = (shooters, runners)

        enemyDotsNode.removeAllChildren()
        let total = shooters + runners
        guard total > 0 else { return }
        let spacing: CGFloat = 12
        var x = -CGFloat(total - 1) * spacing / 2
        for index in 0..<total {
            let dot = SKShapeNode(circleOfRadius: 3.5)
            dot.fillColor = index < shooters
                ? SKColor(red: 1, green: 0.45, blue: 0.35, alpha: 1)   // shooter red
                : SKColor(red: 0.75, green: 0.42, blue: 1, alpha: 1)   // runner purple
            dot.strokeColor = .clear
            dot.position = CGPoint(x: x, y: 0)
            enemyDotsNode.addChild(dot)
            x += spacing
        }
    }

    private func updateBatteryHUD() {
        batteryLabel?.text = String(format: "%.2fs", laserCharge)
        let fraction = CGFloat(laserCharge / laserCapacity)
        batteryFillBar?.size = CGSize(width: 22 * max(0, fraction), height: 9)
        batteryFillBar?.color = fraction > 0.55
            ? SKColor(red: 0.3, green: 0.85, blue: 0.35, alpha: 1)   // green: full-ish
            : fraction > 0.25
                ? SKColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)   // yellow: mid
                : SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)   // red: running low
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
            case .npc, .shooter, .runner:
                npcNodes[body.id]?.position = CGPoint(x: body.position.x, y: body.position.y)
            case .rock:
                break // static; the node was positioned once at build time
            }
        }

    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if isInSteeringZone(touch) {
                if touchController.began(touch, as: .joystick) {
                    updateJoystick(with: touch)
                }
            } else if isInFireZone(touch) {
                if touchController.began(touch, as: .fire) {
                    fireButtonHeld = true
                    fireButton?.fillColor = SKColor(red: 1, green: 0.25, blue: 0.3, alpha: 0.45)
                }
            }
            // Touches on the map itself do nothing.
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where touchController.role(of: touch) == .joystick {
            updateJoystick(with: touch)
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

    private func isInSteeringZone(_ touch: UITouch) -> Bool {
        guard let cameraNode else { return false }
        let location = touch.location(in: cameraNode)
        let dx = location.x - joystickCenter.x
        let dy = location.y - joystickCenter.y
        return dx * dx + dy * dy <= steeringZoneRadius * steeringZoneRadius
    }

    private func isInFireZone(_ touch: UITouch) -> Bool {
        guard let cameraNode else { return false }
        let location = touch.location(in: cameraNode)
        let dx = location.x - fireButtonCenter.x
        let dy = location.y - fireButtonCenter.y
        return dx * dx + dy * dy <= fireZoneRadius * fireZoneRadius
    }

    /// Console-style stick: direction = finger offset from the base center,
    /// speed scales with deflection (full player speed at the rim).
    private func updateJoystick(with touch: UITouch) {
        guard let world, let cameraNode else { return }
        let location = touch.location(in: cameraNode)
        var dx = location.x - joystickCenter.x
        var dy = location.y - joystickCenter.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance > joystickRadius, distance > 0 {
            dx *= joystickRadius / distance
            dy *= joystickRadius / distance
        }
        joystickKnob?.position = CGPoint(x: dx, y: dy)

        let deflection = min(1, distance / joystickRadius)
        if deflection > 0.08, distance > 0 {
            let direction = Vector2(dx, dy).normalized
            world.playerControlVelocity = direction * (world.playerSpeed * deflection)
        } else {
            world.playerControlVelocity = nil // dead zone
        }
    }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            switch touchController.ended(touch) {
            case .joystick:
                world?.playerControlVelocity = nil
                joystickKnob?.position = .zero
            case .fire:
                fireButtonHeld = false
                fireButton?.fillColor = SKColor(red: 1, green: 0.25, blue: 0.3, alpha: 0.22)
            case nil:
                break
            }
        }
    }

    // MARK: - Laser

    private func processLaser() {
        guard let world else { return }
        // The beam fires along the player's current facing (the aim line the
        // joystick steers) — the fire button has no direction of its own.
        let facing = playerNode.map { Vector2(cos(Double($0.zRotation)), sin(Double($0.zRotation))) }
        guard laserCharge > 0, fireButtonHeld, let facing,
              let player = world.playerID.flatMap({ world.body(withID: $0) }),
              let beam = world.castLaserPath(through: player.position + facing * 100),
              let endPoint = beam.points.last, beam.points.count >= 2 else {
            fadeOutBeamIfNeeded()
            return
        }

        // Polyline through every bounce point to the final hit / bounds exit.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: beam.points[0].x, y: beam.points[0].y))
        for point in beam.points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        laserNode?.path = path
        sparkNode?.position = CGPoint(x: endPoint.x, y: endPoint.y)
        showBeamNodes()

        if let victimID = beam.bodyID {
            if victimID == world.playerID {
                // A reflected beam looped back into the player: self-hit.
                killPlayer()
            } else if world.body(withID: victimID)?.kind.isHostile == true {
                kill(npcID: victimID, at: endPoint)
            }
            // Rocks just absorb the beam.
        }

        // The beam rendered this frame, so it drains the battery. This runs
        // after the kill so a last-kill-on-last-drop tie counts as a win.
        // An empty battery is NOT game over: the laser just can't fire until
        // the player collects a dropped spare battery.
        laserCharge = max(0, laserCharge - frameDt)
    }

    // MARK: - Camera

    /// The camera stays put while the player is inside the follow box, then
    /// moves just enough to keep them on its edge — clamped to the map.
    private func updateCamera() {
        guard let world, let cameraNode,
              let player = world.playerID.flatMap({ world.body(withID: $0) }) else { return }
        var cam = cameraNode.position
        let halfW = size.width / 2
        let halfH = size.height / 2
        let marginBottom = halfH // box bottom = screen center line
        let px = CGFloat(player.position.x)
        let py = CGFloat(player.position.y)
        if px > cam.x + halfW - cameraMarginX { cam.x = px - (halfW - cameraMarginX) }
        if px < cam.x - halfW + cameraMarginX { cam.x = px + (halfW - cameraMarginX) }
        if py > cam.y + halfH - cameraMarginTop { cam.y = py - (halfH - cameraMarginTop) }
        if py < cam.y - halfH + marginBottom { cam.y = py + (halfH - marginBottom) }
        cam.x = min(max(cam.x, halfW), CGFloat(world.size.x) - halfW)
        cam.y = min(max(cam.y, halfH), CGFloat(world.size.y) - halfH)
        cameraNode.position = cam
    }


    private func isOnScreen(position: Vector2, radius: Double) -> Bool {
        guard let cameraNode else { return false }
        return abs(position.x - cameraNode.position.x) <= size.width / 2 + radius
            && abs(position.y - cameraNode.position.y) <= size.height / 2 + radius
    }

    // MARK: - Enemies

    /// Shooters aim while they're on screen AND have line of sight; after the
    /// telegraph they fire the killing shot. Losing sight resets the aim.
    private func processShooters(_ currentTime: TimeInterval) {
        guard let world else { return }
        guard gameStarted, let pid = world.playerID,
              let player = world.body(withID: pid) else {
            for node in shooterAimNodes.values { node.isHidden = true }
            return
        }
        for body in world.bodies where body.kind == .shooter {
            let aimNode = shooterAimNodes[body.id]
            let exposed = isOnScreen(position: body.position, radius: body.radius)
                && world.hasLineOfSight(from: body.id, to: pid)
            guard exposed else {
                shooterAimStart[body.id] = nil
                aimNode?.isHidden = true
                continue
            }

            let start = shooterAimStart[body.id] ?? currentTime
            shooterAimStart[body.id] = start

            let path = CGMutablePath()
            path.move(to: CGPoint(x: body.position.x, y: body.position.y))
            path.addLine(to: CGPoint(x: player.position.x, y: player.position.y))
            aimNode?.path = path
            aimNode?.isHidden = false

            if currentTime - start >= telegraphDuration {
                fireShooterBeam(from: body.position, to: player.position)
                killPlayer()
                return
            }
        }
    }

    /// The lethal green flash a shooter leaves on screen when it fires.
    private func fireShooterBeam(from: Vector2, to: Vector2) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: from.x, y: from.y))
        path.addLine(to: CGPoint(x: to.x, y: to.y))
        let beam = SKShapeNode(path: path)
        beam.strokeColor = SKColor(red: 0.25, green: 1, blue: 0.4, alpha: 1)
        beam.lineWidth = 2.5
        beam.glowWidth = 4
        beam.zPosition = 1.5
        addChild(beam)
        beam.run(.sequence([
            .wait(forDuration: 0.15),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
        ]))
    }

    private func checkRunnerTouches() {
        guard gameStarted, let world, let pid = world.playerID,
              let player = world.body(withID: pid) else { return }
        for body in world.bodies where body.kind == .runner {
            if body.position.distance(to: player.position) <= body.radius + player.radius + 0.5 {
                killPlayer()
                return
            }
        }
    }

    /// Shared death path: shooter hit, runner touch, or reflected self-hit.
    private func killPlayer() {
        guard gameStarted, let world, let pid = world.playerID else { return }
        gameStarted = false
        world.remove(bodyID: pid) // runners stand down without a target
        fireButtonHeld = false
        fadeOutBeamIfNeeded()
        for node in shooterAimNodes.values { node.isHidden = true }
        if let node = playerNode {
            node.run(.sequence([
                .group([
                    .scale(to: 1.6, duration: 0.2),
                    .fadeOut(withDuration: 0.2),
                ]),
                .removeFromParent(),
            ]))
            playerNode = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.onPlayerKilled?()
        }
    }

    // MARK: - Battery pickups

    private func spawnBatteryPickup(at position: Vector2) {
        let node = SKShapeNode(rectOf: CGSize(width: 12, height: 18), cornerRadius: 3)
        node.fillColor = SKColor(red: 0.25, green: 0.9, blue: 0.4, alpha: 0.95)
        node.strokeColor = .white
        node.lineWidth = 1
        node.glowWidth = 3
        node.zPosition = 0.5
        node.position = CGPoint(x: position.x, y: position.y)
        node.run(.repeatForever(.sequence([
            .scale(to: 1.15, duration: 0.4),
            .scale(to: 0.9, duration: 0.4),
        ])))
        addChild(node)
        batteryPickups.append((node.position, node))
    }

    private func checkBatteryPickups() {
        guard gameStarted, let world, let pid = world.playerID,
              let player = world.body(withID: pid) else { return }
        batteryPickups.removeAll { pickup in
            let distance = player.position.distance(to: Vector2(pickup.position.x, pickup.position.y))
            guard distance <= player.radius + 14 else { return false }
            laserCharge = laserCapacity // full recharge
            pickup.node.run(.sequence([
                .group([
                    .scale(to: 1.8, duration: 0.2),
                    .fadeOut(withDuration: 0.2),
                ]),
                .removeFromParent(),
            ]))
            return true
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
        let dropPosition = world?.body(withID: npcID)?.position
        world?.remove(bodyID: npcID)

        // Same impact spark as at the world's edge, as a short burst — the NPC
        // is gone instantly, so the spark lives just long enough to register.
        let burst = makeSparkNode()
        burst.position = CGPoint(x: hitPoint.x, y: hitPoint.y)
        addChild(burst)
        burst.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))

        // Battery carriers leave a spare battery where they fell.
        if batteryCarrierIDs.remove(npcID) != nil, let dropPosition {
            spawnBatteryPickup(at: dropPosition)
        }
        shooterAimStart[npcID] = nil
        shooterAimNodes.removeValue(forKey: npcID)?.removeFromParent()

        if let node = npcNodes.removeValue(forKey: npcID) {
            node.run(.sequence([
                .group([
                    .scale(to: 1.6, duration: 0.15),
                    .fadeOut(withDuration: 0.15),
                ]),
                .removeFromParent(),
            ]))
        }

        // Last one? Let the death animation play, then report the win.
        if world?.bodies.contains(where: { $0.kind.isHostile }) == false {
            gameStarted = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.onAllNPCsEliminated?()
            }
        }
    }
}
