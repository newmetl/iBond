/// The simulation. Owns all bodies and a rectangular play area from (0,0) to `size`.
/// Coordinates are screen points; SpriteKit's bottom-left origin is used as-is.
public final class World {
    public private(set) var bodies: [CircleBody] = []
    public private(set) var mirrors: [Mirror] = []
    public var size: Vector2
    public private(set) var playerID: BodyID?

    /// Where the player is currently heading; nil means stand still.
    public var moveTarget: Vector2?
    /// Direct velocity control (virtual joystick). When non-nil it overrides
    /// `moveTarget` entirely; the caller owns clamping to a sane speed.
    public var playerControlVelocity: Vector2?
    /// Player movement speed in points per second.
    public var playerSpeed: Double = 320
    /// Exponential-ish velocity damping applied to hostiles so pushes fade out.
    public var npcDamping: Double = 4
    /// Runner chase speed in points per second (~53% of the default playerSpeed).
    public var runnerSpeed: Double = 170
    /// Per-runner speed overrides (enemy tiers); falls back to `runnerSpeed`.
    public var runnerSpeedOverrides: [BodyID: Double] = [:]

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

    /// Adds a stationary ambusher. Aiming/firing logic lives in the app layer.
    @discardableResult
    public func addShooter(at position: Vector2, radius: Double = 14, mass: Double = 1) -> BodyID {
        let id = makeID()
        bodies.append(CircleBody(id: id, kind: .shooter, position: position,
                                 velocity: .zero, radius: radius, mass: mass))
        return id
    }

    /// Adds a runner that chases the player and kills on touch (app layer).
    /// Runners wait in place until `activateRunner(_:)` is called for them.
    @discardableResult
    public func addRunner(at position: Vector2, radius: Double = 14, mass: Double = 1) -> BodyID {
        let id = makeID()
        bodies.append(CircleBody(id: id, kind: .runner, position: position,
                                 velocity: .zero, radius: radius, mass: mass))
        return id
    }

    /// Adds an app-steered patrolling hostile: drive it with
    /// `setVelocity(_:forBodyID:)` each frame; the engine integrates, damps,
    /// and collides it like any hostile but never overrides its velocity.
    @discardableResult
    public func addHunter(at position: Vector2, radius: Double = 14, mass: Double = 1) -> BodyID {
        let id = makeID()
        bodies.append(CircleBody(id: id, kind: .hunter, position: position,
                                 velocity: .zero, radius: radius, mass: mass))
        return id
    }

    /// Adds a proximity mine: app-steered like the hunter — drive it with
    /// `setVelocity(_:forBodyID:)`; the engine integrates, damps, and
    /// collides it but never overrides its velocity.
    @discardableResult
    public func addMine(at position: Vector2, radius: Double = 7, mass: Double = 1) -> BodyID {
        let id = makeID()
        bodies.append(CircleBody(id: id, kind: .mine, position: position,
                                 velocity: .zero, radius: radius, mass: mass))
        return id
    }

    /// Runner IDs that have started chasing (one-way; set by the app when a
    /// runner first becomes visible on screen).
    public private(set) var activeRunnerIDs: Set<BodyID> = []

    public func activateRunner(_ id: BodyID) {
        guard body(withID: id)?.kind == .runner else { return }
        activeRunnerIDs.insert(id)
    }

    /// Adds an immovable rock obstacle. Blocks circles and the laser.
    @discardableResult
    public func addRock(at position: Vector2, radius: Double) -> BodyID {
        let id = makeID()
        bodies.append(CircleBody(id: id, kind: .rock, position: position,
                                 velocity: .zero, radius: radius, mass: 1))
        return id
    }

    public var rockIDs: [BodyID] {
        bodies.filter { $0.kind == .rock }.map(\.id)
    }

    /// Adds a reflective mirror segment. Reflects the laser; blocks circles.
    public func addMirror(from start: Vector2, to end: Vector2) {
        mirrors.append(Mirror(start: start, end: end))
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
        randomFreePosition(radius: radius,
                           in: Rect(min: .zero, max: size),
                           using: &rng, attempts: attempts)
    }

    /// Like `randomFreePosition(radius:using:attempts:)`, but samples only
    /// inside `region` (intersected with the radius-inset world bounds).
    public func randomFreePosition<R: RandomNumberGenerator>(
        radius: Double, in region: Rect, using rng: inout R, attempts: Int = 100
    ) -> Vector2? {
        let margin = 8.0
        let minX = Swift.max(region.min.x, radius)
        let maxX = Swift.min(region.max.x, size.x - radius)
        let minY = Swift.max(region.min.y, radius)
        let maxY = Swift.min(region.max.y, size.y - radius)
        guard minX <= maxX, minY <= maxY else { return nil }
        for _ in 0..<attempts {
            let p = Vector2(Double.random(in: minX...maxX, using: &rng),
                            Double.random(in: minY...maxY, using: &rng))
            let clearOfBodies = bodies.allSatisfy { $0.position.distance(to: p) >= $0.radius + radius + margin }
            let clearOfMirrors = mirrors.allSatisfy {
                Self.closestPoint(onSegment: $0.start, $0.end, to: p).distance(to: p) >= radius + margin
            }
            if clearOfBodies && clearOfMirrors { return p }
        }
        return nil
    }

    /// Advance the simulation by one fixed timestep. `dt` must be >= 0
    /// (the app's fixed-step accumulator guarantees this).
    public func update(dt: Double) {
        seekPlayer(dt: dt)
        steerRunners()
        integrate(dt: dt)
        resolveCollisions()
        resolveMirrorCollisions()
        applyDamping(dt: dt)
        clampToBounds()
        // Clamping can push a wall-pinned body back into a neighbor it was just
        // separated from; one more pass keeps pairs resolved within the frame.
        resolveCollisions()
        resolveMirrorCollisions()
        // ...and that pass must never leave a body outside the bounds for the
        // rendered frame — residual overlap heals next frame, protrusion won't.
        clampToBounds()
    }

    private func seekPlayer(dt: Double) {
        guard let pid = playerID, let idx = bodies.firstIndex(where: { $0.id == pid }) else { return }
        if let control = playerControlVelocity {
            bodies[idx].velocity = control
            return
        }
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

    /// Activated runners head straight for the player at `runnerSpeed`; with
    /// no player they stand down. Set before integration each step, so
    /// collision shoves still displace them but never deflect the chase.
    /// Un-activated runners wait in place (the app activates each runner the
    /// first time it appears on screen).
    private func steerRunners() {
        let target = playerID.flatMap { body(withID: $0)?.position }
        for i in bodies.indices where bodies[i].kind == .runner {
            guard activeRunnerIDs.contains(bodies[i].id) else { continue }
            guard let target else {
                bodies[i].velocity = .zero
                continue
            }
            let toPlayer = target - bodies[i].position
            let speed = runnerSpeedOverrides[bodies[i].id] ?? runnerSpeed
            bodies[i].velocity = toPlayer.length > 1 ? toPlayer.normalized * speed : .zero
        }
    }

    private func integrate(dt: Double) {
        for i in bodies.indices where !bodies[i].isStatic {
            bodies[i].position += bodies[i].velocity * dt
        }
    }

    /// Test/AI hook: directly set a body's velocity.
    public func setVelocity(_ velocity: Vector2, forBodyID id: BodyID) {
        guard let idx = bodies.firstIndex(where: { $0.id == id }) else { return }
        bodies[idx].velocity = velocity
    }

    /// Gameplay hook: change a body's collision/hit radius mid-game (e.g. a
    /// boss that shrinks as it takes damage). Collisions, laser hits, and
    /// bounds clamping all follow the new radius from the next step on.
    public func setRadius(_ radius: Double, forBodyID id: BodyID) {
        guard let idx = bodies.firstIndex(where: { $0.id == id }) else { return }
        bodies[idx].radius = radius
    }

    /// Pairwise circle-circle response: positional separation weighted by inverse
    /// mass, plus a zero-restitution impulse so bodies push rather than bounce.
    private func resolveCollisions() {
        guard bodies.count > 1 else { return }
        for i in 0..<(bodies.count - 1) {
            for j in (i + 1)..<bodies.count {
                var a = bodies[i]
                var b = bodies[j]
                // Phantoms (mines) ghost through every body.
                guard !a.isPhantom, !b.isPhantom else { continue }
                let delta = b.position - a.position
                let dist = delta.length
                let minDist = a.radius + b.radius
                guard dist < minDist else { continue }

                // Concentric circles have no meaningful normal; pick +x.
                let normal = dist > 0 ? delta / dist : Vector2(1, 0)
                // Static bodies have zero inverse mass: they absorb nothing,
                // the movable partner takes the full separation and impulse.
                let invA = a.isStatic ? 0 : 1 / a.mass
                let invB = b.isStatic ? 0 : 1 / b.mass
                let invSum = invA + invB
                guard invSum > 0 else { continue } // rock-rock: nothing to do

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

    /// Mirrors are static walls: any movable circle overlapping one is pushed
    /// out along the shortest exit, and its approach velocity is cancelled.
    private func resolveMirrorCollisions() {
        guard !mirrors.isEmpty else { return }
        for i in bodies.indices where !bodies[i].isStatic && !bodies[i].isPhantom {
            for mirror in mirrors {
                let closest = Self.closestPoint(onSegment: mirror.start, mirror.end,
                                                to: bodies[i].position)
                let delta = bodies[i].position - closest
                let dist = delta.length
                guard dist < bodies[i].radius else { continue }
                // Center exactly on the segment: push along the segment normal.
                let seg = mirror.end - mirror.start
                let normal = dist > 0 ? delta / dist : Vector2(-seg.y, seg.x).normalized
                bodies[i].position += normal * (bodies[i].radius - dist)
                let approach = bodies[i].velocity.dot(normal)
                if approach < 0 {
                    bodies[i].velocity -= normal * approach
                }
            }
        }
    }

    internal static func closestPoint(onSegment start: Vector2, _ end: Vector2,
                                      to point: Vector2) -> Vector2 {
        let seg = end - start
        let lengthSquared = seg.dot(seg)
        guard lengthSquared > 0 else { return start }
        let s = Swift.min(1, Swift.max(0, (point - start).dot(seg) / lengthSquared))
        return start + seg * s
    }

    private func applyDamping(dt: Double) {
        let factor = max(0, 1 - npcDamping * dt)
        for i in bodies.indices where bodies[i].kind.isHostile {
            bodies[i].velocity *= factor
        }
    }

    private func clampToBounds() {
        for i in bodies.indices where !bodies[i].isStatic {
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
