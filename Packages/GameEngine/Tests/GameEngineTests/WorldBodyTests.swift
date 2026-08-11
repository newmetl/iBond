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

    func testRandomFreePositionReturnsNilForTooSmallWorld() {
        let world = World(size: Vector2(20, 20))
        var rng = SystemRandomNumberGenerator()
        XCTAssertNil(world.randomFreePosition(radius: 14, using: &rng))
    }

    func testRandomFreePositionReturnsNilWhenWorldIsFull() {
        // One body whose blocked zone covers every legal sample point.
        let world = World(size: Vector2(60, 60))
        world.addNPC(at: Vector2(30, 30), radius: 30)
        var rng = SystemRandomNumberGenerator()
        XCTAssertNil(world.randomFreePosition(radius: 14, using: &rng))
    }

    func testRegionConstrainedSamplingStaysInRegion() {
        let world = World(size: Vector2(400, 400))
        var rng = SystemRandomNumberGenerator()
        let region = Rect(min: Vector2(100, 150), max: Vector2(300, 250))
        for _ in 0..<20 {
            guard let p = world.randomFreePosition(radius: 20, in: region, using: &rng) else {
                return XCTFail("expected a free position in an empty region")
            }
            XCTAssertTrue(p.x >= 100 && p.x <= 300 && p.y >= 150 && p.y <= 250)
            // Still respects world bounds insetting by radius.
            XCTAssertTrue(p.x >= 20 && p.x <= 380 && p.y >= 20 && p.y <= 380)
        }
    }

    func testRegionSmallerThanRadiusStillSamplesItsCenterline() {
        // A degenerate (zero-area after inset) region must not crash; it may
        // return nil or a point clamped to the region.
        let world = World(size: Vector2(400, 400))
        var rng = SystemRandomNumberGenerator()
        let region = Rect(min: Vector2(200, 200), max: Vector2(200, 200))
        _ = world.randomFreePosition(radius: 20, in: region, using: &rng) // no crash
    }

    func testRemovingSameBodyTwiceIsHarmless() {
        let world = World(size: Vector2(400, 400))
        let id = world.addNPC(at: Vector2(120, 80))
        world.remove(bodyID: id)
        world.remove(bodyID: id)
        XCTAssertTrue(world.bodies.isEmpty)
    }

    func testAddMineCreatesSmallHostileBody() {
        let world = World(size: Vector2(400, 400))
        let id = world.addMine(at: Vector2(120, 80), radius: 7)
        let mine = world.body(withID: id)
        XCTAssertEqual(mine?.kind, .mine)
        XCTAssertEqual(mine?.radius, 7)
        XCTAssertTrue(mine?.kind.isHostile == true)
    }

    func testMineFollowsSetVelocityLikeAHunter() {
        // Mines are app-steered: the engine integrates whatever velocity the
        // app sets and never overrides it.
        let world = World(size: Vector2(400, 400))
        let id = world.addMine(at: Vector2(100, 100), radius: 7)
        world.setVelocity(Vector2(100, 0), forBodyID: id)
        world.update(dt: 0.1)
        XCTAssertGreaterThan(world.body(withID: id)!.position.x, 100)
    }

    func testSetRadiusChangesBodyRadius() {
        let world = World(size: Vector2(400, 400))
        let id = world.addRunner(at: Vector2(120, 80), radius: 42)
        world.setRadius(30, forBodyID: id)
        XCTAssertEqual(world.body(withID: id)?.radius, 30)
    }

    func testSetRadiusForUnknownBodyIsHarmless() {
        let world = World(size: Vector2(400, 400))
        let id = world.addRunner(at: Vector2(120, 80), radius: 42)
        world.remove(bodyID: id)
        world.setRadius(30, forBodyID: id) // no crash
        XCTAssertTrue(world.bodies.isEmpty)
    }
}
