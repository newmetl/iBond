import XCTest
@testable import GameEngine

final class MovementTests: XCTestCase {
    func testPlayerMovesTowardTargetAtPlayerSpeed() {
        let world = World(size: Vector2(400, 400))
        let id = world.addPlayer(at: Vector2(100, 100))
        world.playerSpeed = 100
        world.moveTarget = Vector2(300, 100) // straight along +x
        world.update(dt: 0.5)
        let p = world.body(withID: id)!.position
        XCTAssertEqual(p.x, 150, accuracy: 1e-6) // 100 pt/s * 0.5 s
        XCTAssertEqual(p.y, 100, accuracy: 1e-6)
    }

    func testPlayerSnapsToTargetOnArrivalAndClearsIt() {
        let world = World(size: Vector2(400, 400))
        let id = world.addPlayer(at: Vector2(100, 100))
        world.playerSpeed = 100
        world.moveTarget = Vector2(110, 100) // 10 pt away, one 0.5 s step covers 50 pt
        world.update(dt: 0.5)
        let body = world.body(withID: id)!
        XCTAssertEqual(body.position, Vector2(110, 100))
        XCTAssertEqual(body.velocity, .zero)
        XCTAssertNil(world.moveTarget)
        // Further updates don't move it.
        world.update(dt: 0.5)
        XCTAssertEqual(world.body(withID: id)!.position, Vector2(110, 100))
    }

    func testPlayerStandsStillWithoutTarget() {
        let world = World(size: Vector2(400, 400))
        let id = world.addPlayer(at: Vector2(100, 100))
        world.update(dt: 1.0)
        XCTAssertEqual(world.body(withID: id)!.position, Vector2(100, 100))
    }

    func testPlayerMovesDiagonallyTowardTarget() {
        let world = World(size: Vector2(400, 400))
        let id = world.addPlayer(at: Vector2(100, 100))
        world.playerSpeed = 100
        world.moveTarget = Vector2(160, 180) // 3-4-5 triangle: direction (0.6, 0.8)
        world.update(dt: 0.5)
        let p = world.body(withID: id)!.position
        XCTAssertEqual(p.x, 130, accuracy: 1e-6) // 100 + 0.6 * 50
        XCTAssertEqual(p.y, 140, accuracy: 1e-6) // 100 + 0.8 * 50
    }

    func testMoveTargetExactlyAtPlayerPositionIsANoOp() {
        let world = World(size: Vector2(400, 400))
        let id = world.addPlayer(at: Vector2(100, 100))
        world.moveTarget = Vector2(100, 100)
        world.update(dt: 0.5)
        let body = world.body(withID: id)!
        XCTAssertEqual(body.position, Vector2(100, 100))
        XCTAssertEqual(body.velocity, .zero)
        XCTAssertNil(world.moveTarget)
    }
}
