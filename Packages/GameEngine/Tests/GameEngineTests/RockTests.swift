import XCTest
@testable import GameEngine

final class RockTests: XCTestCase {
    func testRockNeverMovesWhenCollidedWith() {
        let world = World(size: Vector2(400, 400))
        let rock = world.addRock(at: Vector2(200, 200), radius: 40)
        let npc = world.addNPC(at: Vector2(165, 200), radius: 10) // overlapping: dist 35 < 50
        world.update(dt: 1.0 / 120.0)
        // The rock stays put; the NPC takes the full separation.
        XCTAssertEqual(world.body(withID: rock)!.position, Vector2(200, 200))
        let npcPos = world.body(withID: npc)!.position
        XCTAssertEqual(npcPos.x, 150, accuracy: 1e-6) // pushed out to dist 50
        XCTAssertEqual(npcPos.y, 200, accuracy: 1e-6)
    }

    func testPlayerCannotWalkThroughRock() {
        let world = World(size: Vector2(400, 400))
        world.addPlayer(at: Vector2(100, 200), radius: 16)
        world.addRock(at: Vector2(200, 200), radius: 40)
        world.moveTarget = Vector2(300, 200) // straight through the rock
        for _ in 0..<600 { world.update(dt: 1.0 / 120.0) } // 5 seconds
        let player = world.body(withID: world.playerID!)!
        // Blocked at the surface on the near side, never through the middle.
        XCTAssertLessThanOrEqual(player.position.x, 200 - 40 - 16 + 1)
        XCTAssertEqual(world.body(withID: world.rockIDs.first!)!.position, Vector2(200, 200))
    }

    func testRockIsIgnoredByPlayerSeekAndDamping() {
        let world = World(size: Vector2(400, 400))
        let rock = world.addRock(at: Vector2(200, 200), radius: 40)
        world.setVelocity(Vector2(100, 0), forBodyID: rock) // hostile test: even forced velocity
        world.update(dt: 1.0 / 120.0)
        // Static bodies never integrate velocity.
        XCTAssertEqual(world.body(withID: rock)!.position, Vector2(200, 200))
    }

    func testLaserStopsAtRock() {
        let world = World(size: Vector2(400, 400))
        world.addPlayer(at: Vector2(100, 200), radius: 16)
        let rock = world.addRock(at: Vector2(250, 200), radius: 40)
        world.addNPC(at: Vector2(350, 200), radius: 10) // hidden behind the rock
        let hit = world.castLaser(through: Vector2(300, 200))!
        XCTAssertEqual(hit.bodyID, rock)
        XCTAssertEqual(hit.point.x, 210, accuracy: 1e-6) // 250 - 40
        XCTAssertEqual(hit.point.y, 200, accuracy: 1e-6)
    }

    func testSpawnSamplingAvoidsRocks() {
        let world = World(size: Vector2(200, 200))
        world.addRock(at: Vector2(100, 100), radius: 60)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<30 {
            guard let p = world.randomFreePosition(radius: 14, using: &rng) else { continue }
            XCTAssertGreaterThanOrEqual(p.distance(to: Vector2(100, 100)), 60 + 14)
        }
    }
}
