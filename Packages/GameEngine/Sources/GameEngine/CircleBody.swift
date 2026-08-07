public typealias BodyID = Int

public struct CircleBody: Identifiable, Equatable {
    public enum Kind: Equatable {
        case player
        case npc
        /// Immovable obstacle: blocks circles and the laser, never moves.
        case rock
    }

    /// Static bodies take no integration, damping, or collision response.
    public var isStatic: Bool { kind == .rock }

    public let id: BodyID
    public let kind: Kind
    public var position: Vector2
    public var velocity: Vector2
    public var radius: Double
    /// Must be > 0 — collision response divides by mass.
    public var mass: Double
}
