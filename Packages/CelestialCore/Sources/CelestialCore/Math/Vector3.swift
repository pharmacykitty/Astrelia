/// A 3D cartesian vector. Used for stars' rectangular positions (parsecs, in the
/// equatorial frame with the Sun at the origin) — the basis for Galaxy Map mode.
public struct Vector3: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Euclidean length of the vector.
    public var magnitude: Double { (x * x + y * y + z * z).squareRoot() }
}
