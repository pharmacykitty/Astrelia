import Foundation

/// Sidereal time — the hour angle of the vernal equinox, i.e. "star time".
///
/// See Meeus, ch. 12. These return **mean** sidereal time; nutation (which turns
/// mean into *apparent* sidereal time) is a small correction added in a later phase.
public enum SiderealTime {
    /// Greenwich Mean Sidereal Time for the given instant, as an angle in [0°, 360°).
    /// Meeus, eq. 12.4 (valid for any UT, not just 0h).
    public static func greenwichMean(at jd: JulianDay) -> Angle {
        let d = jd.value - JulianDay.j2000.value
        let t = jd.julianCenturiesSinceJ2000
        let degrees = 280.46061837
            + 360.98564736629 * d
            + 0.000387933 * t * t
            - (t * t * t) / 38_710_000.0
        return Angle.degrees(degrees).normalized
    }

    /// Local Mean Sidereal Time for an observer at `longitude` (east-positive),
    /// as an angle in [0°, 360°).
    public static func localMean(at jd: JulianDay, longitude: Angle) -> Angle {
        (greenwichMean(at: jd) + longitude).normalized
    }
}
