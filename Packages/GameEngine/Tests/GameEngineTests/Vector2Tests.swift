import XCTest
@testable import GameEngine

final class Vector2Tests: XCTestCase {
    func testLength() {
        XCTAssertEqual(Vector2(3, 4).length, 5, accuracy: 1e-9)
        XCTAssertEqual(Vector2.zero.length, 0, accuracy: 1e-9)
    }

    func testNormalized() {
        let n = Vector2(10, 0).normalized
        XCTAssertEqual(n.x, 1, accuracy: 1e-9)
        XCTAssertEqual(n.y, 0, accuracy: 1e-9)
        // Degenerate case: zero vector normalizes to zero, not NaN.
        XCTAssertEqual(Vector2.zero.normalized.length, 0, accuracy: 1e-9)
    }

    func testDot() {
        XCTAssertEqual(Vector2(1, 0).dot(Vector2(0, 1)), 0, accuracy: 1e-9)
        XCTAssertEqual(Vector2(2, 3).dot(Vector2(4, 5)), 23, accuracy: 1e-9)
    }

    func testDistance() {
        XCTAssertEqual(Vector2(1, 1).distance(to: Vector2(4, 5)), 5, accuracy: 1e-9)
    }
}
