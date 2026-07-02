import Foundation
import AABridge

/// Minor bodies carried by the astrology layer: Chiron and the four classical
/// asteroids. (Black Moon Lilith is a lunar point, handled separately.)
public enum MinorBody: Sendable, Hashable, CaseIterable {
    case chiron, ceres, pallas, juno, vesta
}

/// Geocentric ecliptic positions for minor bodies, by two-body propagation of
/// JPL osculating elements.
///
/// **Accuracy.** Elements are heliocentric J2000 osculating elements from the
/// JPL Small-Body Database (epoch below). Two-body Kepler propagation ignores
/// planetary perturbations, so positions are good to ~1° near the epoch and
/// degrade with distance from it — historical natal dates (and Chiron, which is
/// dynamically chaotic) can be off by a few degrees. This lives in the symbolic
/// astrology layer, not the science; refresh the elements periodically.
public enum MinorBodies {

    /// Osculating element set: angles in degrees, `a` in AU, `n` in deg/day,
    /// referred to the J2000 ecliptic, valid at `epoch` (a Julian Day, TDB).
    struct Elements: Sendable {
        let e, a, i, om, w, ma, n: Double
    }

    /// JPL SBDB epoch for the bundled elements (≈ 2026-09-09 TDB).
    static let epoch = 2461200.5

    static func elements(_ body: MinorBody) -> Elements {
        switch body {
        case .ceres:  Elements(e: 0.07969229514816586, a: 2.765552595034094, i: 10.58802780183462,
                               om: 80.24862682043221, w: 73.29421453021587, ma: 274.4193463761342, n: 0.21430445064843)
        case .pallas: Elements(e: 0.2307000995648547, a: 2.769559010737709, i: 34.93279321851542,
                               om: 172.8866193357694, w: 310.9699161652136, ma: 254.2496521742734, n: 0.2138396029251949)
        case .juno:   Elements(e: 0.2556999836681878, a: 2.670989527103278, i: 12.98659236598085,
                               om: 169.8115953492418, w: 247.8950743075613, ma: 262.7322944883855, n: 0.2257853690721904)
        case .vesta:  Elements(e: 0.09020374382834395, a: 2.361365965127599, i: 7.143925545058711,
                               om: 103.701293265032, w: 151.4686478221564, ma: 81.19015607686903, n: 0.2716183613599909)
        case .chiron: Elements(e: 0.3797656311453571, a: 13.68426760850124, i: 6.930574468846328,
                               om: 209.2961258613147, w: 339.2878326589729, ma: 216.7198966018106, n: 0.0194702593257484)
        }
    }

    /// Apparent geocentric ecliptic longitude (of date) — the zodiac frame.
    public static func apparentEclipticLongitude(_ body: MinorBody, at jd: JulianDay) -> Angle {
        eclipticCoordinates(body, at: jd).longitude
    }

    public static func eclipticCoordinates(_ body: MinorBody, at jd: JulianDay) -> EclipticCoordinates {
        let el = elements(body)
        let j = jd.value
        let d2r = Double.pi / 180.0

        // Mean anomaly at jd, then eccentric & true anomaly.
        let M = ((el.ma + el.n * (j - epoch)).truncatingRemainder(dividingBy: 360.0)) * d2r
        let E = solveKepler(meanAnomaly: M, eccentricity: el.e)
        let nu = 2.0 * atan2((1 + el.e).squareRoot() * sin(E / 2),
                             (1 - el.e).squareRoot() * cos(E / 2))
        let r = el.a * (1 - el.e * cos(E))

        // Heliocentric ecliptic (J2000) via the Gaussian rotation by ω, i, Ω.
        let w = el.w * d2r, i = el.i * d2r, om = el.om * d2r
        let xo = r * cos(nu), yo = r * sin(nu)
        let cosw = cos(w), sinw = sin(w), cosO = cos(om), sinO = sin(om), cosi = cos(i), sini = sin(i)
        let xh = xo * (cosO * cosw - sinO * sinw * cosi) - yo * (cosO * sinw + sinO * cosw * cosi)
        let yh = xo * (sinO * cosw + cosO * sinw * cosi) - yo * (sinO * sinw - cosO * cosw * cosi)
        let zh = xo * (sinw * sini) + yo * (cosw * sini)

        // Heliocentric Earth (J2000), rectangular ecliptic.
        let le = KPCAAEarth_EclipticLongitudeJ2000(j, true) * d2r
        let be = KPCAAEarth_EclipticLatitudeJ2000(j, true) * d2r
        let re = KPCAAEarth_RadiusVector(j, true)
        let xe = re * cos(be) * cos(le)
        let ye = re * cos(be) * sin(le)
        let ze = re * sin(be)

        // Geocentric = body − Earth.
        let xg = xh - xe, yg = yh - ye, zg = zh - ze
        let lonJ2000 = atan2(yg, xg)
        let lat = atan2(zg, (xg * xg + yg * yg).squareRoot())

        // Precess longitude J2000 → equinox of date (matches the Pluto path).
        let t = jd.julianCenturiesSinceJ2000
        let precessionDeg = (5028.796195 * t + 1.1054348 * t * t) / 3600.0

        return EclipticCoordinates(
            longitude: (Angle.radians(lonJ2000) + .degrees(precessionDeg)).normalized,
            latitude: .radians(lat)
        )
    }

    /// **Mean Black Moon Lilith** — the mean lunar apogee, longitude of date.
    /// = mean longitude of the perigee (L′ − M′, Meeus 47.1/47.4) + 180°.
    /// Mean elements are referred to the mean equinox of date, so no extra
    /// precession is applied. Moves ~40.69°/yr prograde.
    public static func blackMoonLilith(at jd: JulianDay) -> Angle {
        let t = jd.julianCenturiesSinceJ2000
        let Lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t * t
            + t * t * t / 538841.0 - t * t * t * t / 65_194_000.0
        let Mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t * t
            + t * t * t / 69699.0 - t * t * t * t / 14_712_000.0
        return Angle.degrees(Lp - Mp + 180.0).normalized
    }

    private static func solveKepler(meanAnomaly M: Double, eccentricity e: Double) -> Double {
        var E = M
        for _ in 0..<60 {
            let d = (E - e * sin(E) - M) / (1 - e * cos(E))
            E -= d
            if abs(d) < 1e-12 { break }
        }
        return E
    }
}
