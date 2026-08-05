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
