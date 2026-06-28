import Foundation
import SwiftAA
import AABridge

/// The major planets, as an ephemeris-source enum. Earth is excluded (we observe
/// from it). Pluto is included for astrology even though it is formally a dwarf
/// planet.
public enum Planet: Sendable, Hashable, CaseIterable {
    case mercury, venus, mars, jupiter, saturn, uranus, neptune, pluto
}

/// Planetary positions, backed by SwiftAA (MIT) — Meeus' algorithms, accurate to
/// roughly an arcsecond for modern dates. We expose only Sendable value types
/// (our own `EclipticCoordinates`); the SwiftAA objects never escape this file.
///
/// Returned longitudes are **apparent geocentric ecliptic** of date — the frame
/// the zodiac and the planetarium both want. Input Julian Days are treated as
/// Dynamical Time (ΔT ignored, sub-arcsecond over a day).
public enum Planets {

    /// Apparent geocentric ecliptic coordinates (λ, β) of a planet.
    public static func eclipticCoordinates(_ planet: Planet, at jd: JulianDay) -> EclipticCoordinates {
        let day = SwiftAA.JulianDay(jd.value)
        switch planet {
        case .pluto:
            return plutoGeocentric(at: jd)
        default:
            let body = Self.makeBody(planet, at: day)
            let details = body.allPlanetaryDetails
            return EclipticCoordinates(
                longitude: .degrees(details.ApparentGeocentricLongitude).normalized,
                latitude: .degrees(details.ApparentGeocentricLatitude)
            )
        }
    }

    /// Apparent geocentric ecliptic longitude of a planet (zodiac/astrology).
    public static func apparentEclipticLongitude(_ planet: Planet, at jd: JulianDay) -> Angle {
        eclipticCoordinates(planet, at: jd).longitude
    }

    /// Apparent geocentric equatorial coordinates (RA/Dec) of a planet — for the
    /// planetarium sky view.
    public static func position(_ planet: Planet, at jd: JulianDay) -> EquatorialCoordinates {
        CoordinateTransform.equatorial(
            fromEcliptic: eclipticCoordinates(planet, at: jd),
            obliquity: Earth.meanObliquity(at: jd)
        )
    }

    private static func makeBody(_ planet: Planet, at day: SwiftAA.JulianDay) -> SwiftAA.Planet {
        switch planet {
        case .mercury: return Mercury(julianDay: day)
        case .venus: return Venus(julianDay: day)
        case .mars: return Mars(julianDay: day)
        case .jupiter: return Jupiter(julianDay: day)
        case .saturn: return Saturn(julianDay: day)
        case .uranus: return Uranus(julianDay: day)
        case .neptune: return Neptune(julianDay: day)
        case .pluto: fatalError("Pluto handled separately (DwarfPlanet)")
        }
    }

    /// Geocentric ecliptic coordinates of Pluto, of date.
    ///
    /// SwiftAA can't give Pluto a geocentric position, so we use Meeus ch. 37
    /// (heliocentric Pluto, J2000) and VSOP87 Earth (J2000), reduce by vector
    /// subtraction, then precess the resulting longitude to the equinox of date so
    /// it shares the zodiac frame of the other (apparent, of-date) planets.
    /// Light-time/aberration are ignored (< 1″). Valid 1885–2099 (Meeus 37).
    private static func plutoGeocentric(at jd: JulianDay) -> EclipticCoordinates {
        let j = jd.value

        // Heliocentric Pluto (J2000), degrees & AU.
        let lp = KPCAAPluto_EclipticLongitude(j) * .pi / 180.0
        let bp = KPCAAPluto_EclipticLatitude(j) * .pi / 180.0
        let rp = KPCAAPluto_RadiusVector(j)

        // Heliocentric Earth (J2000), degrees & AU.
        let le = KPCAAEarth_EclipticLongitudeJ2000(j, true) * .pi / 180.0
        let be = KPCAAEarth_EclipticLatitudeJ2000(j, true) * .pi / 180.0
        let re = KPCAAEarth_RadiusVector(j, true)

        // Rectangular ecliptic, then geocentric = Pluto − Earth.
        let x = rp * cos(bp) * cos(lp) - re * cos(be) * cos(le)
        let y = rp * cos(bp) * sin(lp) - re * cos(be) * sin(le)
        let z = rp * sin(bp) - re * sin(be)

        let lonJ2000 = atan2(y, x)
        let lat = atan2(z, (x * x + y * y).squareRoot())

        // Precess the ecliptic longitude from J2000 to the equinox of date
        // (general precession in longitude, Meeus eq. 21.x). β is ~unchanged.
        let t = jd.julianCenturiesSinceJ2000
        let precessionDeg = (5028.796195 * t + 1.1054348 * t * t) / 3600.0

        return EclipticCoordinates(
            longitude: (Angle.radians(lonJ2000) + .degrees(precessionDeg)).normalized,
            latitude: .radians(lat)
        )
    }
}
