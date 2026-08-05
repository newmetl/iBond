import XCTest
@testable import GameEngine

final class CollisionTests: XCTestCase {
    func testOverlappingEqualCirclesSeparateSymmetrically() {
        let world = World(size: Vector2(400, 400))
        let a = world.addNPC(at: Vector2(200, 200), radius: 10)
        let b = world.addNPC(at: Vector2(210, 200), radius: 10) // overlap: 10 < 20
        world.update(dt: 1.0 / 120.0)
        let pa = world.body(withID: a)!.position
        let pb = world.body(withID: b)!.position
        // Separated to at least touching, symmetrically about x = 205.
        XCTAssertGreaterThanOrEqual(pa.distance(to: pb), 20 - 1e-6)
        XCTAssertEqual(pa.x, 195, accuracy: 1e-6)
        XCTAssertEqual(pb.x, 215, accuracy: 1e-6)
        XCTAssertEqual(pa.y, 200, accuracy: 1e-6)
        XCTAssertEqual(pb.y, 200, accuracy: 1e-6)
    }

    func testConcentricCirclesStillSeparate() {
        let world = World(size: Vector2(400, 400))
        let a = world.addNPC(at: Vector2(200, 200), radius: 10)
        let b = world.addNPC(at: Vector2(200, 200), radius: 10)
        world.update(dt: 1.0 / 120.0)
        let dist = world.body(withID: a)!.position.distance(to: world.body(withID: b)!.position)
        XCTAssertGreaterThanOrEqual(dist, 20 - 1e-6)
    }

    func testMovingBodyTransfersVelocityToStaticBody() {
        let world = World(size: Vector2(400, 400))
        let mover = world.addNPC(at: Vector2(180, 200), radius: 10)
        let target = world.addNPC(at: Vector2(199, 200), radius: 10) // overlapping, mover heading +x
        world.setVelocity(Vector2(100, 0), forBodyID: mover)
        world.update(dt: 1.0 / 120.0)
        // Zero restitution, equal masses: mover stops, target takes the velocity.
        XCTAssertGreaterThan(world.body(withID: target)!.velocity.x, 0)
        XCTAssertLessThan(world.body(withID: mover)!.velocity.x, 100)
    }

    func testPlayerShovesNPCOverManySteps() {
        let world = World(size: Vector2(400, 400))
        world.addPlayer(at: Vector2(100, 200), radius: 16)
        let npc = world.addNPC(at: Vector2(160, 200), radius: 14)
        world.moveTarget = Vector2(300, 200)
        for _ in 0..<240 { world.update(dt: 1.0 / 120.0) } // 2 seconds
        // The NPC has been pushed well past its start; nothing overlaps.
        XCTAssertGreaterThan(world.body(withID: npc)!.position.x, 200)
        let p = world.body(withID: world.playerID!)!
        let n = world.body(withID: npc)!
        XCTAssertGreaterThanOrEqual(p.position.distance(to: n.position), 30 - 1e-6)
    }

    func testNPCDampingBleedsOffVelocity() {
        let world = World(size: Vector2(400, 400))
        let id = world.addNPC(at: Vector2(200, 200))
        world.setVelocity(Vector2(120, 0), forBodyID: id)
        for _ in 0..<120 { world.update(dt: 1.0 / 120.0) } // 1 second
        XCTAssertLessThan(world.body(withID: id)!.velocity.length, 10)
    }

    func testBodiesClampToWorldBounds() {
        let world = World(size: Vector2(400, 400))
        let id = world.addNPC(at: Vector2(395, 395), radius: 10)
        world.setVelocity(Vector2(500, 500), forBodyID: id)
        world.update(dt: 0.1)
        let p = world.body(withID: id)!.position
        XCTAssertEqual(p.x, 390, accuracy: 1e-6)
        XCTAssertEqual(p.y, 390, accuracy: 1e-6)
    }

    func testHeavierBodyIsDisplacedLessOnSeparation() {
        let world = World(size: Vector2(400, 400))
        let light = world.addNPC(at: Vector2(200, 200), radius: 10, mass: 1)
        let heavy = world.addNPC(at: Vector2(210, 200), radius: 10, mass: 3)
        world.update(dt: 1.0 / 120.0)
        let lightMoved = abs(world.body(withID: light)!.position.x - 200)
        let heavyMoved = abs(world.body(withID: heavy)!.position.x - 210)
        // Penetration 10, inverse-mass weights: light (1/1) takes 3/4 = 7.5,
        // heavy (1/3) takes 1/4 = 2.5.
        XCTAssertEqual(lightMoved, 7.5, accuracy: 1e-6)
        XCTAssertEqual(heavyMoved, 2.5, accuracy: 1e-6)
        XCTAssertEqual(lightMoved / heavyMoved, 3.0, accuracy: 1e-6)
    }

    func testBodiesStayInBoundsWhenSqueezedAgainstWall() {
        let world = World(size: Vector2(400, 400))
        world.addNPC(at: Vector2(385, 200), radius: 10)
        world.addNPC(at: Vector2(390, 200), radius: 10) // overlapping pair at the wall
        for _ in 0..<10 { world.update(dt: 1.0 / 120.0) }
        for body in world.bodies {
            XCTAssertLessThanOrEqual(body.position.x, 400 - body.radius + 1e-6)
            XCTAssertGreaterThanOrEqual(body.position.x, body.radius - 1e-6)
        }
    }
}
