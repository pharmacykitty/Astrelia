/// Orientation of the Earth relevant to coordinate transforms.
public enum Earth {
    /// Mean obliquity of the ecliptic — the tilt of Earth's axis — for the mean
    /// equinox of date (Meeus eq. 22.2). This omits nutation; for apparent-place
    /// work use `trueObliquity(at:)`.
    public static func meanObliquity(at jd: JulianDay) -> Angle {
        let t = jd.julianCenturiesSinceJ2000
        // 23°26′21.448″ − 46.8150″·T − 0.00059″·T² + 0.001813″·T³
        let arcseconds = 21.448 - 46.8150 * t - 0.00059 * t * t + 0.001813 * t * t * t
        return .degrees(23.0 + 26.0 / 60.0 + arcseconds / 3600.0)
    }

    /// True obliquity of the ecliptic — the mean obliquity plus the nutation in
    /// obliquity, Δε (Meeus, ch. 22): ε = ε₀ + Δε. This is the obliquity to use
    /// in *apparent* ecliptic⇄equatorial transforms.
    public static func trueObliquity(at jd: JulianDay) -> Angle {
        meanObliquity(at: jd) + Nutation.obliquity(at: jd)
    }
}
