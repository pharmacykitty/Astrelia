import CelestialCore
import Foundation

/// Supplies **tropical** geocentric ecliptic longitudes (and optional speeds)
/// for chart bodies. Decoupled so the chart engine is testable with fixed
/// positions and so the planet ephemeris (spec Phase B, SwiftAA) can be swapped
/// in without touching chart/house/aspect code.
public protocol EphemerisProvider: Sendable {
    /// Tropical ecliptic longitude of `body` at `jd`, or nil if this provider
    /// cannot compute it (e.g. planets before Phase B is wired).
    func longitude(of body: AstroBody, at jd: JulianDay) -> Angle?
    /// Longitude velocity in degrees/day, or nil if unknown.
    func speed(of body: AstroBody, at jd: JulianDay) -> Double?
}

extension EphemerisProvider {
    /// Default speed: central finite difference of `longitude`, if available.
    public func speed(of body: AstroBody, at jd: JulianDay) -> Double? {
        let h = 0.5 // days
        guard
            let l1 = longitude(of: body, at: JulianDay(jd.value - h)),
            let l2 = longitude(of: body, at: JulianDay(jd.value + h))
        else { return nil }
        var d = (l2 - l1).degrees.truncatingRemainder(dividingBy: 360.0)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d / (2 * h)
    }

    /// Resolve a body to a full `BodyPosition` in the given zodiac frame, or nil
    /// if unavailable.
    public func position(of body: AstroBody, at jd: JulianDay, zodiac: Zodiac) -> BodyPosition? {
        guard let tropical = longitude(of: body, at: jd) else { return nil }
        let lon = zodiac.longitude(fromTropical: tropical, at: jd)
        return BodyPosition(body: body, longitude: lon, speed: speed(of: body, at: jd))
    }
}

/// The ephemeris for charts, built entirely on `CelestialCore`: Sun & Moon
/// (Meeus 25/47), the mean lunar nodes, and the planets Mercury–Pluto
/// (`CelestialCore.Planets`, SwiftAA-backed). Every body resolves; nothing
/// returns nil. See `docs/astrology-spec.md`.
public struct CelestialCoreEphemeris: EphemerisProvider {
    public init() {}

    public func longitude(of body: AstroBody, at jd: JulianDay) -> Angle? {
        switch body {
        case .sun:
            return Sun.apparentEclipticLongitude(at: jd).normalized
        case .moon:
            return Moon.geocentric(at: jd).ecliptic.longitude.normalized
        case .northNode:
            return Self.meanLunarNode(at: jd)
        case .southNode:
            return (Self.meanLunarNode(at: jd) + .degrees(180)).normalized
        case .mercury: return Planets.apparentEclipticLongitude(.mercury, at: jd)
        case .venus: return Planets.apparentEclipticLongitude(.venus, at: jd)
        case .mars: return Planets.apparentEclipticLongitude(.mars, at: jd)
        case .jupiter: return Planets.apparentEclipticLongitude(.jupiter, at: jd)
        case .saturn: return Planets.apparentEclipticLongitude(.saturn, at: jd)
        case .uranus: return Planets.apparentEclipticLongitude(.uranus, at: jd)
        case .neptune: return Planets.apparentEclipticLongitude(.neptune, at: jd)
        case .pluto: return Planets.apparentEclipticLongitude(.pluto, at: jd)
        case .chiron: return MinorBodies.apparentEclipticLongitude(.chiron, at: jd)
        case .ceres: return MinorBodies.apparentEclipticLongitude(.ceres, at: jd)
        case .pallas: return MinorBodies.apparentEclipticLongitude(.pallas, at: jd)
        case .juno: return MinorBodies.apparentEclipticLongitude(.juno, at: jd)
        case .vesta: return MinorBodies.apparentEclipticLongitude(.vesta, at: jd)
        case .blackMoonLilith: return MinorBodies.blackMoonLilith(at: jd)
        }
    }

    /// Mean longitude of the Moon's ascending node Ω (Meeus eq. 47.7), degrees.
    static func meanLunarNode(at jd: JulianDay) -> Angle {
        let t = jd.julianCenturiesSinceJ2000
        let deg = 125.0445479
            - 1934.1362891 * t
            + 0.0020754 * t * t
            + (t * t * t) / 467_441.0
            - (t * t * t * t) / 60_616_000.0
        return Angle.degrees(deg).normalized
    }
}
