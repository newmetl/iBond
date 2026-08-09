import XCTest
@testable import GameEngine

final class EnemyTests: XCTestCase {
    // MARK: - Kinds

    func testShooterAndRunnerAreHostileKillableKinds() {
        XCTAssertTrue(CircleBody.Kind.npc.isHostile)
        XCTAssertTrue(CircleBody.Kind.shooter.isHostile)
        XCTAssertTrue(CircleBody.Kind.runner.isHostile)
        XCTAssertFalse(CircleBody.Kind.player.isHostile)
        XCTAssertFalse(CircleBody.Kind.rock.isHostile)
    }

    // MARK: - Runner steering

    func testRunnerWalksTowardPlayerOnceActivated() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(400, 400))
        let runner = world.addRunner(at: Vector2(400, 100))
        world.runnerSpeed = 100
        world.activateRunner(runner)
        world.update(dt: 0.5)
        let pos = world.body(withID: runner)!.position
        XCTAssertEqual(pos.x, 400, accuracy: 1e-6)
        XCTAssertEqual(pos.y, 150, accuracy: 1) // moved 50pt toward the player
    }

    func testRunnerWaitsUntilActivated() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(400, 400))
        let runner = world.addRunner(at: Vector2(400, 100))
        world.update(dt: 1.0)
        XCTAssertEqual(world.body(withID: runner)!.position, Vector2(400, 100))
    }

    func testRunnerStopsWhenPlayerIsGone() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(400, 400))
        let runner = world.addRunner(at: Vector2(400, 100))
        world.activateRunner(runner)
        world.remove(bodyID: world.playerID!)
        world.update(dt: 0.5)
        let pos = world.body(withID: runner)!.position
        XCTAssertEqual(pos.y, 100, accuracy: 1) // no chase without a target
    }

    func testRunnerIsBlockedByRocks() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(400, 500))
        let runner = world.addRunner(at: Vector2(400, 100), radius: 14)
        world.activateRunner(runner)
        world.addRock(at: Vector2(400, 300), radius: 40)
        for _ in 0..<600 { world.update(dt: 1.0 / 120.0) } // 5 seconds head-on
        let pos = world.body(withID: runner)!.position
        // Head-on into the rock: blocked at its surface (dead-center, no slide).
        XCTAssertLessThanOrEqual(pos.y, 300 - 40 - 14 + 1)
    }

    // MARK: - Direct player control (virtual joystick)

    func testControlVelocityDrivesThePlayer() {
        let world = World(size: Vector2(800, 800))
        let player = world.addPlayer(at: Vector2(400, 400))
        world.playerControlVelocity = Vector2(100, -50)
        world.update(dt: 0.5)
        let pos = world.body(withID: player)!.position
        XCTAssertEqual(pos.x, 450, accuracy: 1e-6)
        XCTAssertEqual(pos.y, 375, accuracy: 1e-6)
    }

    func testControlVelocityOverridesMoveTarget() {
        let world = World(size: Vector2(800, 800))
        let player = world.addPlayer(at: Vector2(400, 400))
        world.moveTarget = Vector2(100, 400) // would go -x...
        world.playerControlVelocity = Vector2(100, 0) // ...but control wins
        world.update(dt: 0.5)
        XCTAssertEqual(world.body(withID: player)!.position.x, 450, accuracy: 1e-6)
    }

    func testClearingControlVelocityStopsThePlayer() {
        let world = World(size: Vector2(800, 800))
        let player = world.addPlayer(at: Vector2(400, 400))
        world.playerControlVelocity = Vector2(100, 0)
        world.update(dt: 0.5)
        world.playerControlVelocity = nil
        world.update(dt: 0.5)
        XCTAssertEqual(world.body(withID: player)!.position.x, 450, accuracy: 1e-6)
        XCTAssertEqual(world.body(withID: player)!.velocity, .zero)
    }

    func testShooterStaysPutButIsShoveable() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(400, 400))
        let shooter = world.addShooter(at: Vector2(200, 200))
        world.update(dt: 1.0)
        // No self-movement...
        XCTAssertEqual(world.body(withID: shooter)!.position, Vector2(200, 200))
        // ...but a shove impulse damps back out (no perpetual drift).
        world.setVelocity(Vector2(120, 0), forBodyID: shooter)
        for _ in 0..<120 { world.update(dt: 1.0 / 120.0) }
        XCTAssertLessThan(world.body(withID: shooter)!.velocity.length, 10)
    }

    // MARK: - Line of sight

    func testLineOfSightClearBetweenShooterAndPlayer() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(400, 400))
        let shooter = world.addShooter(at: Vector2(400, 100))
        XCTAssertTrue(world.hasLineOfSight(from: shooter, to: world.playerID!))
    }

    func testLineOfSightBlockedByRock() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(400, 400))
        let shooter = world.addShooter(at: Vector2(400, 100))
        world.addRock(at: Vector2(400, 250), radius: 40)
        XCTAssertFalse(world.hasLineOfSight(from: shooter, to: world.playerID!))
    }

    func testLineOfSightBlockedByMirror() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(400, 400))
        let shooter = world.addShooter(at: Vector2(400, 100))
        world.addMirror(from: Vector2(300, 250), to: Vector2(500, 250))
        XCTAssertFalse(world.hasLineOfSight(from: shooter, to: world.playerID!))
    }

    func testLineOfSightBlockedByAnotherBody() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(400, 400))
        let shooter = world.addShooter(at: Vector2(400, 100))
        world.addRunner(at: Vector2(400, 250), radius: 14)
        XCTAssertFalse(world.hasLineOfSight(from: shooter, to: world.playerID!))
    }

    func testLineOfSightIsFalseForMissingBodies() {
        let world = World(size: Vector2(800, 800))
        let shooter = world.addShooter(at: Vector2(400, 100))
        XCTAssertFalse(world.hasLineOfSight(from: shooter, to: 999))
    }

    // MARK: - Reflected self-hit

    func testReflectedBeamCanHitThePlayer() {
        let world = World(size: Vector2(400, 400))
        world.addPlayer(at: Vector2(100, 200), radius: 16)
        world.addMirror(from: Vector2(200, 100), to: Vector2(200, 300)) // perpendicular wall
        let path = world.castLaserPath(through: Vector2(150, 200))! // straight at it
        XCTAssertEqual(path.bodyID, world.playerID)
        XCTAssertEqual(path.points.count, 3)
        XCTAssertEqual(path.points[2].x, 116, accuracy: 1e-6) // own surface: 100 + 16
        XCTAssertEqual(path.points[2].y, 200, accuracy: 1e-6)
    }

    func testFirstSegmentStillIgnoresThePlayer() {
        // No mirror: firing outward never self-hits even though the beam
        // originates inside the player's own circle.
        let world = World(size: Vector2(400, 400))
        world.addPlayer(at: Vector2(100, 200), radius: 16)
        let path = world.castLaserPath(through: Vector2(300, 200))!
        XCTAssertNil(path.bodyID)
        XCTAssertEqual(path.points.count, 2)
    }
}

// MARK: - Hunters

final class HunterTests: XCTestCase {
    func testHunterIsHostileKillableKind() {
        XCTAssertTrue(CircleBody.Kind.hunter.isHostile)
    }

    func testAddHunterCreatesHunterBody() {
        let world = World(size: Vector2(800, 800))
        let id = world.addHunter(at: Vector2(200, 300), radius: 14)
        let body = world.body(withID: id)
        XCTAssertEqual(body?.kind, .hunter)
        XCTAssertEqual(body?.position, Vector2(200, 300))
        XCTAssertEqual(body?.radius, 14)
    }

    /// Hunters are app-steered via setVelocity; the engine integrates them
    /// (with hostile damping) rather than overriding their velocity.
    func testHunterMovesWithSetVelocityAndIsDamped() {
        let world = World(size: Vector2(800, 800))
        let id = world.addHunter(at: Vector2(100, 100))
        world.setVelocity(Vector2(60, 0), forBodyID: id)
        world.update(dt: 0.1)
        let body = world.body(withID: id)!
        XCTAssertEqual(body.position.x, 106, accuracy: 0.5)
        XCTAssertEqual(body.position.y, 100, accuracy: 1e-9)
        // Damping shrank but did not zero the velocity (the app re-steers
        // every rendered frame).
        XCTAssertGreaterThan(body.velocity.x, 0)
        XCTAssertLessThan(body.velocity.x, 60)
    }

    func testHunterIsBlockedByRock() {
        let world = World(size: Vector2(800, 800))
        world.addRock(at: Vector2(160, 100), radius: 30)
        let id = world.addHunter(at: Vector2(100, 100), radius: 14)
        for _ in 0..<120 { // 1s of fixed steps, driving into the rock
            world.setVelocity(Vector2(120, 0), forBodyID: id)
            world.update(dt: 1.0 / 120.0)
        }
        let body = world.body(withID: id)!
        // Stopped at the rock's surface: rock center 160 minus radii 30+14.
        XCTAssertEqual(body.position.x, 116, accuracy: 1.5)
    }

    func testHunterStaysInBounds() {
        let world = World(size: Vector2(300, 300))
        let id = world.addHunter(at: Vector2(280, 150), radius: 14)
        for _ in 0..<120 {
            world.setVelocity(Vector2(400, 0), forBodyID: id)
            world.update(dt: 1.0 / 120.0)
        }
        let body = world.body(withID: id)!
        XCTAssertEqual(body.position.x, 286, accuracy: 1e-6) // size - radius
    }
}

// MARK: - Per-runner speed overrides (tiers)

final class RunnerSpeedOverrideTests: XCTestCase {
    func testRunnerUsesOverrideSpeedWhenSet() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(400, 700))
        let fast = world.addRunner(at: Vector2(400, 100))
        let slow = world.addRunner(at: Vector2(200, 100))
        world.runnerSpeed = 100
        world.runnerSpeedOverrides[fast] = 200
        world.activateRunner(fast)
        world.activateRunner(slow)
        world.update(dt: 0.5)
        XCTAssertEqual(world.body(withID: fast)!.position.y, 200, accuracy: 1)
        XCTAssertLessThan(world.body(withID: slow)!.position.y, 160)
    }
}
