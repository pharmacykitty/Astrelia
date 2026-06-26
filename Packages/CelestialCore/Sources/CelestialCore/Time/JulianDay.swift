import Foundation

/// A Julian Day number — the continuous count of days since noon UTC on
/// 1 January 4713 BC. The common time backbone for astronomical computation.
///
/// See Meeus, *Astronomical Algorithms*, ch. 7. Calendar conversions here assume
/// the **Gregorian** calendar, which is valid for all modern dates.
public struct JulianDay: Sendable, Hashable, Comparable {
    public var value: Double
    public init(_ value: Double) { self.value = value }

    /// The J2000.0 standard epoch: 2000 January 1, 12:00 ≈ JD 2451545.0.
    public static let j2000 = JulianDay(2451545.0)

    /// JD of the Unix epoch (1970-01-01 00:00:00 UTC).
    public static let unixEpoch = JulianDay(2440587.5)

    /// Julian centuries elapsed since J2000.0 — the `T` used throughout Meeus.
    public var julianCenturiesSinceJ2000: Double {
        (value - JulianDay.j2000.value) / 36525.0
    }

    public static func < (lhs: JulianDay, rhs: JulianDay) -> Bool { lhs.value < rhs.value }
}

extension JulianDay {
    /// Build a Julian Day from a Gregorian calendar date with a fractional day
    /// (e.g. `day: 4.81` for the 4th at 19:26 UT). Meeus, eq. 7.1.
    public init(year: Int, month: Int, day: Double) {
        var y = year
        var m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = Int((Double(y) / 100.0).rounded(.down))
        let b = 2 - a + Int((Double(a) / 4.0).rounded(.down))
        let jd = (365.25 * Double(y + 4716)).rounded(.down)
            + (30.6001 * Double(m + 1)).rounded(.down)
            + day + Double(b) - 1524.5
        self.init(jd)
    }

    /// Build a Julian Day from an absolute `Date` (interpreted in UTC).
    public init(_ date: Date) {
        self.init(date.timeIntervalSince1970 / 86400.0 + JulianDay.unixEpoch.value)
    }
}
