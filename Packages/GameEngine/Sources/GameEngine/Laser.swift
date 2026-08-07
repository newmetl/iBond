/// Result of a laser cast: the first body struck (nil if none) and the beam's
/// final endpoint — a body's surface, or where the beam exits the world bounds.
public struct LaserHit: Equatable {
    public let bodyID: BodyID?
    public let point: Vector2
}

/// A reflective line segment. The laser bounces off it; circles can't pass it.
public struct Mirror: Equatable {
    public let start: Vector2
    public let end: Vector2

    public init(start: Vector2, end: Vector2) {
        self.start = start
        self.end = end
    }
}

/// The full beam geometry: `points` starts at the player's center, contains one
/// point per mirror bounce, and ends at the surface hit (or bounds exit).
/// `bodyID` is the body the final segment struck, nil on a miss.
public struct LaserPath: Equatable {
    public let points: [Vector2]
    public let bodyID: BodyID?
}

public extension World {
    /// Reflections stop after this many bounces (guards mirror "traps").
    static let maxLaserBounces = 5

    /// Casts a ray from the player's center through `aim`, reflecting off
    /// mirrors, until it hits a body, exits the bounds, or runs out of bounces.
    /// Returns nil when there is no player or `aim` is the player's center.
    func castLaserPath(through aim: Vector2) -> LaserPath? {
        guard let pid = playerID, let player = body(withID: pid) else { return nil }
        var origin = player.position
        let toAim = aim - origin
        guard toAim.length > .ulpOfOne else { return nil }
        var direction = toAim.normalized

        var points: [Vector2] = [origin]
        var bounces = 0
        while true {
            var bodyT = Double.infinity
            var bodyHit: BodyID?
            for body in bodies where body.id != pid {
                if let t = Self.rayCircleIntersection(origin: origin, direction: direction,
                                                      center: body.position, radius: body.radius),
                   t < bodyT {
                    bodyT = t
                    bodyHit = body.id
                }
            }

            var mirrorT = Double.infinity
            var mirrorNormal: Vector2?
            for mirror in mirrors {
                if let (t, normal) = Self.raySegmentIntersection(origin: origin, direction: direction,
                                                                 start: mirror.start, end: mirror.end),
                   t < mirrorT {
                    mirrorT = t
                    mirrorNormal = normal
                }
            }

            if let bodyHit, bodyT < mirrorT {
                points.append(origin + direction * bodyT)
                return LaserPath(points: points, bodyID: bodyHit)
            }

            if let normal = mirrorNormal {
                let hit = origin + direction * mirrorT
                points.append(hit)
                if bounces >= Self.maxLaserBounces {
                    return LaserPath(points: points, bodyID: nil)
                }
                bounces += 1
                direction = direction - normal * (2 * direction.dot(normal))
                // The reflected ray leaves the mirror plane, so the t > epsilon
                // guard in raySegmentIntersection prevents re-hitting it at t=0.
                origin = hit
                continue
            }

            points.append(boundsExit(origin: origin, direction: direction))
            return LaserPath(points: points, bodyID: nil)
        }
    }

    /// Single-hit view of `castLaserPath`: the final endpoint and struck body.
    func castLaser(through aim: Vector2) -> LaserHit? {
        guard let path = castLaserPath(through: aim), let end = path.points.last else { return nil }
        return LaserHit(bodyID: path.bodyID, point: end)
    }

    /// Smallest positive distance along the ray at which it enters the circle,
    /// or nil if the ray misses (or the circle is entirely behind the origin).
    /// Solves |origin + t*dir - center|² = r² for t.
    /// - Precondition: `direction` must be a unit vector — the quadratic below
    ///   assumes |direction| == 1.
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
        let epsilon = 1e-9 // rejects t≈0 self-intersection at the origin; not a tangent-behavior knob
        if tEnter > epsilon { return tEnter }
        if tExit > epsilon { return tExit } // origin inside the circle: hit the far side
        return nil
    }

    /// Distance along the ray at which it crosses the segment, plus the
    /// segment's unit normal (sign unspecified — reflection is sign-agnostic).
    /// Returns nil for parallel rays, hits behind the origin, or beyond the
    /// segment's ends. Solves origin + t*direction == start + s*(end-start).
    internal static func raySegmentIntersection(
        origin: Vector2, direction: Vector2, start: Vector2, end: Vector2
    ) -> (t: Double, normal: Vector2)? {
        let seg = end - start
        let cross = direction.x * seg.y - direction.y * seg.x
        guard abs(cross) > 1e-12 else { return nil } // parallel
        let diff = start - origin
        let t = (diff.x * seg.y - diff.y * seg.x) / cross
        let s = (diff.x * direction.y - diff.y * direction.x) / cross
        let epsilon = 1e-9
        guard t > epsilon, s >= 0, s <= 1 else { return nil }
        return (t, Vector2(-seg.y, seg.x).normalized)
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
