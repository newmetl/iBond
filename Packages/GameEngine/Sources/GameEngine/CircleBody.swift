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
