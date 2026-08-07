import XCTest
@testable import GameEngine

final class MirrorTests: XCTestCase {
    /// Player at (100, 200) in a 400x400 world.
    private func makeWorld() -> World {
        let world = World(size: Vector2(400, 400))
        world.addPlayer(at: Vector2(100, 200), radius: 16)
        return world
    }

    // MARK: - Reflection geometry

    func testBeamReflectsOffDiagonalMirror() {
        // 45° mirror centered at (200, 200): beam fired along +x reflects to +y.
        let world = makeWorld()
        world.addMirror(from: Vector2(180, 180), to: Vector2(220, 220))
        let path = world.castLaserPath(through: Vector2(150, 200))!
        XCTAssertNil(path.bodyID)
        XCTAssertEqual(path.points.count, 3) // origin, bounce, bounds exit
        XCTAssertEqual(path.points[0], Vector2(100, 200))
        XCTAssertEqual(path.points[1].x, 200, accuracy: 1e-6) // hits mirror at (200,200)
        XCTAssertEqual(path.points[1].y, 200, accuracy: 1e-6)
        XCTAssertEqual(path.points[2].x, 200, accuracy: 1e-4) // straight up to top wall
        XCTAssertEqual(path.points[2].y, 400, accuracy: 1e-4)
    }

    func testReflectedBeamKillsNPCBehindRock() {
        // The bank-shot scenario: rock blocks the direct line; the mirror path hits.
        let world = makeWorld()
        world.addRock(at: Vector2(150, 275), radius: 30)   // sits on the direct player->NPC line
        world.addMirror(from: Vector2(180, 180), to: Vector2(220, 220)) // 45° at (200,200)
        let npc = world.addNPC(at: Vector2(200, 350), radius: 10)

        // Direct shot is blocked by the rock...
        let direct = world.castLaserPath(through: Vector2(200, 350))!
        XCTAssertEqual(direct.bodyID, world.rockIDs.first!)

        // ...but firing +x at the mirror banks the beam up into the NPC.
        let banked = world.castLaserPath(through: Vector2(150, 200))!
        XCTAssertEqual(banked.bodyID, npc)
        XCTAssertEqual(banked.points.count, 3)
        XCTAssertEqual(banked.points[2].x, 200, accuracy: 1e-4)
        XCTAssertEqual(banked.points[2].y, 340, accuracy: 1e-4) // NPC surface: 350 - 10
    }

    func testBeamStopsAtRockWithoutMirror() {
        let world = makeWorld()
        world.addRock(at: Vector2(250, 200), radius: 30)
        let path = world.castLaserPath(through: Vector2(150, 200))!
        XCTAssertEqual(path.bodyID, world.rockIDs.first!)
        XCTAssertEqual(path.points.count, 2)
        XCTAssertEqual(path.points[1].x, 220, accuracy: 1e-6)
    }

    func testParallelBeamMissesMirror() {
        let world = makeWorld()
        world.addMirror(from: Vector2(200, 100), to: Vector2(200, 300)) // vertical
        let path = world.castLaserPath(through: Vector2(100, 300))! // fire straight up, parallel plane offset
        XCTAssertNil(path.bodyID)
        XCTAssertEqual(path.points.count, 2)
        XCTAssertEqual(path.points[1].x, 100, accuracy: 1e-6)
        XCTAssertEqual(path.points[1].y, 400, accuracy: 1e-6) // top wall, no bounce
    }

    func testDoubleBounceBetweenTwoMirrors() {
        // Two 45° mirrors: beam goes right, up, then right again.
        let world = makeWorld()
        world.addMirror(from: Vector2(180, 180), to: Vector2(220, 220))  // at (200,200): +x -> +y
        world.addMirror(from: Vector2(180, 280), to: Vector2(220, 320))  // at (200,300): +y -> +x
        let path = world.castLaserPath(through: Vector2(150, 200))!
        XCTAssertNil(path.bodyID)
        XCTAssertEqual(path.points.count, 4) // origin, two bounces, exit
        XCTAssertEqual(path.points[1].x, 200, accuracy: 1e-4)
        XCTAssertEqual(path.points[1].y, 200, accuracy: 1e-4)
        XCTAssertEqual(path.points[2].x, 200, accuracy: 1e-4)
        XCTAssertEqual(path.points[2].y, 300, accuracy: 1e-4)
        XCTAssertEqual(path.points[3].x, 400, accuracy: 1e-4) // exits right wall
        XCTAssertEqual(path.points[3].y, 300, accuracy: 1e-4)
    }

    func testBounceLimitStopsInfiniteReflection() {
        // Two facing parallel mirrors trap the beam. Fired at a slight upward
        // angle, the zig-zag ascends past the player's own circle (a straight
        // back-and-forth would self-hit, which is its own test) and must
        // terminate at the bounce cap.
        let world = makeWorld()
        world.addMirror(from: Vector2(150, 100), to: Vector2(150, 300))
        world.addMirror(from: Vector2(50, 100), to: Vector2(50, 300))
        let path = world.castLaserPath(through: Vector2(150, 210))!
        XCTAssertNil(path.bodyID)
        // origin + maxBounces bounce points + terminal point
        XCTAssertLessThanOrEqual(path.points.count, World.maxLaserBounces + 2)
        XCTAssertGreaterThanOrEqual(path.points.count, World.maxLaserBounces + 1)
    }

    func testCastLaserStillReturnsFinalSegmentInfo() {
        // The single-hit API remains: final endpoint + body of the path.
        let world = makeWorld()
        world.addMirror(from: Vector2(180, 180), to: Vector2(220, 220))
        let npc = world.addNPC(at: Vector2(200, 350), radius: 10)
        let hit = world.castLaser(through: Vector2(150, 200))!
        XCTAssertEqual(hit.bodyID, npc)
        XCTAssertEqual(hit.point.x, 200, accuracy: 1e-4)
        XCTAssertEqual(hit.point.y, 340, accuracy: 1e-4)
    }

    // MARK: - Movement blocking

    func testPlayerCannotWalkThroughMirror() {
        let world = makeWorld() // player at (100, 200), radius 16
        world.addMirror(from: Vector2(200, 100), to: Vector2(200, 300)) // vertical wall
        world.moveTarget = Vector2(300, 200) // straight through it
        for _ in 0..<600 { world.update(dt: 1.0 / 120.0) } // 5 seconds
        let player = world.body(withID: world.playerID!)!
        XCTAssertLessThanOrEqual(player.position.x, 200 - 16 + 1) // stopped at the surface
    }

    func testOverlappingNPCIsPushedOutOfMirror() {
        let world = World(size: Vector2(400, 400))
        let npc = world.addNPC(at: Vector2(195, 200), radius: 14) // 5pt from the segment
        world.addMirror(from: Vector2(200, 100), to: Vector2(200, 300))
        world.update(dt: 1.0 / 120.0)
        let pos = world.body(withID: npc)!.position
        XCTAssertLessThanOrEqual(pos.x, 200 - 14 + 1e-6) // pushed clear, on its own side
        XCTAssertEqual(pos.y, 200, accuracy: 1e-6)
    }

    func testCircleNearMirrorEndpointIsPushedRadially() {
        let world = World(size: Vector2(400, 400))
        // NPC overlapping the segment's top endpoint diagonally.
        let npc = world.addNPC(at: Vector2(205, 305), radius: 14)
        world.addMirror(from: Vector2(200, 100), to: Vector2(200, 300))
        world.update(dt: 1.0 / 120.0)
        let pos = world.body(withID: npc)!.position
        // Pushed to at least radius away from the endpoint (200, 300).
        XCTAssertGreaterThanOrEqual(pos.distance(to: Vector2(200, 300)), 14 - 1e-6)
    }

    func testSpawnSamplingAvoidsMirrors() {
        let world = World(size: Vector2(200, 200))
        world.addMirror(from: Vector2(100, 0), to: Vector2(100, 200)) // full-height wall
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<30 {
            guard let p = world.randomFreePosition(radius: 14, using: &rng) else { continue }
            XCTAssertGreaterThanOrEqual(abs(p.x - 100), 14)
        }
    }

    func testMirrorEndpointsAreExposedForRendering() {
        let world = makeWorld()
        world.addMirror(from: Vector2(10, 20), to: Vector2(30, 40))
        XCTAssertEqual(world.mirrors.count, 1)
        XCTAssertEqual(world.mirrors[0].start, Vector2(10, 20))
        XCTAssertEqual(world.mirrors[0].end, Vector2(30, 40))
    }
}
