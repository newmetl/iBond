# iBond Milestone 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running iOS app where a player circle moves via first-finger taps/holds, fires a laser through a second finger's position, and physically shoves randomly placed NPC circles that die with an animation when lasered.

**Architecture:** A pure-Swift `GameEngine` Swift Package (vector math, circle bodies, collision resolution, laser raycast — zero UIKit/SpriteKit imports, fully unit-tested via `swift test`) consumed by a SwiftUI app hosting one SpriteKit `GameScene` that handles multi-touch input and mirrors engine state into nodes each frame. The Xcode project is generated with XcodeGen from `project.yml`.

**Tech Stack:** Swift 5.9+, Swift Package Manager, XCTest, SwiftUI (`SpriteView`), SpriteKit, XcodeGen, iOS 17+.

**Spec:** `docs/superpowers/specs/2026-08-05-ibond-milestone1-design.md`

---

## File Structure

```
project.yml                                  # XcodeGen project spec (generates iBond.xcodeproj — gitignored)
.gitignore
README.md                                    # how to generate/build/run
Packages/GameEngine/
  Package.swift
  Sources/GameEngine/
    Vector2.swift                            # SIMD2<Double> typealias + math extensions
    CircleBody.swift                         # body value type (id, kind, position, velocity, radius, mass)
    World.swift                              # bodies, update loop, movement, collisions, bounds, spawning
    Laser.swift                              # LaserHit + castLaser ray math + bounds exit
  Tests/GameEngineTests/
    Vector2Tests.swift
    WorldBodyTests.swift
    MovementTests.swift
    CollisionTests.swift
    LaserTests.swift
App/
  iBondApp.swift                             # SwiftUI @main + SpriteView host
  TouchController.swift                      # assigns movement/laser roles to touches by identity
  GameScene.swift                            # world setup, input wiring, render sync, laser + effects
```

Engine tests run on macOS with `swift test --package-path Packages/GameEngine` — no simulator needed. The app layer (touch + rendering) is verified by building and running in the iOS Simulator.

---

### Task 1: GameEngine package scaffold + Vector2

**Files:**
- Create: `Packages/GameEngine/Package.swift`
- Create: `Packages/GameEngine/Sources/GameEngine/Vector2.swift`
- Test: `Packages/GameEngine/Tests/GameEngineTests/Vector2Tests.swift`

- [ ] **Step 1: Create the package manifest**

`Packages/GameEngine/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GameEngine",
    products: [
        .library(name: "GameEngine", targets: ["GameEngine"])
    ],
    targets: [
        .target(name: "GameEngine"),
        .testTarget(name: "GameEngineTests", dependencies: ["GameEngine"])
    ]
)
```

- [ ] **Step 2: Write the failing test**

`Packages/GameEngine/Tests/GameEngineTests/Vector2Tests.swift`:

```swift
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
```

- [ ] **Step 3: Run test to verify it fails**

Run (from repo root): `swift test --package-path Packages/GameEngine`
Expected: FAIL to compile with "cannot find type 'Vector2' in scope"

- [ ] **Step 4: Write minimal implementation**

`Packages/GameEngine/Sources/GameEngine/Vector2.swift`:

```swift
/// 2D vector used throughout the engine. Built on the standard library's SIMD2,
/// which already provides +, -, *, / and .zero.
public typealias Vector2 = SIMD2<Double>

public extension Vector2 {
    var length: Double { (x * x + y * y).squareRoot() }

    /// Unit vector in the same direction; .zero for the zero vector (no NaNs).
    var normalized: Vector2 {
        let l = length
        return l > 0 ? self / l : .zero
    }

    func dot(_ other: Vector2) -> Double { x * other.x + y * other.y }

    func distance(to other: Vector2) -> Double { (other - self).length }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path Packages/GameEngine`
Expected: PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add Packages
git commit -m "feat(engine): GameEngine package with Vector2 math"
```

---

### Task 2: CircleBody + World body management

**Files:**
- Create: `Packages/GameEngine/Sources/GameEngine/CircleBody.swift`
- Create: `Packages/GameEngine/Sources/GameEngine/World.swift`
- Test: `Packages/GameEngine/Tests/GameEngineTests/WorldBodyTests.swift`

- [ ] **Step 1: Write the failing test**

`Packages/GameEngine/Tests/GameEngineTests/WorldBodyTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/GameEngine`
Expected: FAIL to compile with "cannot find 'World' in scope"

- [ ] **Step 3: Write minimal implementation**

`Packages/GameEngine/Sources/GameEngine/CircleBody.swift`:

```swift
public typealias BodyID = Int

public struct CircleBody: Identifiable, Equatable {
    public enum Kind: Equatable {
        case player
        case npc
    }

    public let id: BodyID
    public let kind: Kind
    public var position: Vector2
    public var velocity: Vector2
    public var radius: Double
    public var mass: Double
}
```

`Packages/GameEngine/Sources/GameEngine/World.swift`:

```swift
/// The simulation. Owns all bodies and a rectangular play area from (0,0) to `size`.
/// Coordinates are screen points; SpriteKit's bottom-left origin is used as-is.
public final class World {
    public private(set) var bodies: [CircleBody] = []
    public var size: Vector2
    public private(set) var playerID: BodyID?

    /// Where the player is currently heading; nil means stand still.
    public var moveTarget: Vector2?
    /// Player movement speed in points per second.
    public var playerSpeed: Double = 320
    /// Exponential-ish velocity damping applied to NPCs so pushes fade out.
    public var npcDamping: Double = 4

    private var nextID: BodyID = 0

    public init(size: Vector2) {
        self.size = size
    }

    @discardableResult
    public func addPlayer(at position: Vector2, radius: Double = 16, mass: Double = 1) -> BodyID {
        let id = makeID()
        bodies.append(CircleBody(id: id, kind: .player, position: position,
                                 velocity: .zero, radius: radius, mass: mass))
        playerID = id
        return id
    }

    @discardableResult
    public func addNPC(at position: Vector2, radius: Double = 14, mass: Double = 1) -> BodyID {
        let id = makeID()
        bodies.append(CircleBody(id: id, kind: .npc, position: position,
                                 velocity: .zero, radius: radius, mass: mass))
        return id
    }

    public func body(withID id: BodyID) -> CircleBody? {
        bodies.first { $0.id == id }
    }

    public func remove(bodyID id: BodyID) {
        bodies.removeAll { $0.id == id }
        if playerID == id { playerID = nil }
    }

    /// Rejection-samples a spawn position inside bounds that keeps a small margin
    /// to every existing body. Returns nil if the world is too crowded (or too small).
    public func randomFreePosition<R: RandomNumberGenerator>(
        radius: Double, using rng: inout R, attempts: Int = 100
    ) -> Vector2? {
        let margin = 8.0
        guard size.x > 2 * radius, size.y > 2 * radius else { return nil }
        for _ in 0..<attempts {
            let p = Vector2(Double.random(in: radius...(size.x - radius), using: &rng),
                            Double.random(in: radius...(size.y - radius), using: &rng))
            let isFree = bodies.allSatisfy { $0.position.distance(to: p) >= $0.radius + radius + margin }
            if isFree { return p }
        }
        return nil
    }

    private func makeID() -> BodyID {
        defer { nextID += 1 }
        return nextID
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/GameEngine`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add Packages
git commit -m "feat(engine): CircleBody and World body management with spawn sampling"
```

---

### Task 3: Player target-seek movement

**Files:**
- Modify: `Packages/GameEngine/Sources/GameEngine/World.swift` (add `update(dt:)`, `seekPlayer`, integration)
- Test: `Packages/GameEngine/Tests/GameEngineTests/MovementTests.swift`

- [ ] **Step 1: Write the failing test**

`Packages/GameEngine/Tests/GameEngineTests/MovementTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/GameEngine`
Expected: FAIL to compile with "value of type 'World' has no member 'update'"

- [ ] **Step 3: Write minimal implementation**

Add to `Packages/GameEngine/Sources/GameEngine/World.swift` (inside `World`):

```swift
    /// Advance the simulation by one fixed timestep.
    public func update(dt: Double) {
        seekPlayer(dt: dt)
        integrate(dt: dt)
    }

    private func seekPlayer(dt: Double) {
        guard let pid = playerID, let idx = bodies.firstIndex(where: { $0.id == pid }) else { return }
        guard let target = moveTarget else {
            // No destination: the player is kinematic, so collision impulses
            // must not leave it drifting.
            bodies[idx].velocity = .zero
            return
        }
        let toTarget = target - bodies[idx].position
        if toTarget.length <= playerSpeed * dt {
            bodies[idx].position = target
            bodies[idx].velocity = .zero
            moveTarget = nil
        } else {
            bodies[idx].velocity = toTarget.normalized * playerSpeed
        }
    }

    private func integrate(dt: Double) {
        for i in bodies.indices {
            bodies[i].position += bodies[i].velocity * dt
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/GameEngine`
Expected: PASS (11 tests)

- [ ] **Step 5: Commit**

```bash
git add Packages
git commit -m "feat(engine): player target-seek movement with arrival snapping"
```

---

### Task 4: Collision resolution, NPC damping, bounds clamping

**Files:**
- Modify: `Packages/GameEngine/Sources/GameEngine/World.swift` (extend `update(dt:)`; add `resolveCollisions`, `applyDamping`, `clampToBounds`)
- Test: `Packages/GameEngine/Tests/GameEngineTests/CollisionTests.swift`

- [ ] **Step 1: Write the failing test**

`Packages/GameEngine/Tests/GameEngineTests/CollisionTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/GameEngine`
Expected: FAIL to compile with "value of type 'World' has no member 'setVelocity'"

- [ ] **Step 3: Write minimal implementation**

In `Packages/GameEngine/Sources/GameEngine/World.swift`, replace `update(dt:)` and add the new methods (inside `World`):

```swift
    /// Advance the simulation by one fixed timestep.
    public func update(dt: Double) {
        seekPlayer(dt: dt)
        integrate(dt: dt)
        resolveCollisions()
        applyDamping(dt: dt)
        clampToBounds()
    }

    /// Test/AI hook: directly set a body's velocity.
    public func setVelocity(_ velocity: Vector2, forBodyID id: BodyID) {
        guard let idx = bodies.firstIndex(where: { $0.id == id }) else { return }
        bodies[idx].velocity = velocity
    }

    /// Pairwise circle-circle response: positional separation weighted by inverse
    /// mass, plus a zero-restitution impulse so bodies push rather than bounce.
    private func resolveCollisions() {
        guard bodies.count > 1 else { return }
        for i in 0..<(bodies.count - 1) {
            for j in (i + 1)..<bodies.count {
                var a = bodies[i]
                var b = bodies[j]
                let delta = b.position - a.position
                let dist = delta.length
                let minDist = a.radius + b.radius
                guard dist < minDist else { continue }

                // Concentric circles have no meaningful normal; pick +x.
                let normal = dist > 0 ? delta / dist : Vector2(1, 0)
                let invA = 1 / a.mass
                let invB = 1 / b.mass
                let invSum = invA + invB

                let penetration = minDist - dist
                a.position -= normal * (penetration * invA / invSum)
                b.position += normal * (penetration * invB / invSum)

                let approachSpeed = (b.velocity - a.velocity).dot(normal)
                if approachSpeed < 0 {
                    let impulse = -approachSpeed / invSum
                    a.velocity -= normal * (impulse * invA)
                    b.velocity += normal * (impulse * invB)
                }

                bodies[i] = a
                bodies[j] = b
            }
        }
    }

    private func applyDamping(dt: Double) {
        let factor = max(0, 1 - npcDamping * dt)
        for i in bodies.indices where bodies[i].kind == .npc {
            bodies[i].velocity *= factor
        }
    }

    private func clampToBounds() {
        for i in bodies.indices {
            let r = bodies[i].radius
            bodies[i].position.x = min(max(bodies[i].position.x, r), size.x - r)
            bodies[i].position.y = min(max(bodies[i].position.y, r), size.y - r)
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/GameEngine`
Expected: PASS (17 tests)

- [ ] **Step 5: Commit**

```bash
git add Packages
git commit -m "feat(engine): circle collision response, NPC damping, bounds clamping"
```

---

### Task 5: Laser raycast

**Files:**
- Create: `Packages/GameEngine/Sources/GameEngine/Laser.swift`
- Test: `Packages/GameEngine/Tests/GameEngineTests/LaserTests.swift`

- [ ] **Step 1: Write the failing test**

`Packages/GameEngine/Tests/GameEngineTests/LaserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/GameEngine`
Expected: FAIL to compile with "value of type 'World' has no member 'castLaser'"

- [ ] **Step 3: Write minimal implementation**

`Packages/GameEngine/Sources/GameEngine/Laser.swift`:

```swift
/// Result of a laser cast: the first NPC struck (nil if none) and the beam's
/// endpoint — the NPC's surface, or where the beam exits the world bounds.
public struct LaserHit: Equatable {
    public let bodyID: BodyID?
    public let point: Vector2
}

public extension World {
    /// Casts a ray from the player's center through `aim`. Returns nil when there
    /// is no player or the aim point coincides with the player's center.
    func castLaser(through aim: Vector2) -> LaserHit? {
        guard let pid = playerID, let player = body(withID: pid) else { return nil }
        let origin = player.position
        let toAim = aim - origin
        guard toAim.length > .ulpOfOne else { return nil }
        let dir = toAim.normalized

        var nearestT = Double.infinity
        var nearestID: BodyID?
        for body in bodies where body.id != pid {
            guard let t = Self.rayCircleIntersection(origin: origin, direction: dir,
                                                     center: body.position, radius: body.radius),
                  t < nearestT else { continue }
            nearestT = t
            nearestID = body.id
        }

        if let nearestID {
            return LaserHit(bodyID: nearestID, point: origin + dir * nearestT)
        }
        return LaserHit(bodyID: nil, point: boundsExit(origin: origin, direction: dir))
    }

    /// Smallest positive distance along the ray at which it enters the circle,
    /// or nil if the ray misses (or the circle is entirely behind the origin).
    /// Solves |origin + t*dir - center|² = r² for t.
    internal static func rayCircleIntersection(
        origin: Vector2, direction: Vector2, center: Vector2, radius: Double
    ) -> Double? {
        let oc = center - origin
        let tCenter = oc.dot(direction)
        let discriminant = tCenter * tCenter - (oc.dot(oc) - radius * radius)
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        let tEnter = tCenter - root
        let tExit = tCenter + root
        let epsilon = 1e-9
        if tEnter > epsilon { return tEnter }
        if tExit > epsilon { return tExit } // origin inside the circle: hit the far side
        return nil
    }

    /// Point where a ray starting inside the bounds rectangle leaves it.
    internal func boundsExit(origin: Vector2, direction: Vector2) -> Vector2 {
        var tMin = Double.infinity
        if direction.x > 0 { tMin = min(tMin, (size.x - origin.x) / direction.x) }
        if direction.x < 0 { tMin = min(tMin, -origin.x / direction.x) }
        if direction.y > 0 { tMin = min(tMin, (size.y - origin.y) / direction.y) }
        if direction.y < 0 { tMin = min(tMin, -origin.y / direction.y) }
        guard tMin.isFinite else { return origin }
        return origin + direction * tMin
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/GameEngine`
Expected: PASS (25 tests)

- [ ] **Step 5: Commit**

```bash
git add Packages
git commit -m "feat(engine): laser raycast with nearest-NPC hit and bounds exit"
```

---

### Task 6: App scaffold (XcodeGen project + empty scene builds)

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `README.md`
- Create: `App/iBondApp.swift`
- Create: `App/GameScene.swift` (minimal placeholder; fleshed out in Task 7)

- [ ] **Step 1: Ensure XcodeGen is installed**

Run: `command -v xcodegen || brew install xcodegen`
Expected: a path like `/opt/homebrew/bin/xcodegen` (installing first if needed)

- [ ] **Step 2: Write the project spec**

`project.yml`:

```yaml
name: iBond
options:
  bundleIdPrefix: com.wojtekgorecki
  deploymentTarget:
    iOS: "17.0"
packages:
  GameEngine:
    path: Packages/GameEngine
targets:
  iBond:
    type: application
    platform: iOS
    sources:
      - App
    dependencies:
      - package: GameEngine
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight
        TARGETED_DEVICE_FAMILY: "1,2"
        SWIFT_VERSION: "5.9"
```

- [ ] **Step 3: Write .gitignore and README**

`.gitignore`:

```
.DS_Store
iBond.xcodeproj/
xcuserdata/
.build/
DerivedData/
```

`README.md`:

```markdown
# iBond

A 2D laser shooter for iOS, rebuilt from a 2011 idea with Swift + SpriteKit and a
custom physics engine. See `docs/superpowers/specs/` for the design.

## Controls
- **First finger** — tap to send the player circle somewhere; hold to make it follow.
- **Second finger** (while the first is down) — fires the laser from the player
  through your fingertip; move it to sweep the beam.

## Building
The Xcode project is generated, not checked in:

    brew install xcodegen   # once
    xcodegen                # writes iBond.xcodeproj
    open iBond.xcodeproj

Engine unit tests (no simulator needed):

    swift test --package-path Packages/GameEngine
```

- [ ] **Step 4: Write the app entry point and placeholder scene**

`App/iBondApp.swift`:

```swift
import SwiftUI
import SpriteKit

@main
struct IBondApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
        }
    }
}

struct GameView: View {
    @State private var scene: GameScene = {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .statusBarHidden()
    }
}
```

`App/GameScene.swift` (placeholder for this task):

```swift
import SpriteKit

final class GameScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1)
    }
}
```

- [ ] **Step 5: Generate the project and build for the simulator**

Run: `xcodegen`
Expected: `Created project at .../iBond.xcodeproj`

Run: `xcrun simctl list devices available | grep -m1 iPhone`
Expected: at least one available iPhone simulator; use its name below (example uses iPhone 16).

Run: `xcodebuild -project iBond.xcodeproj -scheme iBond -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add project.yml .gitignore README.md App
git commit -m "feat(app): SwiftUI + SpriteKit app scaffold via XcodeGen"
```

---

### Task 7: Render the world (player, aim line, NPCs)

**Files:**
- Modify: `App/GameScene.swift` (replace placeholder entirely with the version below)

No engine unit tests here — this is the render layer; verified by building now and running in Task 10.

- [ ] **Step 1: Implement world setup and node sync**

Replace `App/GameScene.swift` with:

```swift
import SpriteKit
import GameEngine

final class GameScene: SKScene {
    private var world: World?
    private var playerNode: SKShapeNode?
    private var npcNodes: [BodyID: SKShapeNode] = [:]

    private var lastUpdateTime: TimeInterval?
    private var accumulator: Double = 0
    private let fixedStep: Double = 1.0 / 120.0

    private let playerRadius: Double = 16
    private let npcRadius: Double = 14
    private let npcCount = 8

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1)
        view.isMultipleTouchEnabled = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Rotation / first layout: keep engine bounds in sync; bodies re-clamp
        // on the next update.
        world?.size = Vector2(size.width, size.height)
    }

    override func update(_ currentTime: TimeInterval) {
        ensureWorld()
        guard let world else { return }

        let dt: Double
        if let last = lastUpdateTime {
            dt = min(currentTime - last, 0.1) // clamp long pauses (backgrounding)
        } else {
            dt = 0
        }
        lastUpdateTime = currentTime

        accumulator += dt
        while accumulator >= fixedStep {
            world.update(dt: fixedStep)
            accumulator -= fixedStep
        }

        syncNodes()
    }

    // MARK: - World setup

    /// The scene's size is zero until SpriteView lays it out, so the world is
    /// created lazily on the first sized update.
    private func ensureWorld() {
        guard world == nil, size.width > 0, size.height > 0 else { return }
        let world = World(size: Vector2(size.width, size.height))

        world.addPlayer(at: Vector2(size.width / 2, size.height / 2), radius: playerRadius)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<npcCount {
            guard let position = world.randomFreePosition(radius: npcRadius, using: &rng) else { break }
            world.addNPC(at: position, radius: npcRadius)
        }
        self.world = world
        buildNodes(for: world)
    }

    private func buildNodes(for world: World) {
        let player = makeCircleNode(radius: playerRadius,
                                    fill: SKColor(red: 0.2, green: 0.85, blue: 1, alpha: 1))
        player.addChild(makeAimLineNode())
        addChild(player)
        playerNode = player

        for body in world.bodies where body.kind == .npc {
            let node = makeCircleNode(radius: npcRadius,
                                      fill: SKColor(red: 1, green: 0.45, blue: 0.35, alpha: 1))
            addChild(node)
            npcNodes[body.id] = node
        }
    }

    private func makeCircleNode(radius: Double, fill: SKColor) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: CGFloat(radius))
        node.fillColor = fill
        node.strokeColor = .white
        node.lineWidth = 1.5
        return node
    }

    /// The "gun barrel" line: drawn along +x from the rim outward; aiming rotates
    /// the whole player node.
    private func makeAimLineNode() -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: playerRadius * 2.2, y: 0))
        let line = SKShapeNode(path: path)
        line.strokeColor = .white
        line.lineWidth = 2
        return line
    }

    // MARK: - Render sync

    private func syncNodes() {
        guard let world else { return }
        for body in world.bodies {
            switch body.kind {
            case .player:
                playerNode?.position = CGPoint(x: body.position.x, y: body.position.y)
            case .npc:
                npcNodes[body.id]?.position = CGPoint(x: body.position.x, y: body.position.y)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project iBond.xcodeproj -scheme iBond -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add App/GameScene.swift
git commit -m "feat(app): render player, aim line, and NPCs from engine state"
```

---

### Task 8: Two-finger touch input (movement wired)

**Files:**
- Create: `App/TouchController.swift`
- Modify: `App/GameScene.swift` (add touch handlers + controller)

- [ ] **Step 1: Implement the touch role controller**

`App/TouchController.swift`:

```swift
import UIKit

/// Assigns roles to touches by identity: the first active touch steers the
/// player, any additional touch drives the laser. Roles are fixed at touch-down;
/// UITouch objects are never retained (Apple's rule) — only their identities.
final class TouchController {
    enum Role {
        case movement
        case laser
    }

    private var movementID: ObjectIdentifier?
    private var laserID: ObjectIdentifier?

    /// Returns the role assigned to a newly began touch, or nil if both roles
    /// are taken (extra fingers are ignored).
    func began(_ touch: UITouch) -> Role? {
        let id = ObjectIdentifier(touch)
        if movementID == nil {
            movementID = id
            return .movement
        }
        if laserID == nil {
            laserID = id
            return .laser
        }
        return nil
    }

    func role(of touch: UITouch) -> Role? {
        let id = ObjectIdentifier(touch)
        if id == movementID { return .movement }
        if id == laserID { return .laser }
        return nil
    }

    /// Clears and returns the touch's role. Call for both ended and cancelled.
    @discardableResult
    func ended(_ touch: UITouch) -> Role? {
        let id = ObjectIdentifier(touch)
        if id == movementID {
            movementID = nil
            return .movement
        }
        if id == laserID {
            laserID = nil
            return .laser
        }
        return nil
    }
}
```

- [ ] **Step 2: Wire touches into the scene**

In `App/GameScene.swift`, add properties (next to the other private vars):

```swift
    private let touchController = TouchController()
    private var laserAimPoint: CGPoint?   // set while the laser finger is down
```

and add the touch handlers (bottom of the class):

```swift
    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            switch touchController.began(touch) {
            case .movement:
                world?.moveTarget = Vector2(location.x, location.y)
            case .laser:
                laserAimPoint = location
            case nil:
                break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            switch touchController.role(of: touch) {
            case .movement:
                // Hold-to-follow: keep re-targeting the finger.
                world?.moveTarget = Vector2(location.x, location.y)
            case .laser:
                laserAimPoint = location
            case nil:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if touchController.ended(touch) == .laser {
                laserAimPoint = nil
            }
            // A lifted movement finger leaves its last target in place — a tap
            // means "go there", so the player keeps gliding to it.
        }
    }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project iBond.xcodeproj -scheme iBond -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add App/TouchController.swift App/GameScene.swift
git commit -m "feat(app): two-finger input — tap/hold movement, laser aim tracking"
```

---

### Task 9: Laser firing, kills, and hit effects

**Files:**
- Modify: `App/GameScene.swift` (laser beam node, spark node, aim rotation, kill animation)

- [ ] **Step 1: Add laser and spark nodes + per-frame laser processing**

In `App/GameScene.swift`, add properties (next to the other private vars):

```swift
    private var laserNode: SKShapeNode?
    private var sparkNode: SKShapeNode?
```

In `buildNodes(for:)`, append at the end:

```swift
        let laser = SKShapeNode()
        laser.strokeColor = SKColor(red: 1, green: 0.2, blue: 0.3, alpha: 1)
        laser.lineWidth = 3
        laser.glowWidth = 6
        laser.isHidden = true
        laser.zPosition = -1 // beam under the circles
        addChild(laser)
        laserNode = laser

        let spark = SKShapeNode(circleOfRadius: 5)
        spark.fillColor = SKColor(red: 1, green: 0.9, blue: 0.4, alpha: 1)
        spark.strokeColor = .clear
        spark.glowWidth = 8
        spark.isHidden = true
        spark.run(.repeatForever(.sequence([
            .scale(to: 1.4, duration: 0.08),
            .scale(to: 0.8, duration: 0.08),
        ])))
        addChild(spark)
        sparkNode = spark
```

At the end of `update(_:)`, after `syncNodes()`, add:

```swift
        processLaser()
```

Then add the laser section (bottom of the class):

```swift
    // MARK: - Laser

    private func processLaser() {
        guard let world else { return }
        guard let aim = laserAimPoint,
              let hit = world.castLaser(through: Vector2(aim.x, aim.y)),
              let player = world.playerID.flatMap({ world.body(withID: $0) }) else {
            laserNode?.isHidden = true
            sparkNode?.isHidden = true
            return
        }

        // Rotate the aim line to the firing direction (persists after release).
        let direction = hit.point - player.position
        playerNode?.zRotation = CGFloat(atan2(direction.y, direction.x))

        // Beam from the player's center to the hit point / bounds exit.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: player.position.x, y: player.position.y))
        path.addLine(to: CGPoint(x: hit.point.x, y: hit.point.y))
        laserNode?.path = path
        laserNode?.isHidden = false

        sparkNode?.position = CGPoint(x: hit.point.x, y: hit.point.y)
        sparkNode?.isHidden = false

        if let victimID = hit.bodyID {
            kill(npcID: victimID)
        }
    }

    /// Instant kill: remove from the simulation immediately, let the node play
    /// a short grow-and-fade before leaving the scene.
    private func kill(npcID: BodyID) {
        world?.remove(bodyID: npcID)
        guard let node = npcNodes.removeValue(forKey: npcID) else { return }
        node.run(.sequence([
            .group([
                .scale(to: 1.6, duration: 0.15),
                .fadeOut(withDuration: 0.15),
            ]),
            .removeFromParent(),
        ]))
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project iBond.xcodeproj -scheme iBond -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run all engine tests once more (regression)**

Run: `swift test --package-path Packages/GameEngine`
Expected: PASS (25 tests)

- [ ] **Step 4: Commit**

```bash
git add App/GameScene.swift
git commit -m "feat(app): laser beam with spark effect and NPC kill animation"
```

---

### Task 10: Run in the simulator and verify

**Files:** none (verification only)

- [ ] **Step 1: Launch in the iOS Simulator**

Build and install (substitute the available iPhone simulator name from Task 6):

```bash
xcodebuild -project iBond.xcodeproj -scheme iBond -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath DerivedData build
xcrun simctl boot "iPhone 16" || true
xcrun simctl install booted DerivedData/Build/Products/Debug-iphonesimulator/iBond.app
xcrun simctl launch booted com.wojtekgorecki.iBond
```

Expected: app launches; dark scene, cyan player circle with white aim line at center, 8 red NPC circles scattered without overlaps.

If the iOS Simulator MCP tools are available, prefer them: `attach` the live panel first so the user can watch, then `launch` the built app, then use `tap`/`touch_path`/`screenshot` for the checks below.

- [ ] **Step 2: Verify the checklist**

Using simulator interaction (single-finger checks work with normal clicks/taps; for two-finger laser checks in the Simulator app hold ⌥ Option for two-touch pinch mode, or drive `touch2_path` via the MCP tool):

- Tap an empty spot → player glides there and stops.
- Press and drag → player follows the finger.
- Walk the player into an NPC → the NPC is pushed aside; circles never overlap or tunnel.
- With one finger held, add a second → red beam from the player through the second finger, spark at the endpoint, aim line rotated to match.
- Sweep the beam across an NPC → it grows/fades out and is gone; the beam then continues to the next obstacle or screen edge.
- Rotate the device/simulator → everything stays inside the new bounds.

- [ ] **Step 3: Capture a screenshot for the user**

Take a screenshot (MCP `screenshot` action or `xcrun simctl io booted screenshot shot.png` into the scratchpad) and share it.

- [ ] **Step 4: Fix anything that fails verification, then final commit if any fixes were made**

```bash
git add -A
git commit -m "fix(app): milestone 1 verification fixes"
```

---

## Deviations & Notes

- **Multi-touch in the Simulator is awkward** (Option-key pinch only): full two-finger verification may need the MCP `touch2_path` tool or a real device. Note the limitation to the user if the laser gesture can't be fully exercised.
- The engine deliberately treats the player as kinematic (velocity zeroed when idle, re-set while seeking); only NPCs keep impulse velocity + damping. This is what makes shoving feel one-directional and stable.
- `iBond.xcodeproj` is generated by XcodeGen and gitignored; `project.yml` is the source of truth.
