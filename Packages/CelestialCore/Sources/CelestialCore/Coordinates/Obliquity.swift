/// Orientation of the Earth relevant to coordinate transforms.
public enum Earth {
    /// Mean obliquity of the ecliptic — the tilt of Earth's axis — for the mean
    /// equinox of date (Meeus eq. 22.2). Nutation (→ *true* obliquity) is a small
    /// correction added in a later phase.
    public static func meanObliquity(at jd: JulianDay) -> Angle {
        let t = jd.julianCenturiesSinceJ2000
        // 23°26′21.448″ − 46.8150″·T − 0.00059″·T² + 0.001813″·T³
        let arcseconds = 21.448 - 46.8150 * t - 0.00059 * t * t + 0.001813 * t * t * t
        return .degrees(23.0 + 26.0 / 60.0 + arcseconds / 3600.0)
    }
}
