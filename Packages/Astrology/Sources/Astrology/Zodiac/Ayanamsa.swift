import CelestialCore

/// The zodiac reference frame a chart is cast in.
///
/// `CelestialCore` produces **tropical** ecliptic longitudes (measured from the
/// vernal equinox of date). Sidereal charts subtract an *ayanamsa* — the
/// accumulated precessional offset between the tropical and a star-fixed zodiac.
public enum Zodiac: Sendable, Hashable {
    /// Tropical: 0° Aries pinned to the vernal equinox. Western default.
    case tropical
    /// Sidereal: star-fixed, via the chosen ayanamsa (Vedic/Jyotish).
    case sidereal(Ayanamsa)

    /// Convert a tropical ecliptic longitude into this frame at the given instant.
    public func longitude(fromTropical tropical: Angle, at jd: JulianDay) -> Angle {
        switch self {
        case .tropical:
            return tropical.normalized
        case .sidereal(let ayanamsa):
            return (tropical - ayanamsa.value(at: jd)).normalized
        }
    }
}

/// An ayanamsa: the tropical→sidereal offset as a function of date. It drifts
/// with precession (~50.3″/yr), so it is a function of time, not a constant.
///
/// v1 ships **Lahiri** (the Indian government standard, most widely used).
/// Other systems (Krishnamurti/KP, Raman, Fagan–Bradley) slot in as more cases.
public enum Ayanamsa: Sendable, Hashable {
    case lahiri

    /// The offset to subtract from a tropical longitude to obtain the sidereal
    /// longitude, at the given instant.
    public func value(at jd: JulianDay) -> Angle {
        switch self {
        case .lahiri:
            // Linear model: value at J2000.0 plus a constant precessional rate.
            // J2000 Lahiri ≈ 23°51.2′ (23.8534°); rate ≈ 50.29″/yr = 1.3969°/cy.
            // Yields ≈ 24°11′ for 2024, matching published tables to ~1′ across
            // the modern era. Refine to a higher-order series in a later pass.
            let t = jd.julianCenturiesSinceJ2000
            return .degrees(23.85340 + 1.396971 * t)
        }
    }
}
