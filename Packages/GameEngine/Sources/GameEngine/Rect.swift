/// Axis-aligned rectangle in world coordinates.
public struct Rect: Equatable {
    public var min: Vector2
    public var max: Vector2

    public init(min: Vector2, max: Vector2) {
        self.min = min
        self.max = max
    }
}
