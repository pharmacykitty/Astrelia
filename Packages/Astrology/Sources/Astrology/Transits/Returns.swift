import CelestialCore
import Foundation

/// Which luminary's return this chart marks.
public enum ReturnKind: Sendable, Hashable {
    /// Sun back to its exact natal longitude — once a year, near the birthday.
    case solar
    /// Moon back to its exact natal longitude — roughly every 27.3 days.
    case lunar

    public var title: String { self == .solar ? "Solar Return" : "Lunar Return" }
    public var body: AstroBody { self == .solar ? .sun : .moon }
}

/// A return chart: a full natal-style chart cast for the instant a luminary comes
/// back to its natal ecliptic longitude. A solar return chart describes the year
/// ahead; a lunar return, the month ahead. Cast for wherever you are at the moment
/// of return (default: the natal place).
public struct ReturnChart: Sendable, Hashable {
    public let kind: ReturnKind
    /// The exact instant the luminary perfected its return.
    public let exactDate: Date
    /// The chart cast for that instant and the chosen location.
    public let chart: NatalChart
}

/// Solar and lunar returns. Pure root-finding on `CelestialCore`; the same
/// bisection style as `Forecast`, working in the **tropical** frame (a return is
/// defined by the body's absolute ecliptic position, independent of ayanamsa).
public enum Returns {

    /// The next solar return at or after `date`, cast for `location` (default: the
    /// natal place). Returns nil only if the Sun's longitude can't be computed.
    public static func solarReturn(
        of natal: NatalChart,
        onOrAfter date: Date = Date(),
        at location: GeographicLocation? = nil,
        ephemeris: any EphemerisProvider = CelestialCoreEphemeris()
    ) -> ReturnChart? {
        returnChart(.solar, of: natal, onOrAfter: date, at: location,
                    maxDays: 370, step: 5, ephemeris: ephemeris)
    }

    /// The next lunar return at or after `date`, cast for `location` (default: the
    /// natal place).
    public static func lunarReturn(
        of natal: NatalChart,
        onOrAfter date: Date = Date(),
        at location: GeographicLocation? = nil,
        ephemeris: any EphemerisProvider = CelestialCoreEphemeris()
    ) -> ReturnChart? {
        returnChart(.lunar, of: natal, onOrAfter: date, at: location,
                    maxDays: 31, step: 1, ephemeris: ephemeris)
    }

    /// A run of upcoming returns of one kind — e.g. the next twelve lunar returns
    /// for the year of months ahead. Soonest first.
    public static func upcoming(
        _ kind: ReturnKind,
        of natal: NatalChart,
        count: Int,
        from date: Date = Date(),
        at location: GeographicLocation? = nil,
        ephemeris: any EphemerisProvider = CelestialCoreEphemeris()
    ) -> [ReturnChart] {
        var out: [ReturnChart] = []
        var cursor = date
        let maxDays = kind == .solar ? 370.0 : 31.0
        let step = kind == .solar ? 5.0 : 1.0
        for _ in 0..<max(0, count) {
            guard let r = returnChart(kind, of: natal, onOrAfter: cursor, at: location,
                                      maxDays: maxDays, step: step, ephemeris: ephemeris)
            else { break }
            out.append(r)
            // Step just past this return to find the following one.
            cursor = r.exactDate.addingTimeInterval(86_400)
        }
        return out
    }

    // MARK: Core

    private static func returnChart(
        _ kind: ReturnKind, of natal: NatalChart,
        onOrAfter date: Date, at location: GeographicLocation?,
        maxDays: Double, step: Double,
        ephemeris: any EphemerisProvider
    ) -> ReturnChart? {
        // The natal body's tropical longitude is the target the body must regain.
        guard let target = ephemeris.longitude(of: kind.body, at: natal.julianDay) else { return nil }
        guard let when = nextMatch(of: kind.body, toTropical: target,
                                   from: date, maxDays: maxDays, step: step,
                                   ephemeris: ephemeris) else { return nil }
        let chart = NatalChart(at: JulianDay(when), location: location ?? natal.location,
                               settings: natal.settings, ephemeris: ephemeris)
        return ReturnChart(kind: kind, exactDate: when, chart: chart)
    }

    /// First time at/after `from` that `body`'s tropical longitude equals `target`.
    static func nextMatch(
        of body: AstroBody, toTropical target: Angle,
        from start: Date, maxDays: Double, step: Double,
        ephemeris: any EphemerisProvider
    ) -> Date? {
        let startJD = JulianDay(start).value
        // Signed difference body−target, folded to (−180, 180].
        func diff(_ jdv: Double) -> Double? {
            guard let lon = ephemeris.longitude(of: body, at: JulianDay(jdv)) else { return nil }
            var d = (lon - target).degrees.truncatingRemainder(dividingBy: 360.0)
            if d > 180 { d -= 360 }
            if d <= -180 { d += 360 }
            return d
        }
        var t0 = startJD
        guard var d0 = diff(t0) else { return nil }
        let n = max(1, Int(maxDays / step))
        for _ in 0..<n {
            let t1 = t0 + step
            guard let d1 = diff(t1) else { return nil }
            // Crossing from behind the target up through it (ignore the ±180 wrap).
            if d0 <= 0, d1 > 0, (d1 - d0) < 180 {
                let root = bisect(t0, t1, target: target, body: body, ephemeris: ephemeris)
                return date(root)
            }
            t0 = t1; d0 = d1
        }
        return nil
    }

    private static func bisect(
        _ lo: Double, _ hi: Double, target: Angle, body: AstroBody,
        ephemeris: any EphemerisProvider
    ) -> Double {
        func diff(_ jdv: Double) -> Double {
            guard let lon = ephemeris.longitude(of: body, at: JulianDay(jdv)) else { return 0 }
            var d = (lon - target).degrees.truncatingRemainder(dividingBy: 360.0)
            if d > 180 { d -= 360 }
            if d <= -180 { d += 360 }
            return d
        }
        var a = lo, b = hi
        var fa = diff(a)
        for _ in 0..<50 {
            let m = (a + b) / 2
            let fm = diff(m)
            if abs(fm) < 1e-6 || (b - a) < 1e-6 { return m }
            if fa <= 0, fm > 0 { b = m } else { a = m; fa = fm }
        }
        return (a + b) / 2
    }

    private static func date(_ jdValue: Double) -> Date {
        Date(timeIntervalSince1970: (jdValue - JulianDay.unixEpoch.value) * 86400.0)
    }
}
