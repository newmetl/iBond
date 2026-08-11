import SpriteKit
import GameEngine

/// How the player steers and fires. Selected in the config menu (gear icon);
/// applied when the next game starts.
enum ControlScheme: String {
    /// Virtual joystick (lower-left) + fire button (lower-right).
    case joystick
    /// No on-screen controls: single tap walks to the tapped position,
    /// double tap fires a burst at it, double tap + hold keeps firing at
    /// the finger.
    case tap
    /// Joystick (lower-left) steers; no fire button — a single tap anywhere
    /// else fires a burst at the tapped position, tap + hold keeps firing
    /// at the finger.
    case stickAndTap
}

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
    /// Designated carriers and what they drop (shooters→red, hunters→orange).
    private var batteryCarriers: [BodyID: BatteryType] = [:]
    private var batteryPickups: [(position: CGPoint, node: SKShapeNode, type: BatteryType)] = []

    private var lastUpdateTime: TimeInterval?
    private var accumulator: Double = 0
    private let fixedStep: Double = 1.0 / 120.0

    private let playerRadius: Double = 16
    private let npcRadius: Double = 14

    /// Everything level-dependent (map scale, enemy counts, obstacles,
    /// batteries, spawn distances) lives in the level table: Levels.swift.
    private var level = 1
    private var config = LevelConfig.forLevel(1)
    /// Decorative litter density is constant per screen of map area
    /// (about 200 pieces on the original 3×3 map).
    private let litterPerScreen = 22

    /// Virtual joystick (in the control strip, left): knob travel radius and
    /// touch-capture zone.
    private let joystickRadius: CGFloat = 70
    private let steeringZoneRadius: CGFloat = 120

    /// Fire button (control strip, right; classic joystick scheme only):
    /// tap = burst, hold = continuous. The beam fires along the player's
    /// current facing.
    private let fireButtonRadius: CGFloat = 44
    private let fireZoneRadius: CGFloat = 100

    /// Both stick schemes reserve an opaque strip at the bottom of the screen
    /// for the controls; the visible play area is everything above it. The
    /// pure tap scheme has no on-screen controls and keeps the full screen.
    private var controlStripHeight: CGFloat {
        controlScheme == .tap ? 0 : min(190, size.height * 0.24)
    }
    private var controlPanel: SKSpriteNode?
    private var controlPanelSeparator: SKSpriteNode?

    private let mirrorHalfLength: Double = 70

    /// Hunter (patrolling shooter): ambles until it notices the player, then
    /// loops run-closer → aim at a locked point → shoot. The locked aim makes
    /// the shot dodgeable. Approach/aim speeds are per-body (tiers, boss);
    /// only the shared bits live here.
    private let hunterPatrolSpeed: Double = 55
    private let hunterApproachDuration: TimeInterval = 0.6

    private enum HunterMode {
        case patrol(direction: Vector2, until: TimeInterval)
        case approach(until: TimeInterval)
        case aim(target: Vector2, start: TimeInterval)
    }
    private var hunterModes: [BodyID: HunterMode] = [:]
    private var hunterAimNodes: [BodyID: SKShapeNode] = [:]

    /// Per-enemy tier attributes, assigned at spawn (see EnemyTiers/BossStats).
    /// Shields are seconds-of-red-beam; damage accumulates as
    /// frameDt × battery power and the enemy dies at shield ≤ damage.
    private var shieldSeconds: [BodyID: Double] = [:]
    private var enemyDamage: [BodyID: Double] = [:]
    private var enemyBaseColors: [BodyID: (r: CGFloat, g: CGFloat, b: CGFloat)] = [:]
    private var shooterAimDurations: [BodyID: Double] = [:]
    private var hunterApproachSpeeds: [BodyID: Double] = [:]
    private var hunterAimDurations: [BodyID: Double] = [:]
    private var hunterPatrolSpeeds: [BodyID: Double] = [:]
    private var enemyTierIndex: [BodyID: Int] = [:]
    private var bossIDs: Set<BodyID> = []
    /// Enemies the player has had on screen at least once (one-way, like
    /// runner activation). Only seen enemies can be damaged — blind-firing
    /// across the map must not farm kills.
    private var seenEnemyIDs: Set<BodyID> = []

    private let touchController = TouchController()
    private var fireButtonHeld = false

    /// Set by GameView before startGame; never changes mid-game.
    var controlScheme: ControlScheme = .joystick
    /// Tap scheme state: the finger that double-tapped (nil when not held),
    /// where it is, and the end of the minimum burst window — a quick
    /// double-tap fires for at least this long even if released instantly.
    private var fireTouch: UITouch?
    private var fireTarget: CGPoint = .zero
    private var burstEndTime: TimeInterval = 0
    private let tapBurstDuration: TimeInterval = 0.2
    private var laserNode: SKShapeNode?
    private var sparkNode: SKShapeNode?

    /// Laser batteries: one additive reserve (seconds of firing time) per
    /// type — every pickup ADDS its capacity to that type's pool, nothing is
    /// overwritten. `batteryType` is the currently selected laser; it drains
    /// only while the beam is actually rendering. When the selected pool runs
    /// dry the laser auto-switches to the next type with charge (red →
    /// orange → white); the strip buttons switch manually.
    private var batteryType: BatteryType = .red
    private var batteryReserves: [BatteryType: Double] = [:]
    private var currentReserve: Double { batteryReserves[batteryType] ?? 0 }
    private var batteryButtons: [BatteryType: SKShapeNode] = [:]
    private var batteryButtonFills: [BatteryType: SKSpriteNode] = [:]
    private var batteryButtonLabels: [BatteryType: SKLabelNode] = [:]

    /// Player shields: armor rings exactly like the enemies wear. Each ring
    /// absorbs one ENEMY LASER hit (shooter or hunter shot) and vanishes;
    /// runner/boss touch and the player's own reflected beam ignore shields.
    /// Pickups appear only on levels that field shielded regular enemies
    /// (tier II+); the player stacks at most three.
    private let maxPlayerShields = 3
    private var playerShields = 0
    private var shieldPickups: [(position: CGPoint, node: SKShapeNode)] = []
    private var shieldCarriers: Set<BodyID> = []

    /// Fortress levels (every level ending in 5): a rock ring with one
    /// entrance holds every enemy; crossing it springs the trap.
    private var fortressCenter: Vector2?
    private var fortressRadius: Double = 0
    private var fortressBreached = false
    private var batteryHUDNode: SKNode?
    private var enemyDotsNode: SKNode?
    private var lastEnemyDotIDs: Set<BodyID> = []
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
        layoutControlPanel()
    }

    /// Sizes and positions the control strip's backdrop + separator line.
    private func layoutControlPanel() {
        controlPanel?.size = CGSize(width: size.width, height: controlStripHeight)
        controlPanel?.position = CGPoint(x: 0, y: -size.height / 2 + controlStripHeight / 2)
        controlPanelSeparator?.size = CGSize(width: size.width, height: 1.5)
        controlPanelSeparator?.position = CGPoint(x: 0, y: -size.height / 2 + controlStripHeight)
        layoutBatteryButtons()
    }

    private let batteryButtonSize = CGSize(width: 92, height: 44)

    /// The type buttons stack red-top → white-bottom on the strip's right; the
    /// classic scheme shifts them left to clear the fire button.
    private func layoutBatteryButtons() {
        let x = controlScheme == .joystick
            ? size.width / 2 - 70 - fireButtonRadius - batteryButtonSize.width / 2 - 14
            : size.width / 2 - 70
        let centerY = -size.height / 2 + controlStripHeight * 0.5
        for type in BatteryType.allCases {
            let slot = CGFloat(1 - type.rawValue) // red +1, orange 0, white -1
            batteryButtons[type]?.position = CGPoint(x: x, y: centerY + slot * 56)
        }
    }

    /// The battery type whose visible button contains the touch, if any.
    private func batteryButtonHit(_ touch: UITouch) -> BatteryType? {
        guard let cameraNode else { return nil }
        let location = touch.location(in: cameraNode)
        for type in BatteryType.allCases {
            guard let button = batteryButtons[type], !button.isHidden else { continue }
            // A little touch padding beyond the drawn rect.
            if abs(location.x - button.position.x) <= batteryButtonSize.width / 2 + 8,
               abs(location.y - button.position.y) <= batteryButtonSize.height / 2 + 8 {
                return type
            }
        }
        return nil
    }

    /// Joystick base center in camera coordinates: left half of the control
    /// strip, pulled in from the screen edge (80pt from the corner felt too
    /// close) and vertically centered in the strip.
    private var joystickCenter: CGPoint {
        CGPoint(x: -size.width / 2 + 130,
                y: -size.height / 2 + controlStripHeight * 0.5)
    }

    /// Fire button center in camera coordinates: right side of the strip.
    private var fireButtonCenter: CGPoint {
        CGPoint(x: size.width / 2 - 70,
                y: -size.height / 2 + controlStripHeight * 0.5)
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
        registerVisibleEnemies()
        checkFortressBreach()
        processLaser()
        processShooters(currentTime)
        processHunters(currentTime)
        checkTouchKills()
        checkBatteryPickups()
        checkShieldPickups()
        updateBatteryHUD()
        updateEnemyDots()
        updateSounds()
    }

    /// Toggles the looped audio layers to match this frame's state.
    private func updateSounds() {
        let sound = SoundManager.shared
        sound.setLaserFiring(beamVisible)
        let hunterAiming = hunterModes.values.contains {
            if case .aim = $0 { return true } else { return false }
        }
        sound.setShooterAiming(gameStarted && (!shooterAimStart.isEmpty || hunterAiming))
        let chasing = gameStarted && world.map { w in
            w.bodies.contains { $0.kind == .runner && w.activeRunnerIDs.contains($0.id) }
        } == true
        sound.setRunnersChasing(chasing)
    }

    /// One sweep over the hostiles currently on screen: marks them as seen
    /// (only seen enemies are damageable) and activates runners. Runners wait
    /// in ambush until they first scroll into view, then chase forever —
    /// without that, every runner would converge on spawn.
    private func registerVisibleEnemies() {
        guard gameStarted, let world else { return }
        for body in world.bodies
        where body.kind.isHostile
            && isOnScreen(position: body.position, radius: body.radius) {
            seenEnemyIDs.insert(body.id)
            if body.kind == .runner, !world.activeRunnerIDs.contains(body.id) {
                world.activateRunner(body.id)
            }
        }
    }

    /// Fortress levels: stepping through the entrance springs the trap —
    /// every enemy notices the player at once. Runners give chase, hunters
    /// charge (processHunters treats them as permanently noticed), shooters
    /// wake for damage purposes. One-way, like runner activation.
    private func checkFortressBreach() {
        guard gameStarted, !fortressBreached, let world,
              let center = fortressCenter,
              let player = world.playerID.flatMap({ world.body(withID: $0) }),
              player.position.distance(to: center) < fortressRadius - 45 else { return }
        fortressBreached = true
        let now = lastUpdateTime ?? 0
        for body in world.bodies where body.kind.isHostile {
            seenEnemyIDs.insert(body.id)
            if body.kind == .runner, !world.activeRunnerIDs.contains(body.id) {
                world.activateRunner(body.id)
            }
            if body.kind == .hunter {
                hunterModes[body.id] = .approach(until: now + hunterApproachDuration)
            }
        }
    }

    // MARK: - World setup

    /// Starts a fresh game on the given level: tears down any previous
    /// world/nodes and builds a new one (player centered, NPCs re-randomized).
    /// Called from the menu / continue / restart overlay.
    ///
    /// `carryOver` (level finished → next level) keeps the battery reserves
    /// and shields; red is topped up to at least one full capacity — 3s of
    /// red laser is the guaranteed minimum every level starts with. Without
    /// carry-over (menu, death, dev picks) everything resets to exactly that.
    func startGame(level: Int, carryOver: Bool = false) {
        self.level = level
        config = LevelConfig.forLevel(level)
        removeAllChildren()
        camera = nil
        cameraNode = nil
        world = nil
        playerNode = nil
        npcNodes = [:]
        joystickBase = nil
        joystickKnob = nil
        fireButton = nil
        controlPanel = nil
        controlPanelSeparator = nil
        lastPlayerPosition = nil
        laserNode = nil
        sparkNode = nil
        fireButtonHeld = false
        fireTouch = nil
        burstEndTime = 0
        batteryHUDNode = nil
        enemyDotsNode = nil
        lastEnemyDotIDs = []
        if carryOver {
            batteryReserves[.red] = max(batteryReserves[.red] ?? 0,
                                        BatteryType.red.capacity)
            if currentReserve <= 0 { batteryType = .red }
        } else {
            batteryType = .red
            batteryReserves = [.red: BatteryType.red.capacity]
        }
        batteryButtons = [:]
        batteryButtonFills = [:]
        batteryButtonLabels = [:]
        beamVisible = false
        shooterAimStart = [:]
        shooterAimNodes = [:]
        hunterModes = [:]
        hunterAimNodes = [:]
        shieldSeconds = [:]
        enemyDamage = [:]
        enemyBaseColors = [:]
        shooterAimDurations = [:]
        hunterApproachSpeeds = [:]
        hunterAimDurations = [:]
        hunterPatrolSpeeds = [:]
        enemyTierIndex = [:]
        bossIDs = []
        seenEnemyIDs = []
        batteryCarriers = [:]
        batteryPickups = []
        if !carryOver { playerShields = 0 }
        shieldPickups = []
        shieldCarriers = []
        fortressCenter = nil
        fortressRadius = 0
        fortressBreached = false
        gameStarted = true
        SoundManager.shared.startMusic()
        ensureWorld() // builds now if the scene is laid out; else on next update
    }

    /// The scene's size is zero until SpriteView lays it out, so the world is
    /// created lazily on the first sized update after the game starts.
    private func ensureWorld() {
        guard gameStarted, world == nil, size.width > 0, size.height > 0 else { return }
        let mapSize = Vector2(size.width * config.mapScale, size.height * config.mapScale)
        let world = World(size: mapSize)
        var rng = SystemRandomNumberGenerator()

        // Fortress levels: a rock ring at the map center with one entrance
        // opening along the map's LONG axis; the player starts outside,
        // in front of the entrance, and every enemy waits inside.
        let center = mapSize * 0.5
        let ringRadius = min(mapSize.x, mapSize.y) * 0.30
        let entranceDir: Vector2 = mapSize.y >= mapSize.x ? Vector2(0, -1) : Vector2(-1, 0)
        let wallRockRadius = 40.0
        let playerStart: Vector2
        if config.fortress {
            fortressCenter = center
            fortressRadius = ringRadius
            playerStart = center + entranceDir * (ringRadius + 280)
        } else {
            playerStart = center
        }
        world.addPlayer(at: playerStart, radius: playerRadius)
        world.runnerSpeed = EnemyTiers.runnerSpeed[0]

        if config.fortress {
            // Wall rocks overlap slightly (spacing 1.5×radius) so the ring
            // is beam- and body-tight everywhere except the entrance gap.
            let entranceAngle = atan2(entranceDir.y, entranceDir.x)
            let gapHalfAngle = (60.0 + wallRockRadius) / ringRadius
            let count = Int(2 * Double.pi * ringRadius / (wallRockRadius * 1.5))
            for i in 0..<count {
                let angle = Double(i) / Double(count) * 2 * .pi
                var diff = angle - entranceAngle
                while diff > .pi { diff -= 2 * .pi }
                while diff < -.pi { diff += 2 * .pi }
                guard abs(diff) >= gapHalfAngle else { continue }
                world.addRock(at: center + Vector2(cos(angle), sin(angle)) * ringRadius,
                              radius: wallRockRadius)
            }
        }
        /// A free spot inside the fortress ring (engine-checked against
        /// bodies; run before the wall's interior fills up).
        func fortressInteriorPosition(radius: Double) -> Vector2? {
            let reach = ringRadius - wallRockRadius - radius - 20
            for _ in 0..<80 {
                let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                let dist = Double.random(in: 0...max(1, reach), using: &rng)
                let candidate = center + Vector2(cos(angle), sin(angle)) * dist
                if world.bodies.allSatisfy({
                    $0.position.distance(to: candidate) >= $0.radius + radius + 6
                }) {
                    return candidate
                }
            }
            return nil
        }
        // Keep the entrance corridor clear of random obstacles — a rock or
        // mirror in the gap would seal the only way in.
        let entranceMid = center + entranceDir * ringRadius
        func blocksEntrance(_ position: Vector2) -> Bool {
            config.fortress && position.distance(to: entranceMid) < 180
        }

        // Mirrors first, then rocks, then enemies — each placement pass avoids
        // everything placed before it (spawn sampling checks bodies + mirrors).
        let inset = 120.0
        let field = Rect(min: Vector2(inset, inset),
                         max: Vector2(mapSize.x - inset, mapSize.y - inset))
        for _ in 0..<config.mirrorCount {
            guard let mirrorCenter = world.randomFreePosition(radius: mirrorHalfLength + 10,
                                                              in: field, using: &rng),
                  !blocksEntrance(mirrorCenter) else { continue }
            let angle = Double.random(in: 0..<Double.pi, using: &rng)
            let along = Vector2(cos(angle), sin(angle)) * mirrorHalfLength
            world.addMirror(from: mirrorCenter - along, to: mirrorCenter + along)
        }
        for _ in 0..<config.rockCount {
            let radius = Double.random(in: 38...56, using: &rng)
            guard let position = world.randomFreePosition(radius: radius, in: field,
                                                          using: &rng),
                  !blocksEntrance(position) else { continue }
            world.addRock(at: position, radius: radius)
        }

        // Player shields arrive with the first shielded REGULAR enemies
        // (tier II+, level 31 on): two lie on the map, two ride designated
        // armored carriers and drop where they die.
        let shieldedRegulars = config.runners.dropFirst().reduce(0, +)
            + config.shooters.dropFirst().reduce(0, +)
            + config.hunters.dropFirst().reduce(0, +)
        var shieldCarriersLeft = shieldedRegulars > 0 ? 2 : 0

        // Shooters lurk right next to cover — rocks normally; on the
        // all-mirror levels (no rocks at all) they tuck in beside mirror
        // midpoints instead (mirrors block line of sight, so the hidden
        // check below still works). Never near the player's spawn. The
        // first `shooterRedCarriers` carry Red batteries.
        let rocks = world.rockIDs.compactMap { world.body(withID: $0) }
        let coverSpots: [(position: Vector2, radius: Double)] = rocks.isEmpty
            ? world.mirrors.map { (($0.start + $0.end) * 0.5, 12.0) }
            : rocks.map { ($0.position, $0.radius) }
        var shooterCarriersLeft = config.shooterRedCarriers
        for (tier, count) in config.shooters.enumerated() {
            var placed = 0
            var attempts = 0
            while placed < count, attempts < 300 {
                attempts += 1
                let candidate: Vector2
                if config.fortress {
                    // Fortress: shooters wait anywhere inside the ring — the
                    // wall itself is their cover.
                    guard let inside = fortressInteriorPosition(radius: npcRadius) else { continue }
                    candidate = inside
                } else {
                    guard let cover = coverSpots.randomElement(using: &rng) else { break }
                    let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                    let dist = cover.radius + npcRadius + Double.random(in: 4...26, using: &rng)
                    candidate = cover.position + Vector2(cos(angle), sin(angle)) * dist
                    guard candidate.x > 20, candidate.x < mapSize.x - 20,
                          candidate.y > 20, candidate.y < mapSize.y - 20,
                          candidate.distance(to: playerStart) > config.shooterMinPlayerDistance,
                          world.bodies.allSatisfy({ $0.position.distance(to: candidate) >= $0.radius + npcRadius + 6 })
                    else { continue }
                }
                let id = world.addShooter(at: candidate, radius: npcRadius)
                // "Behind these obstacles": a shooter must start HIDDEN —
                // reject spots with a clear line to the player's spawn.
                if !config.fortress, let pid = world.playerID,
                   world.hasLineOfSight(from: id, to: pid) {
                    world.remove(bodyID: id)
                    continue
                }
                shooterAimDurations[id] = EnemyTiers.shooterAim[tier]
                shieldSeconds[id] = EnemyTiers.shooterShield[tier]
                enemyTierIndex[id] = tier
                if shooterCarriersLeft > 0 {
                    batteryCarriers[id] = .red
                    shooterCarriersLeft -= 1
                }
                if tier >= 1, shieldCarriersLeft > 0 {
                    shieldCarriers.insert(id)
                    shieldCarriersLeft -= 1
                }
                placed += 1
            }
        }

        for (tier, count) in config.runners.enumerated() {
            var placed = 0
            var attempts = 0
            while placed < count, attempts < 300 {
                attempts += 1
                let position: Vector2
                if config.fortress {
                    guard let inside = fortressInteriorPosition(radius: npcRadius) else { continue }
                    position = inside
                } else {
                    guard let free = world.randomFreePosition(radius: npcRadius, using: &rng),
                          free.distance(to: playerStart) > config.runnerMinPlayerDistance else { continue }
                    position = free
                }
                let id = world.addRunner(at: position, radius: npcRadius)
                world.runnerSpeedOverrides[id] = EnemyTiers.runnerSpeed[tier]
                shieldSeconds[id] = EnemyTiers.runnerShield[tier]
                enemyTierIndex[id] = tier
                if tier >= 1, shieldCarriersLeft > 0 {
                    shieldCarriers.insert(id)
                    shieldCarriersLeft -= 1
                }
                placed += 1
            }
        }

        // Hunters patrol from anywhere runner-distance away from the spawn.
        // The first `hunterOrangeCarriers` carry Orange batteries.
        var hunterCarriersLeft = config.hunterOrangeCarriers
        for (tier, count) in config.hunters.enumerated() {
            var placed = 0
            var attempts = 0
            while placed < count, attempts < 300 {
                attempts += 1
                let position: Vector2
                if config.fortress {
                    guard let inside = fortressInteriorPosition(radius: npcRadius) else { continue }
                    position = inside
                } else {
                    guard let free = world.randomFreePosition(radius: npcRadius, using: &rng),
                          free.distance(to: playerStart) > config.runnerMinPlayerDistance else { continue }
                    position = free
                }
                let id = world.addHunter(at: position, radius: npcRadius)
                hunterApproachSpeeds[id] = EnemyTiers.hunterApproach[tier]
                hunterAimDurations[id] = EnemyTiers.hunterAim[tier]
                shieldSeconds[id] = EnemyTiers.hunterShield[tier]
                enemyTierIndex[id] = tier
                if hunterCarriersLeft > 0 {
                    batteryCarriers[id] = .orange
                    hunterCarriersLeft -= 1
                }
                if tier >= 1, shieldCarriersLeft > 0 {
                    shieldCarriers.insert(id)
                    shieldCarriersLeft -= 1
                }
                placed += 1
            }
        }

        // Bosses: huge versions of regular kinds; behavior follows the kind.
        for spec in config.bosses {
            var placed = false
            var bossAttempts = 0
            while !placed, bossAttempts < 300 {
                bossAttempts += 1
                let position: Vector2
                if config.fortress {
                    guard let inside = fortressInteriorPosition(radius: BossStats.radius) else { continue }
                    position = inside
                } else {
                    guard let free = world.randomFreePosition(radius: BossStats.radius, using: &rng),
                          free.distance(to: playerStart) > config.runnerMinPlayerDistance else { continue }
                    position = free
                }
                let id: BodyID
                switch spec.kind {
                case .runner:
                    id = world.addRunner(at: position, radius: BossStats.radius,
                                         mass: BossStats.mass)
                    world.runnerSpeedOverrides[id] = BossStats.runnerSpeed(tier: spec.tier)
                case .shooter:
                    id = world.addShooter(at: position, radius: BossStats.radius,
                                          mass: BossStats.mass)
                    shooterAimDurations[id] = BossStats.shooterAim(tier: spec.tier)
                case .hunter:
                    id = world.addHunter(at: position, radius: BossStats.radius,
                                         mass: BossStats.mass)
                    hunterPatrolSpeeds[id] = BossStats.patrolSpeed
                    hunterApproachSpeeds[id] = BossStats.hunterApproach(tier: spec.tier)
                    hunterAimDurations[id] = BossStats.hunterAim(tier: spec.tier)
                }
                shieldSeconds[id] = spec.shield
                enemyTierIndex[id] = spec.tier
                bossIDs.insert(id)
                placed = true
            }
        }

        self.world = world
        buildNodes(for: world)
        updatePlayerShieldRings() // carried-over shields show from frame one

        // Typed map spares, never right next to the spawn.
        for (type, count) in [(BatteryType.red, config.redSpares),
                              (.orange, config.orangeSpares),
                              (.white, config.whiteSpares)] {
            var placed = 0
            var attempts = 0
            while placed < count, attempts < 200 {
                attempts += 1
                guard let position = world.randomFreePosition(radius: 12, using: &rng),
                      position.distance(to: playerStart) > 150 else { continue }
                spawnBatteryPickup(at: position, type: type)
                placed += 1
            }
        }

        // Map-spare shields, same placement rules as batteries.
        if shieldedRegulars > 0 {
            var placed = 0
            var attempts = 0
            while placed < 2, attempts < 200 {
                attempts += 1
                guard let position = world.randomFreePosition(radius: 12, using: &rng),
                      position.distance(to: playerStart) > 150 else { continue }
                spawnShieldPickup(at: position)
                placed += 1
            }
        }
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
        let litterCount = Int(Double(litterPerScreen) * Double(config.mapScale * config.mapScale))
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
        // Shield rings — the same look as enemy armor; one lights up per
        // collected shield (innermost first), see updatePlayerShieldRings.
        for ring in 0..<maxPlayerShields {
            let armor = SKShapeNode(circleOfRadius: playerRadius + 4 + CGFloat(ring) * 4)
            armor.name = "playerShield\(ring)"
            armor.strokeColor = SKColor(white: 0.95, alpha: 0.75)
            armor.lineWidth = 1.5
            armor.fillColor = .clear
            armor.isHidden = true
            player.addChild(armor)
        }
        addChild(player)
        playerNode = player

        for body in world.bodies where body.kind.isHostile {
            let rgb = enemyColor(for: body)
            enemyBaseColors[body.id] = rgb
            let node = makeCircleNode(radius: body.radius,
                                      fill: SKColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1))
            node.zPosition = 0
            // Facing line: shows where the enemy aims (shooter) or runs (runner).
            let facingPath = CGMutablePath()
            facingPath.move(to: .zero)
            facingPath.addLine(to: CGPoint(x: body.radius * 1.7, y: 0))
            let facingLine = SKShapeNode(path: facingPath)
            facingLine.strokeColor = SKColor(white: 1, alpha: 0.7)
            facingLine.lineWidth = 1.5
            node.addChild(facingLine)
            // Version cues that scale with toughness: heavier outline per
            // tier (tier III glows), plus concentric armor rings — one for
            // tier II, two for tier III, three for the boss — that fade as
            // the shield burns (see applyLaserDamage).
            let tier = min(max(enemyTierIndex[body.id] ?? 0, 0), 2)
            node.lineWidth = 1.5 + CGFloat(tier)
            if tier >= 2 { node.glowWidth = 2 }
            let ringCount = bossIDs.contains(body.id) ? 3 : tier
            for ring in 0..<ringCount {
                let armor = SKShapeNode(circleOfRadius: body.radius + 4 + CGFloat(ring) * 4)
                armor.name = "armorRing\(ring)" // index 0 = innermost
                armor.strokeColor = SKColor(white: 0.95, alpha: 0.75)
                armor.lineWidth = 1.5
                armor.fillColor = .clear
                node.addChild(armor)
            }
            addChild(node)
            npcNodes[body.id] = node
        }

        for body in world.bodies where body.kind == .shooter {
            let aim = SKShapeNode()
            aim.strokeColor = SKColor(red: 0.3, green: 1, blue: 0.4, alpha: 0.3)
            aim.lineWidth = 1
            aim.isHidden = true
            aim.zPosition = -0.5
            addChild(aim)
            shooterAimNodes[body.id] = aim
        }

        // Hunter telegraphs: an orange line locked to the aimed point.
        for body in world.bodies where body.kind == .hunter {
            let aim = SKShapeNode()
            aim.strokeColor = SKColor(red: 1, green: 0.7, blue: 0.25, alpha: 0.4)
            aim.lineWidth = 1
            aim.isHidden = true
            aim.zPosition = -0.5
            addChild(aim)
            hunterAimNodes[body.id] = aim
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

        // The joystick exists in every scheme except pure tap; the fire
        // button only in the classic joystick scheme.
        if controlScheme != .tap {
            // Opaque strip along the bottom: the controls' home, visually
            // separated from the (reduced) play area above it.
            let panel = SKSpriteNode(color: SKColor(red: 0.07, green: 0.07, blue: 0.12, alpha: 1),
                                     size: .zero)
            panel.zPosition = 2.9 // over every world node, under the HUD tier
            camera.addChild(panel)
            controlPanel = panel

            let separator = SKSpriteNode(color: SKColor(white: 1, alpha: 0.22), size: .zero)
            separator.zPosition = 2.9
            camera.addChild(separator)
            controlPanelSeparator = separator
            layoutControlPanel()

            // Virtual joystick, on the strip's left half.
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

            if controlScheme == .joystick {
                // Fire button, on the strip's right side.
                let fire = SKShapeNode(circleOfRadius: fireButtonRadius)
                fire.fillColor = SKColor(red: 1, green: 0.25, blue: 0.3, alpha: 0.22)
                fire.strokeColor = SKColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.6)
                fire.lineWidth = 2
                fire.position = fireButtonCenter
                fire.zPosition = 3
                camera.addChild(fire)
                fireButton = fire
            }

            // Laser-type buttons, stacked on the strip's right (next to the
            // fire button in the classic scheme). Each is drawn AS a battery:
            // outlined body with a tip, filled to its pool's charge level in
            // the type's color, seconds on top. One per battery type; each
            // appears only while its pool has charge — see updateBatteryHUD.
            for type in BatteryType.allCases {
                let button = SKShapeNode(rectOf: batteryButtonSize, cornerRadius: 7)
                button.zPosition = 3
                button.isHidden = true
                button.fillColor = SKColor(white: 0, alpha: 0.35)
                camera.addChild(button)
                batteryButtons[type] = button

                let tip = SKShapeNode(rectOf: CGSize(width: 5, height: 16), cornerRadius: 2)
                tip.strokeColor = .clear
                tip.fillColor = SKColor(white: 1, alpha: 0.85)
                tip.position = CGPoint(x: batteryButtonSize.width / 2 + 4, y: 0)
                button.addChild(tip)

                let fill = SKSpriteNode(color: batteryColor(type), size: .zero)
                fill.anchorPoint = CGPoint(x: 0, y: 0.5)
                fill.position = CGPoint(x: -batteryButtonSize.width / 2 + 4, y: 0)
                button.addChild(fill)
                batteryButtonFills[type] = fill

                // Dark backing chip so the seconds stay readable on any fill
                // color (white text on the white battery was invisible).
                let labelBacking = SKShapeNode(rectOf: CGSize(width: 56, height: 20),
                                               cornerRadius: 6)
                labelBacking.fillColor = SKColor(white: 0, alpha: 0.45)
                labelBacking.strokeColor = .clear
                button.addChild(labelBacking)

                let label = SKLabelNode(text: "")
                label.fontName = "HelveticaNeue-Bold"
                label.fontSize = 15
                label.fontColor = SKColor(white: 1, alpha: 0.9)
                label.horizontalAlignmentMode = .center
                label.verticalAlignmentMode = .center
                button.addChild(label)
                batteryButtonLabels[type] = label
            }
            layoutBatteryButtons()
        }

        // Top HUD (rides the camera): just the current level and the enemy
        // dot row — the battery state lives on the strip buttons below.
        let hud = SKNode()
        hud.position = CGPoint(x: 0, y: size.height / 2 - 80)
        hud.zPosition = 3
        hud.alpha = 0.85
        camera.addChild(hud)
        batteryHUDNode = hud

        let levelLabel = SKLabelNode(text: level == 0 ? "TEST" : "LVL \(level)")
        levelLabel.fontName = "HelveticaNeue-Bold"
        levelLabel.fontSize = 13
        levelLabel.fontColor = SKColor(white: 1, alpha: 0.85)
        levelLabel.horizontalAlignmentMode = .center
        levelLabel.verticalAlignmentMode = .center
        levelLabel.position = .zero
        hud.addChild(levelLabel)

        // One dot per remaining enemy, in the enemy's color (see updateEnemyDots).
        let dots = SKNode()
        dots.position = CGPoint(x: 0, y: -18)
        hud.addChild(dots)
        enemyDotsNode = dots
    }

    /// Body (and HUD dot) color: each kind keeps its hue, each tier gets its
    /// own shade — dark (I) → vivid (II) → bright (III) — so versions are
    /// tellable at a glance both on the map and in the dot row. The boss has
    /// its own deep red-orange.
    private func enemyColor(for body: CircleBody) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        if bossIDs.contains(body.id) {
            // Bosses: a deep, saturated version of their kind's hue.
            switch body.kind {
            case .runner: return (0.55, 0.12, 0.85)
            case .shooter: return (0.85, 0.1, 0.15)
            default: return (0.95, 0.3, 0.1)
            }
        }
        let tier = min(max(enemyTierIndex[body.id] ?? 0, 0), 2)
        switch body.kind {
        case .runner:
            return [(0.45, 0.22, 0.62), (0.75, 0.42, 1.0), (0.95, 0.7, 1.0)][tier]
        case .hunter:
            return [(0.6, 0.35, 0.06), (1.0, 0.62, 0.15), (1.0, 0.85, 0.35)][tier]
        default: // shooters (and legacy npc)
            return [(0.62, 0.22, 0.16), (1.0, 0.45, 0.35), (1.0, 0.7, 0.6)][tier]
        }
    }

    /// Rebuilds the HUD dot row whenever the set of living enemies changes.
    /// Each dot wears its enemy's actual body color (shooter red, boss
    /// deep red-orange and larger, hunter orange, runner purple), grouped
    /// shooters → boss → hunters → runners.
    private func updateEnemyDots() {
        guard let world, let enemyDotsNode else { return }
        let hostiles = world.bodies.filter { $0.kind.isHostile }
        let ids = Set(hostiles.map(\.id))
        guard ids != lastEnemyDotIDs else { return }
        lastEnemyDotIDs = ids

        enemyDotsNode.removeAllChildren()
        guard !hostiles.isEmpty else { return }
        func rank(_ body: CircleBody) -> Int {
            if bossIDs.contains(body.id) { return 1 }
            switch body.kind {
            case .shooter: return 0
            case .hunter: return 2
            default: return 3
            }
        }
        let sorted = hostiles.sorted {
            (rank($0), enemyTierIndex[$0.id] ?? 0, $0.id)
                < (rank($1), enemyTierIndex[$1.id] ?? 0, $1.id)
        }
        // Late levels field 30+ enemies; tighten the row so it stays on screen.
        let spacing: CGFloat = sorted.count > 24 ? 7 : 12
        var x = -CGFloat(sorted.count - 1) * spacing / 2
        for body in sorted {
            let isBoss = bossIDs.contains(body.id)
            let dot = SKShapeNode(circleOfRadius: isBoss ? 5.5 : 3.5)
            let rgb = enemyBaseColors[body.id] ?? (1, 1, 1)
            dot.fillColor = SKColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            dot.strokeColor = .clear
            dot.position = CGPoint(x: x, y: 0)
            enemyDotsNode.addChild(dot)
            x += spacing
        }
    }

    private func updateBatteryHUD() {
        // Strip batteries: visible only for types with charge; the selected
        // one wears a white outline. The fill level shows the pool against
        // one full capacity (stacked reserves cap the bar and carry the
        // surplus in the seconds label).
        for type in BatteryType.allCases {
            guard let button = batteryButtons[type] else { continue }
            let reserve = batteryReserves[type] ?? 0
            button.isHidden = reserve <= 0
            let selected = type == batteryType
            button.strokeColor = selected ? .white : batteryColor(type)
            button.lineWidth = selected ? 2.5 : 1.5
            let fraction = CGFloat(min(1, reserve / type.capacity))
            batteryButtonFills[type]?.size = CGSize(
                width: (batteryButtonSize.width - 8) * fraction,
                height: batteryButtonSize.height - 8)
            batteryButtonFills[type]?.alpha = selected ? 0.9 : 0.45
            batteryButtonLabels[type]?.text = String(format: "%.2fs", reserve)
        }
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
                // While tap-firing, the aim is locked to the finger
                // (processLaser owns the rotation) — movement must not
                // fight it.
                let aimLocked = controlScheme != .joystick && firingRequested
                if !aimLocked, let last = lastPlayerPosition {
                    let dx = position.x - last.x
                    let dy = position.y - last.y
                    if dx * dx + dy * dy > 0.01 {
                        rotatePlayer(toward: atan2(dy, dx))
                    }
                }
                lastPlayerPosition = position
                playerNode?.position = position
            case .npc, .shooter, .runner, .hunter:
                guard let node = npcNodes[body.id] else { break }
                node.position = CGPoint(x: body.position.x, y: body.position.y)
                // Shooters track the player; runners face their movement.
                if body.kind == .shooter,
                   let target = world.playerID.flatMap({ world.body(withID: $0)?.position }) {
                    let toPlayer = target - body.position
                    if toPlayer.length > 1 {
                        node.zRotation = CGFloat(atan2(toPlayer.y, toPlayer.x))
                    }
                } else if body.kind == .runner || body.kind == .hunter,
                          body.velocity.length > 1 {
                    node.zRotation = CGFloat(atan2(body.velocity.y, body.velocity.x))
                }
            case .rock:
                break // static; the node was positioned once at build time
            }
        }

    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch controlScheme {
        case .joystick:
            for touch in touches {
                if let type = batteryButtonHit(touch) {
                    selectBattery(type)
                } else if isInSteeringZone(touch) {
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
        case .tap:
            tapSchemeTouchesBegan(touches)
        case .stickAndTap:
            // Joystick steers; a touch on the play area (above the control
            // strip) fires. Stray touches on the strip do nothing.
            for touch in touches {
                if let type = batteryButtonHit(touch) {
                    selectBattery(type)
                } else if isInSteeringZone(touch) {
                    if touchController.began(touch, as: .joystick) {
                        updateJoystick(with: touch)
                    }
                } else if !isInControlStrip(touch) {
                    beginFireTouch(touch)
                }
            }
        }
    }

    /// Tap scheme: single tap walks there, double tap fires at it (and keeps
    /// firing at the finger while held). Starting to fire cancels the walk —
    /// the first tap of a double tap briefly sets one — so shooting never
    /// drags the player toward the target.
    private func tapSchemeTouchesBegan(_ touches: Set<UITouch>) {
        guard gameStarted, let world else { return }
        for touch in touches {
            if touch.tapCount >= 2 {
                beginFireTouch(touch)
            } else if fireTouch == nil {
                let location = touch.location(in: self)
                world.moveTarget = Vector2(location.x, location.y)
            }
        }
    }

    /// Starts firing at the touch: cancels any pending walk, snaps the aim so
    /// even the shortest burst leaves in the tapped direction (finger
    /// tracking then smooths), and opens the minimum burst window.
    private func beginFireTouch(_ touch: UITouch) {
        guard gameStarted, let world else { return }
        let location = touch.location(in: self)
        world.moveTarget = nil
        fireTouch = touch
        fireTarget = location
        burstEndTime = (lastUpdateTime ?? 0) + tapBurstDuration
        if let player = world.playerID.flatMap({ world.body(withID: $0) }) {
            let dx = location.x - player.position.x
            let dy = location.y - player.position.y
            if dx * dx + dy * dy > 1 {
                playerNode?.zRotation = atan2(dy, dx)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Roles make this scheme-agnostic: a touch is the fire finger, a
        // joystick finger, or nothing.
        for touch in touches {
            if touch === fireTouch {
                fireTarget = touch.location(in: self)
            } else if touchController.role(of: touch) == .joystick {
                updateJoystick(with: touch)
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

    private func isInSteeringZone(_ touch: UITouch) -> Bool {
        guard let cameraNode else { return false }
        let location = touch.location(in: cameraNode)
        let dx = location.x - joystickCenter.x
        let dy = location.y - joystickCenter.y
        return dx * dx + dy * dy <= steeringZoneRadius * steeringZoneRadius
    }

    private func isInControlStrip(_ touch: UITouch) -> Bool {
        guard let cameraNode else { return false }
        return touch.location(in: cameraNode).y < -size.height / 2 + controlStripHeight
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
            if touch === fireTouch {
                fireTouch = nil // the burst window may keep firing briefly
                continue
            }
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

    /// True while the current scheme wants the beam on: held fire button, or
    /// a held double-tap / its minimum burst window.
    private var firingRequested: Bool {
        switch controlScheme {
        case .joystick: return fireButtonHeld
        case .tap, .stickAndTap:
            return fireTouch != nil || (lastUpdateTime ?? 0) < burstEndTime
        }
    }

    private func processLaser() {
        guard let world else { return }
        // Tap-fire schemes: the beam must pass exactly through the finger,
        // even while running. Re-read the touch's location every frame (a
        // stationary finger produces no move events, but the camera scrolls
        // under it, so its scene position changes), face it directly with no
        // smoothing (the finger itself moves smoothly), and cast through the
        // actual finger point instead of a facing-derived ray. Movement-based
        // facing is suppressed in syncNodes while firing.
        var castThrough: Vector2?
        if controlScheme != .joystick, firingRequested,
           let player = world.playerID.flatMap({ world.body(withID: $0) }) {
            if let fireTouch { fireTarget = fireTouch.location(in: self) }
            let dx = Double(fireTarget.x) - player.position.x
            let dy = Double(fireTarget.y) - player.position.y
            if dx * dx + dy * dy > 1 {
                playerNode?.zRotation = CGFloat(atan2(dy, dx))
                castThrough = Vector2(Double(fireTarget.x), Double(fireTarget.y))
            }
        }
        // Otherwise the beam fires along the player's current facing (the
        // aim line the joystick steers) — firing has no direction of its own.
        let facing = playerNode.map { Vector2(cos(Double($0.zRotation)), sin(Double($0.zRotation))) }
        guard currentReserve > 0, firingRequested, let facing,
              let player = world.playerID.flatMap({ world.body(withID: $0) }) else {
            fadeOutBeamIfNeeded()
            return
        }
        let aimPoint = castThrough ?? (player.position + facing * 100)

        let points: [Vector2]
        if batteryType.piercing {
            // White: a straight ray through everything; damages every
            // hostile it crosses. No reflections, so no self-hit.
            guard let beam = world.castPiercingBeam(through: aimPoint),
                  beam.points.count >= 2 else {
                fadeOutBeamIfNeeded()
                return
            }
            points = beam.points
            for id in beam.bodyIDs
            where world.body(withID: id)?.kind.isHostile == true {
                applyLaserDamage(to: id, world: world)
            }
        } else {
            guard let beam = world.castLaserPath(through: aimPoint),
                  let endPoint = beam.points.last, beam.points.count >= 2 else {
                fadeOutBeamIfNeeded()
                return
            }
            points = beam.points
            if let victimID = beam.bodyID {
                if victimID == world.playerID {
                    // A reflected beam looped back into the player: self-hit.
                    killPlayer()
                } else if world.body(withID: victimID)?.kind.isHostile == true {
                    applyLaserDamage(to: victimID, world: world, hitPoint: endPoint)
                }
                // Rocks just absorb the beam.
            }
        }

        // Polyline through every bounce point to the final hit / bounds exit.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        laserNode?.path = path
        if let endPoint = points.last {
            sparkNode?.position = CGPoint(x: endPoint.x, y: endPoint.y)
        }
        showBeamNodes()

        // The beam rendered this frame, so it drains the selected reserve.
        // This runs after the kill so a last-kill-on-last-drop tie counts as
        // a win. Running dry auto-switches to the next type with charge; all
        // pools empty is NOT game over, the laser just can't fire until the
        // player collects another battery.
        batteryReserves[batteryType] = max(0, currentReserve - frameDt)
        if currentReserve <= 0 { autoSwitchBattery() }
    }

    /// Selects the given battery type: the beam color and the strip buttons
    /// follow immediately.
    private func selectBattery(_ type: BatteryType) {
        batteryType = type
        laserNode?.strokeColor = batteryColor(type)
    }

    /// The selected pool is empty: fall over to the STRONGEST type (white →
    /// orange → red) that still has charge, if any — the stronger laser is
    /// always preferred.
    private func autoSwitchBattery() {
        guard currentReserve <= 0,
              let next = BatteryType.allCases.reversed()
                  .first(where: { (batteryReserves[$0] ?? 0) > 0 })
        else { return }
        selectBattery(next)
    }

    /// Shield damage from the player's beam this frame (damage accumulates as
    /// beam-seconds × battery power); kills once it passes the shield, and
    /// heats the body toward white as the shield burns.
    private func applyLaserDamage(to victimID: BodyID, world: World,
                                  hitPoint: Vector2? = nil) {
        // Never-seen enemies just absorb the beam like a rock — blind-firing
        // across the map must not kill things the player hasn't met.
        guard seenEnemyIDs.contains(victimID) else { return }
        let shield = shieldSeconds[victimID] ?? 0
        let damage = (enemyDamage[victimID] ?? 0) + frameDt * batteryType.power
        enemyDamage[victimID] = damage
        if damage >= shield {
            let position = hitPoint ?? world.body(withID: victimID)?.position
            if let position { kill(npcID: victimID, at: position) }
        } else if shield > 0, let node = npcNodes[victimID],
                  let base = enemyBaseColors[victimID] {
            let f = CGFloat(min(1, damage / shield))
            node.fillColor = SKColor(red: base.r + (1 - base.r) * f,
                                     green: base.g + (1 - base.g) * f,
                                     blue: base.b + (1 - base.b) * f, alpha: 1)
            // The rings ARE the health bar: each covers an equal slice of
            // the shield and peels off outermost-first as it burns (the
            // boss's three rings = thirds of its health).
            let rings = node.children.compactMap { child -> (SKNode, Int)? in
                guard let name = child.name, name.hasPrefix("armorRing"),
                      let index = Int(name.dropFirst("armorRing".count)) else { return nil }
                return (child, index)
            }
            let count = Double(rings.count)
            for (ring, index) in rings {
                let depletionStart = count - 1 - Double(index) // outermost first
                ring.alpha = CGFloat(max(0, min(1, 1 - (Double(f) * count - depletionStart))))
            }
        }
    }

    // MARK: - Camera

    /// The camera tracks the player directly — every step of movement scrolls
    /// the view immediately (no follow box) — clamped to the map.
    private func updateCamera() {
        guard let world, let cameraNode,
              let player = world.playerID.flatMap({ world.body(withID: $0) }) else { return }
        let halfW = size.width / 2
        let halfH = size.height / 2
        // Center the player in the VISIBLE play area — the part of the screen
        // above the control strip — and let the bottom clamp stop at the strip's
        // top edge so no map hides behind the panel.
        let strip = controlStripHeight
        var cam = CGPoint(x: CGFloat(player.position.x),
                          y: CGFloat(player.position.y) - strip / 2)
        cam.x = min(max(cam.x, halfW), CGFloat(world.size.x) - halfW)
        cam.y = min(max(cam.y, halfH - strip), CGFloat(world.size.y) - halfH)
        cameraNode.position = cam
    }


    /// "On screen" means inside the VISIBLE play area: the control strip
    /// covers the bottom of the screen, so bodies behind the panel don't
    /// count (they can't be seen, must not activate or aim).
    private func isOnScreen(position: Vector2, radius: Double) -> Bool {
        guard let cameraNode else { return false }
        return abs(position.x - cameraNode.position.x) <= size.width / 2 + radius
            && position.y - cameraNode.position.y <= size.height / 2 + radius
            && position.y - cameraNode.position.y >= -size.height / 2 + controlStripHeight - radius
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

            if currentTime - start >= (shooterAimDurations[body.id] ?? EnemyTiers.shooterAim[0]) {
                fireShooterBeam(from: body.position, to: player.position)
                if absorbEnemyLaserHit() {
                    shooterAimStart[body.id] = nil // survived: the shooter re-aims
                } else {
                    return
                }
            }
        }
    }

    /// The lethal green flash a shooter leaves on screen when it fires.
    private func fireShooterBeam(from: Vector2, to: Vector2) {
        fireShooterBeam(along: [from, to])
    }

    /// Polyline variant for hunter shots, which can bounce off mirrors.
    private func fireShooterBeam(along points: [Vector2]) {
        guard let first = points.first else { return }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        // Same thin crisp look as the player's beam, just green.
        let beam = SKShapeNode(path: path)
        beam.strokeColor = SKColor(red: 0.25, green: 1, blue: 0.4, alpha: 1)
        beam.lineWidth = 1.5
        beam.zPosition = 1.5
        addChild(beam)
        beam.run(.sequence([
            .wait(forDuration: 0.15),
            .fadeOut(withDuration: 0.4),
            .removeFromParent(),
        ]))
        SoundManager.shared.playShooterFire()
    }

    /// Hunter state machine: amble around the map; on noticing the player
    /// (on screen + line of sight) loop run-closer → aim 500ms at a locked
    /// point → shoot. The lock makes the shot dodgeable; a miss restarts the
    /// loop, losing sight returns the hunter to patrol.
    private func processHunters(_ currentTime: TimeInterval) {
        guard let world else { return }
        guard gameStarted, let pid = world.playerID,
              let player = world.body(withID: pid) else {
            for body in world.bodies where body.kind == .hunter {
                world.setVelocity(.zero, forBodyID: body.id)
            }
            for node in hunterAimNodes.values { node.isHidden = true }
            return
        }
        for body in world.bodies where body.kind == .hunter {
            let id = body.id
            // A sprung fortress keeps every hunter permanently on the hunt —
            // they charge and shoot regardless of sight lines.
            let noticed = fortressBreached
                || (isOnScreen(position: body.position, radius: body.radius)
                    && world.hasLineOfSight(from: id, to: pid))
            var mode = hunterModes[id] ?? .patrol(direction: .zero, until: 0)

            if case .patrol = mode, noticed {
                mode = .approach(until: currentTime + hunterApproachDuration)
            }

            switch mode {
            case .patrol(var direction, var until):
                if currentTime >= until || direction == .zero {
                    let angle = Double.random(in: 0..<(2 * .pi))
                    direction = Vector2(cos(angle), sin(angle))
                    until = currentTime + Double.random(in: 1.5...3.5)
                }
                world.setVelocity(direction * (hunterPatrolSpeeds[id] ?? hunterPatrolSpeed),
                                  forBodyID: id)
                mode = .patrol(direction: direction, until: until)
                hunterAimNodes[id]?.isHidden = true

            case .approach(let until):
                if !noticed {
                    mode = .patrol(direction: .zero, until: 0)
                    world.setVelocity(.zero, forBodyID: id)
                } else if currentTime >= until {
                    mode = .aim(target: player.position, start: currentTime)
                    world.setVelocity(.zero, forBodyID: id)
                } else {
                    let toPlayer = player.position - body.position
                    let speed = hunterApproachSpeeds[id] ?? EnemyTiers.hunterApproach[0]
                    world.setVelocity(toPlayer.length > 1
                                      ? toPlayer.normalized * speed
                                      : .zero, forBodyID: id)
                }
                hunterAimNodes[id]?.isHidden = true

            case .aim(let target, let start):
                world.setVelocity(.zero, forBodyID: id)
                // The telegraph is a light beam: cast the actual laser path,
                // so it continues past a dodged player and bounces off
                // mirrors exactly like the shot will.
                if let aim = hunterAimNodes[id],
                   let beam = world.castLaserPath(from: id, through: target),
                   beam.points.count >= 2 {
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: beam.points[0].x, y: beam.points[0].y))
                    for point in beam.points.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x, y: point.y))
                    }
                    aim.path = path
                    aim.isHidden = false
                }
                if currentTime - start >= (hunterAimDurations[id] ?? EnemyTiers.hunterAim[0]) {
                    hunterAimNodes[id]?.isHidden = true
                    fireHunterShot(from: body, lockedTarget: target, world: world)
                    guard gameStarted else { return } // the shot connected
                    mode = noticed ? .approach(until: currentTime + hunterApproachDuration)
                                   : .patrol(direction: .zero, until: 0)
                }
            }
            hunterModes[id] = mode
        }
    }

    /// The hunter's shot: the real laser cast along the locked direction —
    /// reflected by mirrors, stopped by rocks. It kills only if the beam's
    /// final segment strikes the player; dodging during the aim makes it
    /// miss (and the beam visibly continues past where you stood).
    private func fireHunterShot(from hunter: CircleBody, lockedTarget: Vector2,
                                world: World) {
        guard let beam = world.castLaserPath(from: hunter.id, through: lockedTarget),
              beam.points.count >= 2 else { return }
        fireShooterBeam(along: beam.points)
        if beam.bodyID == world.playerID {
            absorbEnemyLaserHit()
        }
    }

    /// Runners, hunters, and every boss (huge shooters included) kill on
    /// contact.
    private func checkTouchKills() {
        guard gameStarted, let world, let pid = world.playerID,
              let player = world.body(withID: pid) else { return }
        for body in world.bodies
        where body.kind == .runner || body.kind == .hunter || bossIDs.contains(body.id) {
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
        SoundManager.shared.playPlayerDeath()
        fireButtonHeld = false
        fireTouch = nil
        burstEndTime = 0
        fadeOutBeamIfNeeded()
        for node in shooterAimNodes.values { node.isHidden = true }
        for node in hunterAimNodes.values { node.isHidden = true }
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

    /// The on-screen color of each battery type (pickup body, HUD bar, beam).
    private func batteryColor(_ type: BatteryType) -> SKColor {
        switch type {
        case .red: return SKColor(red: 1, green: 0.25, blue: 0.3, alpha: 1)
        case .orange: return SKColor(red: 1, green: 0.62, blue: 0.15, alpha: 1)
        case .white: return .white
        }
    }

    private func spawnBatteryPickup(at position: Vector2, type: BatteryType) {
        let node = SKShapeNode(rectOf: CGSize(width: 12, height: 18), cornerRadius: 3)
        node.fillColor = batteryColor(type)
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
        batteryPickups.append((node.position, node, type))
    }

    private func checkBatteryPickups() {
        guard gameStarted, let world, let pid = world.playerID,
              let player = world.body(withID: pid) else { return }
        batteryPickups.removeAll { pickup in
            let distance = player.position.distance(to: Vector2(pickup.position.x, pickup.position.y))
            guard distance <= player.radius + 14 else { return false }
            // The pickup ADDS a full charge to its type's pool — collecting a
            // second Red on top of a full Red gives 6s. A stronger laser is
            // always preferred: picking one up switches to it immediately
            // (as does any pickup while the selected pool is empty).
            batteryReserves[pickup.type, default: 0] += pickup.type.capacity
            if pickup.type.power > batteryType.power || currentReserve <= 0 {
                selectBattery(pickup.type)
            }
            pickup.node.run(.sequence([
                .group([
                    .scale(to: 1.8, duration: 0.2),
                    .fadeOut(withDuration: 0.2),
                ]),
                .removeFromParent(),
            ]))
            spawnRechargeEffect(at: player.position)
            return true
        }
    }

    // MARK: - Player shields

    /// Shows one armor ring per collected shield, innermost first.
    private func updatePlayerShieldRings() {
        guard let playerNode else { return }
        for ring in 0..<maxPlayerShields {
            playerNode.childNode(withName: "playerShield\(ring)")?.isHidden =
                ring >= playerShields
        }
    }

    /// A shield lying on the map: concentric armor rings, pulsing gently.
    private func spawnShieldPickup(at position: Vector2) {
        let node = SKShapeNode(circleOfRadius: 12)
        node.strokeColor = SKColor(white: 0.95, alpha: 0.85)
        node.lineWidth = 1.5
        node.fillColor = .clear
        node.glowWidth = 2
        node.zPosition = 0.5
        node.position = CGPoint(x: position.x, y: position.y)
        let inner = SKShapeNode(circleOfRadius: 7)
        inner.strokeColor = SKColor(white: 0.95, alpha: 0.85)
        inner.lineWidth = 1.5
        inner.fillColor = .clear
        node.addChild(inner)
        node.run(.repeatForever(.sequence([
            .scale(to: 1.15, duration: 0.4),
            .scale(to: 0.9, duration: 0.4),
        ])))
        addChild(node)
        shieldPickups.append((node.position, node))
    }

    /// Collects touched shields up to the cap — a full player (3 rings)
    /// leaves further shields lying for later.
    private func checkShieldPickups() {
        guard gameStarted, playerShields < maxPlayerShields, let world,
              let pid = world.playerID, let player = world.body(withID: pid) else { return }
        shieldPickups.removeAll { pickup in
            guard playerShields < maxPlayerShields else { return false }
            let distance = player.position.distance(to: Vector2(pickup.position.x, pickup.position.y))
            guard distance <= player.radius + 14 else { return false }
            playerShields += 1
            updatePlayerShieldRings()
            pickup.node.run(.sequence([
                .group([
                    .scale(to: 1.8, duration: 0.2),
                    .fadeOut(withDuration: 0.2),
                ]),
                .removeFromParent(),
            ]))
            spawnRechargeEffect(at: player.position)
            return true
        }
    }

    /// An enemy laser connected: a shield eats the hit (one ring bursts and
    /// is gone) — only with no rings left does the player die. Runner/boss
    /// touch and the player's own reflected beam never reach this path.
    /// Returns true when the player survived.
    @discardableResult
    private func absorbEnemyLaserHit() -> Bool {
        guard playerShields > 0 else {
            killPlayer()
            return false
        }
        playerShields -= 1
        updatePlayerShieldRings()
        SoundManager.shared.playOuch()
        if let playerNode {
            let burst = SKShapeNode(circleOfRadius: playerRadius + 8)
            burst.strokeColor = SKColor(white: 1, alpha: 0.9)
            burst.lineWidth = 3
            burst.glowWidth = 4
            burst.fillColor = .clear
            burst.position = playerNode.position
            burst.zPosition = 1.6
            addChild(burst)
            burst.run(.sequence([
                .group([
                    .scale(to: 2.0, duration: 0.3),
                    .fadeOut(withDuration: 0.3),
                ]),
                .removeFromParent(),
            ]))
        }
        return true
    }

    /// Energy-hit feedback on collecting a spare: a green ring bursts out of
    /// the player and the battery icon pulses.
    private func spawnRechargeEffect(at position: Vector2) {
        let ring = SKShapeNode(circleOfRadius: 18)
        ring.strokeColor = SKColor(red: 0.3, green: 1, blue: 0.45, alpha: 0.9)
        ring.lineWidth = 3
        ring.glowWidth = 4
        ring.fillColor = .clear
        ring.position = CGPoint(x: position.x, y: position.y)
        ring.zPosition = 1.6
        ring.setScale(0.3)
        addChild(ring)
        ring.run(.sequence([
            .group([
                .scale(to: 2.2, duration: 0.35),
                .fadeOut(withDuration: 0.35),
            ]),
            .removeFromParent(),
        ]))
        batteryHUDNode?.run(.sequence([
            .scale(to: 1.25, duration: 0.1),
            .scale(to: 1.0, duration: 0.15),
        ]))
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
        SoundManager.shared.playOuch()

        // Same impact spark as at the world's edge, as a short burst — the NPC
        // is gone instantly, so the spark lives just long enough to register.
        let burst = makeSparkNode()
        burst.position = CGPoint(x: hitPoint.x, y: hitPoint.y)
        addChild(burst)
        burst.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))

        // Battery carriers leave their battery where they fell; shield
        // carriers their shield.
        if let type = batteryCarriers.removeValue(forKey: npcID), let dropPosition {
            spawnBatteryPickup(at: dropPosition, type: type)
        }
        if shieldCarriers.remove(npcID) != nil, let dropPosition {
            spawnShieldPickup(at: dropPosition)
        }
        shooterAimStart[npcID] = nil
        shooterAimNodes.removeValue(forKey: npcID)?.removeFromParent()
        hunterModes[npcID] = nil
        hunterAimNodes.removeValue(forKey: npcID)?.removeFromParent()
        shieldSeconds[npcID] = nil
        enemyDamage[npcID] = nil
        enemyBaseColors[npcID] = nil
        enemyTierIndex[npcID] = nil
        shooterAimDurations[npcID] = nil
        hunterApproachSpeeds[npcID] = nil
        hunterAimDurations[npcID] = nil
        hunterPatrolSpeeds[npcID] = nil
        bossIDs.remove(npcID)

        if let node = npcNodes.removeValue(forKey: npcID) {
            node.run(.sequence([
                .group([
                    .scale(to: 1.6, duration: 0.15),
                    .fadeOut(withDuration: 0.15),
                ]),
                .removeFromParent(),
            ]))
        }

        // Last one? Celebrate on the live scene, then report the win.
        if world?.bodies.contains(where: { $0.kind.isHostile }) == false {
            gameStarted = false
            spawnWinCelebration()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.onAllNPCsEliminated?()
            }
        }
    }

    /// Victory fireworks: staggered multicolor bursts around the player plus
    /// expanding rings. Runs on the live scene before the overlay appears
    /// (and keeps sparkling behind it — the scene never pauses).
    private func spawnWinCelebration() {
        guard let world,
              let player = world.playerID.flatMap({ world.body(withID: $0) }) else { return }
        let center = CGPoint(x: player.position.x, y: player.position.y)
        let colors: [SKColor] = [
            SKColor(red: 0.2, green: 0.85, blue: 1, alpha: 1),   // player cyan
            SKColor(red: 0.3, green: 1, blue: 0.45, alpha: 1),   // battery green
            SKColor(red: 1, green: 0.9, blue: 0.4, alpha: 1),    // spark yellow
            SKColor(red: 0.75, green: 0.42, blue: 1, alpha: 1),  // runner purple
            SKColor(red: 1, green: 0.45, blue: 0.35, alpha: 1),  // shooter red
            .white,
        ]

        for burst in 0..<6 {
            let delay = Double(burst) * 0.22
            let origin = CGPoint(x: center.x + CGFloat.random(in: -130...130),
                                 y: center.y + CGFloat.random(in: -150...150))

            let ring = SKShapeNode(circleOfRadius: 16)
            ring.strokeColor = colors[burst % colors.count]
            ring.lineWidth = 2.5
            ring.fillColor = .clear
            ring.position = origin
            ring.zPosition = 2.5
            ring.alpha = 0
            ring.setScale(0.2)
            addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: delay),
                .fadeIn(withDuration: 0.05),
                .group([
                    .scale(to: 3.0, duration: 0.5),
                    .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 0.3)]),
                ]),
                .removeFromParent(),
            ]))

            for _ in 0..<14 {
                let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 2.5...4.5))
                dot.fillColor = colors.randomElement() ?? .white
                dot.strokeColor = .clear
                dot.position = origin
                dot.zPosition = 2.5
                dot.alpha = 0
                addChild(dot)
                let angle = Double.random(in: 0..<(2 * .pi))
                let distance = Double.random(in: 50...140)
                let fly = SKAction.moveBy(x: cos(angle) * distance,
                                          y: sin(angle) * distance,
                                          duration: 0.7)
                fly.timingMode = .easeOut
                dot.run(.sequence([
                    .wait(forDuration: delay),
                    .fadeIn(withDuration: 0.05),
                    .group([
                        fly,
                        .sequence([.wait(forDuration: 0.35), .fadeOut(withDuration: 0.35)]),
                    ]),
                    .removeFromParent(),
                ]))
            }
        }
    }
}
