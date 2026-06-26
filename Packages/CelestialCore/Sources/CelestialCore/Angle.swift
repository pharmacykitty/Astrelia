import Foundation

/// A geometric angle, stored internally in radians.
///
/// Strongly typed on purpose: radians/degrees/hours confusion is the single most
/// common bug in astronomy code, so conversions are always explicit. Value-typed
/// and `Sendable`.
public struct Angle: Sendable, Hashable, Comparable, AdditiveArithmetic {
    /// The angle in radians.
    public var radians: Double

    public init(radians: Double) { self.radians = radians }

    /// Hours of right ascension → angle (1 hour = 15°).
    public static func hours(_ hours: Double) -> Angle { .degrees(hours * 15.0) }
    public static func degrees(_ degrees: Double) -> Angle { Angle(radians: degrees * .pi / 180.0) }
    public static func radians(_ radians: Double) -> Angle { Angle(radians: radians) }

    public var degrees: Double { radians * 180.0 / .pi }
    /// The angle expressed in hours of right ascension (15° per hour).
    public var hours: Double { degrees / 15.0 }

    public var sine: Double { Foundation.sin(radians) }
    public var cosine: Double { Foundation.cos(radians) }
    public var tangent: Double { Foundation.tan(radians) }

    /// Normalised into the half-open range [0, 2π) radians (i.e. [0°, 360°)).
    public var normalized: Angle {
        let twoPi = 2.0 * Double.pi
        var r = radians.truncatingRemainder(dividingBy: twoPi)
        if r < 0 { r += twoPi }
        return Angle(radians: r)
    }

    // MARK: AdditiveArithmetic / Comparable

    public static let zero = Angle(radians: 0)
    public static func + (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians + rhs.radians) }
    public static func - (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians - rhs.radians) }
    public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }

    // MARK: Inverse trig (return strongly-typed angles)

    public static func asin(_ value: Double) -> Angle { Angle(radians: Foundation.asin(value)) }
    public static func acos(_ value: Double) -> Angle { Angle(radians: Foundation.acos(value)) }
    public static func atan2(y: Double, x: Double) -> Angle { Angle(radians: Foundation.atan2(y, x)) }
}
