import XCTest
@testable import GameEngine

final class WorldBodyTests: XCTestCase {
    func testAddPlayerAndNPCsHaveDistinctIDs() {
        let world = World(size: Vector2(400, 400))
        let p = world.addPlayer(at: Vector2(200, 200))
        let a = world.addNPC(at: Vector2(50, 50))
        let b = world.addNPC(at: Vector2(300, 300))
        XCTAssertEqual(Set([p, a, b]).count, 3)
        XCTAssertEqual(world.playerID, p)
        XCTAssertEqual(world.bodies.count, 3)
    }

    func testBodyLookupReturnsCorrectBody() {
        let world = World(size: Vector2(400, 400))
        let id = world.addNPC(at: Vector2(120, 80), radius: 14)
        let body = world.body(withID: id)
        XCTAssertEqual(body?.position, Vector2(120, 80))
        XCTAssertEqual(body?.radius, 14)
        XCTAssertEqual(body?.kind, .npc)
        XCTAssertNil(world.body(withID: 999))
    }

    func testRemoveBody() {
        let world = World(size: Vector2(400, 400))
        let id = world.addNPC(at: Vector2(120, 80))
        world.remove(bodyID: id)
        XCTAssertNil(world.body(withID: id))
        XCTAssertTrue(world.bodies.isEmpty)
    }

    func testRandomFreePositionDoesNotOverlapExistingBodies() {
        let world = World(size: Vector2(400, 400))
        world.addPlayer(at: Vector2(200, 200), radius: 16)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            guard let p = world.randomFreePosition(radius: 14, using: &rng) else {
                return XCTFail("expected a free position in a mostly empty world")
            }
            // Inside bounds, respecting the radius…
            XCTAssertTrue(p.x >= 14 && p.x <= 386 && p.y >= 14 && p.y <= 386)
            // …and clear of every existing body.
            for b in world.bodies {
                XCTAssertGreaterThanOrEqual(b.position.distance(to: p), b.radius + 14)
            }
            world.addNPC(at: p, radius: 14)
        }
    }
}
