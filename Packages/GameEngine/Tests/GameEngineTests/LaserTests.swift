import XCTest
@testable import GameEngine

final class LaserTests: XCTestCase {
    /// World with the player at (200, 200), aiming helpers below.
    private func makeWorld() -> World {
        let world = World(size: Vector2(400, 400))
        world.addPlayer(at: Vector2(200, 200), radius: 16)
        return world
    }

    func testHitsNPCAtSurfacePoint() {
        let world = makeWorld()
        let npc = world.addNPC(at: Vector2(300, 200), radius: 10)
        let hit = world.castLaser(through: Vector2(250, 200))!
        XCTAssertEqual(hit.bodyID, npc)
        XCTAssertEqual(hit.point.x, 290, accuracy: 1e-6) // 300 - radius 10
        XCTAssertEqual(hit.point.y, 200, accuracy: 1e-6)
    }

    func testHitsNearestOfSeveralNPCs() {
        let world = makeWorld()
        let near = world.addNPC(at: Vector2(280, 200), radius: 10)
        world.addNPC(at: Vector2(350, 200), radius: 10)
        let hit = world.castLaser(through: Vector2(400, 200))!
        XCTAssertEqual(hit.bodyID, near)
    }

    func testAimPointBeyondNPCStillHitsIt() {
        // The beam is a ray through the aim point, not a segment to it.
        let world = makeWorld()
        let npc = world.addNPC(at: Vector2(350, 200), radius: 10)
        let hit = world.castLaser(through: Vector2(240, 200))! // aim closer than the NPC
        XCTAssertEqual(hit.bodyID, npc)
    }

    func testIgnoresNPCBehindThePlayer() {
        let world = makeWorld()
        world.addNPC(at: Vector2(100, 200), radius: 10) // behind, given +x aim
        let hit = world.castLaser(through: Vector2(300, 200))!
        XCTAssertNil(hit.bodyID)
    }

    func testMissExitsAtWorldBounds() {
        let world = makeWorld()
        let hit = world.castLaser(through: Vector2(300, 200))! // +x, nothing in the way
        XCTAssertNil(hit.bodyID)
        XCTAssertEqual(hit.point.x, 400, accuracy: 1e-6)
        XCTAssertEqual(hit.point.y, 200, accuracy: 1e-6)
    }

    func testDiagonalMissExitsAtCorrectWall() {
        let world = makeWorld()
        let hit = world.castLaser(through: Vector2(250, 250))! // 45°, hits top wall first (tie: same t)
        XCTAssertNil(hit.bodyID)
        XCTAssertEqual(hit.point.x, 400, accuracy: 1e-6)
        XCTAssertEqual(hit.point.y, 400, accuracy: 1e-6)
    }

    func testAimAtPlayerCenterReturnsNil() {
        let world = makeWorld()
        XCTAssertNil(world.castLaser(through: Vector2(200, 200)))
    }

    func testNoPlayerReturnsNil() {
        let world = World(size: Vector2(400, 400))
        world.addNPC(at: Vector2(300, 200))
        XCTAssertNil(world.castLaser(through: Vector2(300, 200)))
    }

    func testOriginInsideNPCHitsFarSide() {
        // Player overlapping an NPC: the beam exits through the far side.
        let world = makeWorld()
        let npc = world.addNPC(at: Vector2(205, 200), radius: 30) // player center inside
        let hit = world.castLaser(through: Vector2(300, 200))!
        XCTAssertEqual(hit.bodyID, npc)
        XCTAssertEqual(hit.point.x, 235, accuracy: 1e-6) // 205 + 30
        XCTAssertEqual(hit.point.y, 200, accuracy: 1e-6)
    }

    func testAsymmetricDiagonalMissExitsAtNearestWall() {
        // Shallow angle: reaches the right wall (x=400) before the top wall.
        let world = makeWorld()
        let hit = world.castLaser(through: Vector2(300, 250))! // dir (2,1)/√5
        XCTAssertNil(hit.bodyID)
        XCTAssertEqual(hit.point.x, 400, accuracy: 1e-6)
        XCTAssertEqual(hit.point.y, 300, accuracy: 1e-6) // 200 + (200/2)*1
    }
}

// MARK: - Casting from arbitrary bodies (hunter beams)

final class BodyOriginLaserTests: XCTestCase {
    func testCastFromBodySkipsItselfAndHitsTargetInLine() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(600, 400))
        let hunter = world.addHunter(at: Vector2(200, 400), radius: 14)
        let path = world.castLaserPath(from: hunter, through: Vector2(300, 400))
        XCTAssertEqual(path?.bodyID, world.playerID)
        XCTAssertEqual(path?.points.last?.x ?? 0, 584, accuracy: 1e-6) // player surface
    }

    func testCastFromBodyStopsAtRock() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(600, 400))
        let rock = world.addRock(at: Vector2(400, 400), radius: 30)
        let hunter = world.addHunter(at: Vector2(200, 400), radius: 14)
        let path = world.castLaserPath(from: hunter, through: Vector2(300, 400))
        XCTAssertEqual(path?.bodyID, rock)
    }

    func testCastFromBodyReflectsOffMirrorToPlayer() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(200, 600))
        let hunter = world.addHunter(at: Vector2(200, 200), radius: 14)
        // 45° mirror at (400, 200): beam fired along +x bounces up toward +y.
        world.addMirror(from: Vector2(350, 150), to: Vector2(450, 250))
        // The reflected ray runs up the x=400 line; put the player on it.
        world.remove(bodyID: world.playerID!)
        world.addPlayer(at: Vector2(400, 600))
        let path = world.castLaserPath(from: hunter, through: Vector2(300, 200))
        XCTAssertEqual(path?.bodyID, world.playerID)
        XCTAssertEqual(path?.points.count, 3) // origin, bounce, hit
    }

    func testPlayerCastStillWorksViaDelegation() {
        let world = World(size: Vector2(800, 800))
        world.addPlayer(at: Vector2(200, 400))
        let npc = world.addNPC(at: Vector2(600, 400))
        let path = world.castLaserPath(through: Vector2(300, 400))
        XCTAssertEqual(path?.bodyID, npc)
    }
}
