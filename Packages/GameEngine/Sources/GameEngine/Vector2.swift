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
