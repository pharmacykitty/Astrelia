import Foundation

/// Apparent position of the Sun (Meeus, ch. 25 — the "low accuracy" method, good
/// to about 0.01°). Input Julian Days are treated as Dynamical Time; ΔT is ignored
/// for now (sub-arcsecond for the Sun over a day).
public enum Sun {
    /// Apparent geocentric equatorial coordinates of the Sun.
    public static func position(at jd: JulianDay) -> EquatorialCoordinates {
        let t = jd.julianCenturiesSinceJ2000

        // Geometric mean longitude and mean anomaly.
        let meanLongitude = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        let meanAnomaly = Angle.degrees(357.52911 + 35999.05029 * t - 0.0001537 * t * t)
        let m = meanAnomaly.radians

        // Equation of the centre.
        let center = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m)
            + (0.019993 - 0.000101 * t) * sin(2 * m)
            + 0.000289 * sin(3 * m)
        let trueLongitude = meanLongitude + center

        // Apparent longitude (nutation + aberration), with matching obliquity term.
        let omega = Angle.degrees(125.04 - 1934.136 * t)
        let apparentLongitude = Angle.degrees(trueLongitude - 0.00569 - 0.00478 * sin(omega.radians))
        let obliquity = Earth.meanObliquity(at: jd) + .degrees(0.00256 * cos(omega.radians))

        // The Sun's ecliptic latitude is ~0.
        return CoordinateTransform.equatorial(
            fromEcliptic: EclipticCoordinates(longitude: apparentLongitude, latitude: .zero),
            obliquity: obliquity
        )
    }

    /// Apparent ecliptic longitude of the Sun (useful for the zodiac / astrology later).
    public static func apparentEclipticLongitude(at jd: JulianDay) -> Angle {
        let t = jd.julianCenturiesSinceJ2000
        let meanLongitude = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        let meanAnomaly = Angle.degrees(357.52911 + 35999.05029 * t - 0.0001537 * t * t)
        let m = meanAnomaly.radians
        let center = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m)
            + (0.019993 - 0.000101 * t) * sin(2 * m)
            + 0.000289 * sin(3 * m)
        let omega = Angle.degrees(125.04 - 1934.136 * t)
        return Angle.degrees(meanLongitude + center - 0.00569 - 0.00478 * sin(omega.radians)).normalized
    }
}
