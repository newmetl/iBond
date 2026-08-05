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
