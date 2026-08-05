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
}
