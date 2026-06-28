import Foundation

/// A single dated sky event, computed purely from the bundled ephemeris (no
/// external data or network). Pure value type, `Sendable` — safe to hand to UI.
///
/// Times are derived from the same Meeus/SwiftAA models the rest of `CelestialCore`
/// uses. Input `Date`s are treated as UTC and fed to the ephemeris as Dynamical
/// Time (ΔT ≈ 70 s in this era is ignored — far below the day-scale tolerances of a
/// "what's coming up" feed, though it nudges the printed minute by ~a minute).
public struct AstroEvent: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case solstice
        case equinox
        case newMoon
        case firstQuarter
        case fullMoon
        case lastQuarter
        case opposition
        case conjunction
        case greatestElongation
        case perigee
        case apogee
        case perihelion
        case aphelion
        /// Approximate flag: a new Moon occurring near a lunar node. Geometry only —
        /// not a full Besselian element solution, and visibility depends on location.
        case solarEclipse
        /// Approximate flag: a full Moon occurring near a lunar node.
        case lunarEclipse
    }

    /// The instant of the event (UTC).
    public let date: Date
    public let kind: Kind
    /// Short headline, e.g. "Mars at Opposition" or "Full Moon".
    public let title: String
    /// One-sentence description suitable for a feed row.
    public let detail: String

    public var id: String { "\(kind.rawValue)@\(date.timeIntervalSince1970)" }

    public init(date: Date, kind: Kind, title: String, detail: String) {
        self.date = date
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

// MARK: - Engine

extension AstroEvent {
    /// All sky events occurring in the window `[start, start + days]`, sorted by date.
    ///
    /// Implemented by a coarse-to-fine time search: each quantity (Sun longitude,
    /// Sun–Moon elongation, planet–Sun elongation, geocentric distances) is sampled
    /// once per day, candidate crossings/extrema are bracketed, then refined to ~a
    /// second by bisection (zero crossings) or golden-section (extrema).
    public static func upcoming(after start: Date = Date(), within days: Double = 90) -> [AstroEvent] {
        let startJD = JulianDay(start).value
        let endJD = startJD + max(0, days)

        // Pad by a day each side so extrema/crossings at the very edges are bracketed.
        var times: [Double] = []
        var t = startJD - 1.0
        while t <= endJD + 1.0 + 1e-9 { times.append(t); t += 1.0 }

        var events: [AstroEvent] = []
        events += seasonEvents(times)
        events += moonPhaseEvents(times)
        events += planetEvents(times)
        events += moonDistanceEvents(times)
        events += earthDistanceEvents(times)

        // Keep only events strictly inside the requested window, sorted.
        return events
            .filter { JulianDay($0.date).value >= startJD - 1e-9 && JulianDay($0.date).value <= endJD + 1e-9 }
            .sorted { $0.date < $1.date }
    }

    // MARK: Solstices & equinoxes (Sun's ecliptic longitude = 0/90/180/270)

    private static func seasonEvents(_ times: [Double]) -> [AstroEvent] {
        struct Season { let target: Double; let kind: Kind; let title: String; let detail: String }
        let seasons = [
            Season(target: 0, kind: .equinox, title: "March Equinox",
                   detail: "The Sun crosses the celestial equator heading north; day and night are nearly equal."),
            Season(target: 90, kind: .solstice, title: "June Solstice",
                   detail: "The Sun reaches its northernmost point — the year's longest day north of the equator."),
            Season(target: 180, kind: .equinox, title: "September Equinox",
                   detail: "The Sun crosses the celestial equator heading south; day and night are nearly equal."),
            Season(target: 270, kind: .solstice, title: "December Solstice",
                   detail: "The Sun reaches its southernmost point — the year's shortest day north of the equator."),
        ]

        var out: [AstroEvent] = []
        for s in seasons {
            let f: (Double) -> Double = { signedDeg(Sun.apparentEclipticLongitude(at: JulianDay($0)).degrees - s.target) }
            for jd in risingZeros(times, f) {
                out.append(AstroEvent(date: dateFromJD(jd), kind: s.kind, title: s.title, detail: s.detail))
            }
        }
        return out
    }

    // MARK: Moon phases (Moon–Sun elongation = 0/90/180/270), plus eclipse flags

    private static func moonPhaseEvents(_ times: [Double]) -> [AstroEvent] {
        struct Phase { let target: Double; let kind: Kind; let title: String; let detail: String }
        let phases = [
            Phase(target: 0, kind: .newMoon, title: "New Moon",
                  detail: "The Moon sits between Earth and the Sun — dark skies, ideal for faint objects."),
            Phase(target: 90, kind: .firstQuarter, title: "First Quarter",
                  detail: "The Moon is half-lit and rides high in the evening sky."),
            Phase(target: 180, kind: .fullMoon, title: "Full Moon",
                  detail: "The fully lit Moon rises at sunset and shines all night."),
            Phase(target: 270, kind: .lastQuarter, title: "Last Quarter",
                  detail: "The half-lit Moon rises after midnight, best before dawn."),
        ]

        func moonSunElong(_ jd: Double) -> Double {
            let day = JulianDay(jd)
            let moon = Moon.geocentric(at: day).ecliptic.longitude.degrees
            let sun = Sun.apparentEclipticLongitude(at: day).degrees
            return moon - sun
        }

        var out: [AstroEvent] = []
        for p in phases {
            let f: (Double) -> Double = { signedDeg(moonSunElong($0) - p.target) }
            for jd in risingZeros(times, f) {
                out.append(AstroEvent(date: dateFromJD(jd), kind: p.kind, title: p.title, detail: p.detail))

                // STRETCH: crude eclipse flag — syzygy near a lunar node (small |β|).
                // Geometry-only thresholds; not a rigorous eclipse prediction.
                let beta = abs(Moon.geocentric(at: JulianDay(jd)).ecliptic.latitude.degrees)
                if p.kind == .newMoon, beta < 1.5 {
                    out.append(AstroEvent(date: dateFromJD(jd), kind: .solarEclipse,
                                          title: "Possible Solar Eclipse",
                                          detail: "New Moon near a lunar node (β ≈ \(fmt(beta, "%.2f"))°) — a solar eclipse is possible somewhere on Earth. Approximate."))
                } else if p.kind == .fullMoon, beta < 1.0 {
                    out.append(AstroEvent(date: dateFromJD(jd), kind: .lunarEclipse,
                                          title: "Possible Lunar Eclipse",
                                          detail: "Full Moon near a lunar node (β ≈ \(fmt(beta, "%.2f"))°) — a lunar eclipse is possible. Approximate."))
                }
            }
        }
        return out
    }

    // MARK: Planet–Sun events (conjunction, opposition, greatest elongation)

    private static func planetEvents(_ times: [Double]) -> [AstroEvent] {
        var out: [AstroEvent] = []
        let superior: [Planet] = [.mars, .jupiter, .saturn, .uranus, .neptune, .pluto]
        let inferior: [Planet] = [.mercury, .venus]

        // Conjunction with the Sun — every planet (signed longitude diff crosses 0).
        for planet in Planet.allCases {
            let f: (Double) -> Double = { signedDeg(planetSunLonDiff(planet, $0)) }
            for jd in signChanges(times, f, guardMag: 90) {
                out.append(AstroEvent(
                    date: dateFromJD(jd), kind: .conjunction,
                    title: "\(planet.displayName) in Conjunction with the Sun",
                    detail: "\(planet.displayName) lines up with the Sun and is lost in its glare."))
            }
        }

        // Opposition — superior planets only (elongation passes through 180°).
        for planet in superior {
            let f: (Double) -> Double = { signedDeg(planetSunLonDiff(planet, $0) - 180) }
            for jd in signChanges(times, f, guardMag: 90) {
                out.append(AstroEvent(
                    date: dateFromJD(jd), kind: .opposition,
                    title: "\(planet.displayName) at Opposition",
                    detail: "\(planet.displayName) lies opposite the Sun — fully lit, closest, and visible all night. Best time to observe."))
            }
        }

        // Greatest elongation — Mercury & Venus (local maxima of angular separation).
        for planet in inferior {
            let sep: (Double) -> Double = { planetSunSeparation(planet, $0) }
            for ex in extrema(times, sep) where ex.isMax {
                let east = signedDeg(planetSunLonDiff(planet, ex.jd)) > 0
                let dist = sep(ex.jd)
                out.append(AstroEvent(
                    date: dateFromJD(ex.jd), kind: .greatestElongation,
                    title: "\(planet.displayName) at Greatest \(east ? "Eastern" : "Western") Elongation",
                    detail: "\(planet.displayName) stands \(fmt(dist, "%.1f"))° from the Sun — best \(east ? "evening" : "morning") visibility."))
            }
        }
        return out
    }

    // MARK: Moon perigee / apogee (geocentric distance extrema)

    private static func moonDistanceEvents(_ times: [Double]) -> [AstroEvent] {
        let dist: (Double) -> Double = { Moon.geocentric(at: JulianDay($0)).distanceKm }
        var out: [AstroEvent] = []
        for ex in extrema(times, dist) {
            let km = dist(ex.jd)
            if ex.isMax {
                out.append(AstroEvent(date: dateFromJD(ex.jd), kind: .apogee,
                                      title: "Moon at Apogee",
                                      detail: "The Moon reaches its farthest point from Earth (\(fmt(km, "%.0f")) km) — the smallest full disk."))
            } else {
                out.append(AstroEvent(date: dateFromJD(ex.jd), kind: .perigee,
                                      title: "Moon at Perigee",
                                      detail: "The Moon reaches its closest point to Earth (\(fmt(km, "%.0f")) km) — the largest disk."))
            }
        }
        return out
    }

    // MARK: Earth perihelion / aphelion (Sun–Earth distance extrema)

    private static func earthDistanceEvents(_ times: [Double]) -> [AstroEvent] {
        let dist: (Double) -> Double = { earthSunDistanceAU(JulianDay($0)) }
        var out: [AstroEvent] = []
        for ex in extrema(times, dist) {
            let au = dist(ex.jd)
            if ex.isMax {
                out.append(AstroEvent(date: dateFromJD(ex.jd), kind: .aphelion,
                                      title: "Earth at Aphelion",
                                      detail: "Earth is farthest from the Sun (\(fmt(au, "%.4f")) AU)."))
            } else {
                out.append(AstroEvent(date: dateFromJD(ex.jd), kind: .perihelion,
                                      title: "Earth at Perihelion",
                                      detail: "Earth is closest to the Sun (\(fmt(au, "%.4f")) AU)."))
            }
        }
        return out
    }
}

// MARK: - Numerical search helpers

extension AstroEvent {
    /// Refined Julian Days where `f` rises through zero (negative → non-negative).
    /// For quantities that increase monotonically (Sun longitude, Moon elongation),
    /// this picks the wanted crossing and ignores the opposite-side ±180° wrap.
    private static func risingZeros(_ times: [Double], _ f: (Double) -> Double) -> [Double] {
        var roots: [Double] = []
        var prevT = times[0]
        var prevV = f(prevT)
        for i in 1..<times.count {
            let t = times[i]
            let v = f(t)
            if prevV < 0, v >= 0 {
                roots.append(bisect(f, prevT, t))
            }
            prevT = t; prevV = v
        }
        return roots
    }

    /// Refined Julian Days where `f` changes sign in either direction. `guardMag`
    /// rejects the discontinuous ±180° wrap of a signed-angle function (a real
    /// crossing of 0 has both endpoints small in magnitude).
    private static func signChanges(_ times: [Double], _ f: (Double) -> Double, guardMag: Double) -> [Double] {
        var roots: [Double] = []
        var prevT = times[0]
        var prevV = f(prevT)
        for i in 1..<times.count {
            let t = times[i]
            let v = f(t)
            if (prevV < 0) != (v < 0), abs(prevV) < guardMag, abs(v) < guardMag {
                roots.append(bisect(f, prevT, t))
            }
            prevT = t; prevV = v
        }
        return roots
    }

    /// Local extrema of `g`, each tagged max/min, refined by golden-section search.
    private static func extrema(_ times: [Double], _ g: (Double) -> Double) -> [(jd: Double, isMax: Bool)] {
        let vals = times.map(g)
        var out: [(jd: Double, isMax: Bool)] = []
        guard times.count >= 3 else { return [] }
        for i in 1..<(times.count - 1) {
            if vals[i] > vals[i - 1], vals[i] > vals[i + 1] {
                out.append((goldenSection(g, times[i - 1], times[i + 1], findMax: true), true))
            } else if vals[i] < vals[i - 1], vals[i] < vals[i + 1] {
                out.append((goldenSection(g, times[i - 1], times[i + 1], findMax: false), false))
            }
        }
        return out
    }

    /// Bisection root of `f` on `[lo, hi]` (endpoints of opposite sign), to ~1 s.
    private static func bisect(_ f: (Double) -> Double, _ lo0: Double, _ hi0: Double) -> Double {
        var lo = lo0, hi = hi0
        var flo = f(lo)
        for _ in 0..<60 {
            let mid = 0.5 * (lo + hi)
            let fmid = f(mid)
            if fmid == 0 { return mid }
            if (flo < 0) != (fmid < 0) { hi = mid } else { lo = mid; flo = fmid }
            if hi - lo < 1e-6 { break }
        }
        return 0.5 * (lo + hi)
    }

    /// Golden-section search for a max (or min) of unimodal `g` on `[a, b]`.
    private static func goldenSection(_ g: (Double) -> Double, _ a0: Double, _ b0: Double, findMax: Bool) -> Double {
        let gr = (5.0.squareRoot() - 1.0) / 2.0
        var a = a0, b = b0
        var c = b - gr * (b - a)
        var d = a + gr * (b - a)
        var fc = g(c), fd = g(d)
        for _ in 0..<80 {
            let cBetter = findMax ? (fc > fd) : (fc < fd)
            if cBetter {
                b = d; d = c; fd = fc; c = b - gr * (b - a); fc = g(c)
            } else {
                a = c; c = d; fc = fd; d = a + gr * (b - a); fd = g(d)
            }
            if b - a < 1e-5 { break }
        }
        return 0.5 * (a + b)
    }
}

// MARK: - Ephemeris quantities & small utilities

extension AstroEvent {
    /// Signed geocentric ecliptic-longitude difference planet − Sun, in degrees.
    private static func planetSunLonDiff(_ planet: Planet, _ jd: Double) -> Double {
        let day = JulianDay(jd)
        return Planets.apparentEclipticLongitude(planet, at: day).degrees
            - Sun.apparentEclipticLongitude(at: day).degrees
    }

    /// Great-circle angular separation (degrees) of a planet from the Sun, using the
    /// planet's ecliptic (λ, β) and the Sun's β ≈ 0.
    private static func planetSunSeparation(_ planet: Planet, _ jd: Double) -> Double {
        let day = JulianDay(jd)
        let p = Planets.eclipticCoordinates(planet, at: day)
        let sunLon = Sun.apparentEclipticLongitude(at: day)
        let dLon = (p.longitude - sunLon).radians
        let beta = p.latitude.radians
        let cosSep = cos(beta) * cos(dLon)
        return acos(min(1, max(-1, cosSep))) * 180.0 / .pi
    }

    /// Earth–Sun distance in AU (Meeus ch. 25, eq. 25.5) — for perihelion/aphelion.
    private static func earthSunDistanceAU(_ jd: JulianDay) -> Double {
        let t = jd.julianCenturiesSinceJ2000
        let m = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) * .pi / 180.0
        let e = 0.016708634 - 0.000042037 * t - 0.0000001267 * t * t
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m)
            + (0.019993 - 0.000101 * t) * sin(2 * m)
            + 0.000289 * sin(3 * m)
        let nu = m + c * .pi / 180.0
        return 1.000001018 * (1 - e * e) / (1 + e * cos(nu))
    }

    /// Wrap a degree value to the half-open range [-180, 180).
    private static func signedDeg(_ x: Double) -> Double {
        var r = x.truncatingRemainder(dividingBy: 360)
        if r < -180 { r += 360 } else if r >= 180 { r -= 360 }
        return r
    }

    private static func dateFromJD(_ jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - JulianDay.unixEpoch.value) * 86400.0)
    }

    private static func fmt(_ v: Double, _ spec: String) -> String { String(format: spec, v) }
}

// MARK: - Display names

extension Planet {
    /// Capitalised English name, for event titles.
    public var displayName: String {
        switch self {
        case .mercury: return "Mercury"
        case .venus: return "Venus"
        case .mars: return "Mars"
        case .jupiter: return "Jupiter"
        case .saturn: return "Saturn"
        case .uranus: return "Uranus"
        case .neptune: return "Neptune"
        case .pluto: return "Pluto"
        }
    }
}
