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

    /// Adds the player body. Call at most once per World — the engine drives a
    /// single player via `playerID`; a second call would orphan the first body.
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

    /// Advance the simulation by one fixed timestep. `dt` must be >= 0
    /// (the app's fixed-step accumulator guarantees this).
    public func update(dt: Double) {
        seekPlayer(dt: dt)
        integrate(dt: dt)
        resolveCollisions()
        applyDamping(dt: dt)
        clampToBounds()
        // Clamping can push a wall-pinned body back into a neighbor it was just
        // separated from; one more pass keeps pairs resolved within the frame.
        resolveCollisions()
        // ...and that pass must never leave a body outside the bounds for the
        // rendered frame — residual overlap heals next frame, protrusion won't.
        clampToBounds()
    }

    private func seekPlayer(dt: Double) {
        guard let pid = playerID, let idx = bodies.firstIndex(where: { $0.id == pid }) else { return }
        guard var target = moveTarget else {
            // No destination: the player is kinematic, so collision impulses
            // must not leave it drifting.
            bodies[idx].velocity = .zero
            return
        }
        // Targets are only reachable inside the playable rect (clampToBounds
        // stops the body one radius from each wall). Clamp so edge taps — or a
        // rotation that shrank the bounds — can't strand an unreachable target.
        let r = bodies[idx].radius
        target.x = min(max(target.x, r), size.x - r)
        target.y = min(max(target.y, r), size.y - r)
        moveTarget = target

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

    private func makeID() -> BodyID {
        defer { nextID += 1 }
        return nextID
    }
}
