import Foundation

/// Position and phase of the Moon (Meeus, ch. 47 — the truncated ELP-2000/82
/// series, accurate to roughly 10″ in longitude and 4″ in latitude). Input Julian
/// Days are treated as Dynamical Time; ΔT and nutation are ignored for now
/// (well under an arcminute, far below sensor accuracy).
public enum Moon {
    /// Geocentric ecliptic position and distance of the Moon.
    public struct Geocentric: Sendable, Hashable {
        public let ecliptic: EclipticCoordinates
        /// Earth–Moon distance in kilometres.
        public let distanceKm: Double
    }

    public static func geocentric(at jd: JulianDay) -> Geocentric {
        let t = jd.julianCenturiesSinceJ2000
        let rad = Double.pi / 180.0

        // Fundamental arguments (degrees).
        let lPrime = 218.3164477 + 481267.88123421 * t - 0.0015786 * t * t
            + t * t * t / 538841.0 - t * t * t * t / 65194000.0
        let d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t * t
            + t * t * t / 545868.0 - t * t * t * t / 113065000.0
        let m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t * t
            + t * t * t / 24490000.0
        let mPrime = 134.9633964 + 477198.8675055 * t + 0.0087414 * t * t
            + t * t * t / 69699.0 - t * t * t * t / 14712000.0
        let f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t * t
            - t * t * t / 3526000.0 + t * t * t * t / 863310000.0

        let e = 1.0 - 0.002516 * t - 0.0000074 * t * t
        let a1 = 119.75 + 131.849 * t
        let a2 = 53.09 + 479264.290 * t
        let a3 = 313.45 + 481266.484 * t

        var sumL = 0.0   // longitude (×1e-6 degrees)
        var sumR = 0.0   // distance  (×1e-3 km)
        for term in longitudeDistanceTerms {
            let argument = (Double(term.d) * d + Double(term.m) * m
                + Double(term.mp) * mPrime + Double(term.f) * f) * rad
            let eccentricity = term.eccentricityPower(e)
            sumL += Double(term.sine) * eccentricity * sin(argument)
            sumR += Double(term.cosine) * eccentricity * cos(argument)
        }

        var sumB = 0.0   // latitude (×1e-6 degrees)
        for term in latitudeTerms {
            let argument = (Double(term.d) * d + Double(term.m) * m
                + Double(term.mp) * mPrime + Double(term.f) * f) * rad
            sumB += Double(term.sine) * term.eccentricityPower(e) * sin(argument)
        }

        // Additive (planetary / flattening) terms.
        sumL += 3958.0 * sin(a1 * rad)
            + 1962.0 * sin((lPrime - f) * rad)
            + 318.0 * sin(a2 * rad)
        sumB += -2235.0 * sin(lPrime * rad)
            + 382.0 * sin(a3 * rad)
            + 175.0 * sin((a1 - f) * rad)
            + 175.0 * sin((a1 + f) * rad)
            + 127.0 * sin((lPrime - mPrime) * rad)
            - 115.0 * sin((lPrime + mPrime) * rad)

        let longitude = Angle.degrees(lPrime + sumL / 1_000_000.0).normalized
        let latitude = Angle.degrees(sumB / 1_000_000.0)
        let distance = 385000.56 + sumR / 1000.0

        return Geocentric(
            ecliptic: EclipticCoordinates(longitude: longitude, latitude: latitude),
            distanceKm: distance
        )
    }

    /// Apparent geocentric equatorial coordinates of the Moon.
    public static func position(at jd: JulianDay) -> EquatorialCoordinates {
        CoordinateTransform.equatorial(
            fromEcliptic: geocentric(at: jd).ecliptic,
            obliquity: Earth.meanObliquity(at: jd)
        )
    }

    /// Illumination and waxing/waning state of the Moon (Meeus, ch. 48).
    public static func phase(at jd: JulianDay) -> MoonPhase {
        let t = jd.julianCenturiesSinceJ2000
        let rad = Double.pi / 180.0

        let d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t * t
            + t * t * t / 545868.0 - t * t * t * t / 113065000.0
        let m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t * t + t * t * t / 24490000.0
        let mPrime = 134.9633964 + 477198.8675055 * t + 0.0087414 * t * t
            + t * t * t / 69699.0 - t * t * t * t / 14712000.0

        // Phase angle of the Moon (Sun–Moon–Earth), Meeus eq. 48.4.
        let phaseAngle = 180.0 - d
            - 6.289 * sin(mPrime * rad)
            + 2.100 * sin(m * rad)
            - 1.274 * sin((2.0 * d - mPrime) * rad)
            - 0.658 * sin(2.0 * d * rad)
            - 0.214 * sin(2.0 * mPrime * rad)
            - 0.110 * sin(d * rad)
        let illuminated = (1.0 + cos(phaseAngle * rad)) / 2.0

        // Waxing while the Moon's elongation east of the Sun is 0°–180°.
        let elongation = (d.truncatingRemainder(dividingBy: 360.0) + 360.0)
            .truncatingRemainder(dividingBy: 360.0)
        return MoonPhase(illuminatedFraction: illuminated, isWaxing: elongation < 180.0)
    }
}

/// The Moon's illumination and waxing/waning state.
public struct MoonPhase: Sendable, Hashable {
    /// Fraction of the Moon's disk that is lit, 0 (new) … 1 (full).
    public let illuminatedFraction: Double
    public let isWaxing: Bool

    public var name: String {
        let k = illuminatedFraction
        if k < 0.04 { return "New Moon" }
        if k > 0.96 { return "Full Moon" }
        if abs(k - 0.5) < 0.06 { return isWaxing ? "First Quarter" : "Last Quarter" }
        if k < 0.5 { return isWaxing ? "Waxing Crescent" : "Waning Crescent" }
        return isWaxing ? "Waxing Gibbous" : "Waning Gibbous"
    }
}

// MARK: - Periodic term tables (Meeus, ch. 47)

private struct LunarTerm {
    let d, m, mp, f: Int
    let sine: Int
    let cosine: Int

    init(_ d: Int, _ m: Int, _ mp: Int, _ f: Int, _ sine: Int, _ cosine: Int = 0) {
        self.d = d; self.m = m; self.mp = mp; self.f = f
        self.sine = sine; self.cosine = cosine
    }

    /// Terms involving the Sun's mean anomaly are scaled by powers of `E` (eq. 47.6),
    /// because the Earth's orbital eccentricity changes slowly over time.
    func eccentricityPower(_ e: Double) -> Double {
        switch abs(m) {
        case 1: return e
        case 2: return e * e
        default: return 1.0
        }
    }
}

// Table 47.A — longitude (sine) and distance (cosine).
private let longitudeDistanceTerms: [LunarTerm] = [
    LunarTerm(0, 0, 1, 0, 6288774, -20905355),
    LunarTerm(2, 0, -1, 0, 1274027, -3699111),
    LunarTerm(2, 0, 0, 0, 658314, -2955968),
    LunarTerm(0, 0, 2, 0, 213618, -569925),
    LunarTerm(0, 1, 0, 0, -185116, 48888),
    LunarTerm(0, 0, 0, 2, -114332, -3149),
    LunarTerm(2, 0, -2, 0, 58793, 246158),
    LunarTerm(2, -1, -1, 0, 57066, -152138),
    LunarTerm(2, 0, 1, 0, 53322, -170733),
    LunarTerm(2, -1, 0, 0, 45758, -204586),
    LunarTerm(0, 1, -1, 0, -40923, -129620),
    LunarTerm(1, 0, 0, 0, -34720, 108743),
    LunarTerm(0, 1, 1, 0, -30383, 104755),
    LunarTerm(2, 0, 0, -2, 15327, 10321),
    LunarTerm(0, 0, 1, 2, -12528, 0),
    LunarTerm(0, 0, 1, -2, 10980, 79661),
    LunarTerm(4, 0, -1, 0, 10675, -34782),
    LunarTerm(0, 0, 3, 0, 10034, -23210),
    LunarTerm(4, 0, -2, 0, 8548, -21636),
    LunarTerm(2, 1, -1, 0, -7888, 24208),
    LunarTerm(2, 1, 0, 0, -6766, 30824),
    LunarTerm(1, 0, -1, 0, -5163, -8379),
    LunarTerm(1, 1, 0, 0, 4987, -16675),
    LunarTerm(2, -1, 1, 0, 4036, -12831),
    LunarTerm(2, 0, 2, 0, 3994, -10445),
    LunarTerm(4, 0, 0, 0, 3861, -11650),
    LunarTerm(2, 0, -3, 0, 3665, 14403),
    LunarTerm(0, 1, -2, 0, -2689, -7003),
    LunarTerm(2, 0, -1, 2, -2602, 0),
    LunarTerm(2, -1, -2, 0, 2390, 10056),
    LunarTerm(1, 0, 1, 0, -2348, 6322),
    LunarTerm(2, -2, 0, 0, 2236, -9884),
    LunarTerm(0, 1, 2, 0, -2120, 5751),
    LunarTerm(0, 2, 0, 0, -2069, 0),
    LunarTerm(2, -2, -1, 0, 2048, -4950),
    LunarTerm(2, 0, 1, -2, -1773, 4130),
    LunarTerm(2, 0, 0, 2, -1595, 0),
    LunarTerm(4, -1, -1, 0, 1215, -3958),
    LunarTerm(0, 0, 2, 2, -1110, 0),
    LunarTerm(3, 0, -1, 0, -892, 3258),
    LunarTerm(2, 1, 1, 0, -810, 2616),
    LunarTerm(4, -1, -2, 0, 759, -1897),
    LunarTerm(0, 2, -1, 0, -713, -2117),
    LunarTerm(2, 2, -1, 0, -700, 2354),
    LunarTerm(2, 1, -2, 0, 691, 0),
    LunarTerm(2, -1, 0, -2, 596, 0),
    LunarTerm(4, 0, 1, 0, 549, -1423),
    LunarTerm(0, 0, 4, 0, 537, -1117),
    LunarTerm(4, -1, 0, 0, 520, -1571),
    LunarTerm(1, 0, -2, 0, -487, -1739),
    LunarTerm(2, 1, 0, -2, -399, 0),
    LunarTerm(0, 0, 2, -2, -381, -4421),
    LunarTerm(1, 1, 1, 0, 351, 0),
    LunarTerm(3, 0, -2, 0, -340, 0),
    LunarTerm(4, 0, -3, 0, 330, 0),
    LunarTerm(2, -1, 2, 0, 327, 0),
    LunarTerm(0, 2, 1, 0, -323, 1165),
    LunarTerm(1, 1, -1, 0, 299, 0),
    LunarTerm(2, 0, 3, 0, 294, 0),
    LunarTerm(2, 0, -1, -2, 0, 8752),
]

// Table 47.B — latitude (sine).
private let latitudeTerms: [LunarTerm] = [
    LunarTerm(0, 0, 0, 1, 5128122),
    LunarTerm(0, 0, 1, 1, 280602),
    LunarTerm(0, 0, 1, -1, 277693),
    LunarTerm(2, 0, 0, -1, 173237),
    LunarTerm(2, 0, -1, 1, 55413),
    LunarTerm(2, 0, -1, -1, 46271),
    LunarTerm(2, 0, 0, 1, 32573),
    LunarTerm(0, 0, 2, 1, 17198),
    LunarTerm(2, 0, 1, -1, 9266),
    LunarTerm(0, 0, 2, -1, 8822),
    LunarTerm(2, -1, 0, -1, 8216),
    LunarTerm(2, 0, -2, -1, 4324),
    LunarTerm(2, 0, 1, 1, 4200),
    LunarTerm(2, 1, 0, -1, -3359),
    LunarTerm(2, -1, -1, 1, 2463),
    LunarTerm(2, -1, 0, 1, 2211),
    LunarTerm(2, -1, -1, -1, 2065),
    LunarTerm(0, 1, -1, -1, -1870),
    LunarTerm(4, 0, -1, -1, 1828),
    LunarTerm(0, 1, 0, 1, -1794),
    LunarTerm(0, 0, 0, 3, -1749),
    LunarTerm(0, 1, -1, 1, -1565),
    LunarTerm(1, 0, 0, 1, -1491),
    LunarTerm(0, 1, 1, 1, -1475),
    LunarTerm(0, 1, 1, -1, -1410),
    LunarTerm(0, 1, 0, -1, -1344),
    LunarTerm(1, 0, 0, -1, -1335),
    LunarTerm(0, 0, 3, 1, 1107),
    LunarTerm(4, 0, 0, -1, 1021),
    LunarTerm(4, 0, -1, 1, 833),
    LunarTerm(0, 0, 1, -3, 777),
    LunarTerm(4, 0, -2, 1, 671),
    LunarTerm(2, 0, 0, -3, 607),
    LunarTerm(2, 0, 2, -1, 596),
    LunarTerm(2, -1, 1, -1, 491),
    LunarTerm(2, 0, -2, 1, -451),
    LunarTerm(0, 0, 3, -1, 439),
    LunarTerm(2, 0, 2, 1, 422),
    LunarTerm(2, 0, -3, -1, 421),
    LunarTerm(2, 1, -1, 1, -366),
    LunarTerm(2, 1, 0, 1, -351),
    LunarTerm(4, 0, 0, 1, 331),
    LunarTerm(2, -1, 1, 1, 315),
    LunarTerm(2, -2, 0, -1, 302),
    LunarTerm(0, 0, 1, 3, -283),
    LunarTerm(2, 1, 1, -1, -229),
    LunarTerm(1, 1, 0, -1, 223),
    LunarTerm(1, 1, 0, 1, 223),
    LunarTerm(0, 1, -2, -1, -220),
    LunarTerm(2, 1, -1, -1, -220),
    LunarTerm(1, 0, 1, 1, -185),
    LunarTerm(2, -1, -2, -1, 181),
    LunarTerm(0, 1, 2, 1, -177),
    LunarTerm(4, 0, -2, -1, 176),
    LunarTerm(4, -1, -1, -1, 166),
    LunarTerm(1, 0, 1, -1, -164),
    LunarTerm(4, 0, 1, -1, 132),
    LunarTerm(1, 0, -1, -1, -119),
    LunarTerm(4, -1, 0, -1, 115),
    LunarTerm(2, -2, 0, 1, 107),
]
