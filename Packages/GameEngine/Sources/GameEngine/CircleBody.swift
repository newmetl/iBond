public typealias BodyID = Int

public struct CircleBody: Identifiable, Equatable {
    public enum Kind: Equatable {
        case player
        case npc
        /// Immovable obstacle: blocks circles and the laser, never moves.
        case rock
        /// Stationary hostile that ambushes the player (aiming/firing is
        /// driven by the app layer; the engine just hosts the body).
        case shooter
        /// Hostile that steers toward the player; kills on touch (app layer).
        case runner

        /// Hostile kinds are laser-killable and count toward the win condition.
        public var isHostile: Bool {
            switch self {
            case .npc, .shooter, .runner: return true
            case .player, .rock: return false
            }
        }
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
