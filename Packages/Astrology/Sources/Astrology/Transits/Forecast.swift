import CelestialCore
import Foundation

/// The exact moment an upcoming transit perfects (transiting body to a natal point).
public struct ForecastEvent: Sendable, Hashable, Identifiable {
    public let date: Date
    public let transiting: AstroBody
    public let natal: AstroBody
    public let kind: AspectKind
    public var id: String { "\(Int(date.timeIntervalSince1970))-\(transiting.rawValue)-\(kind.rawValue)-\(natal.rawValue)" }

    public init(date: Date, transiting: AstroBody, natal: AstroBody, kind: AspectKind) {
        self.date = date; self.transiting = transiting; self.natal = natal; self.kind = kind
    }
}

/// A retrograde span: from the station-retrograde to the station-direct.
public struct RetrogradePeriod: Sendable, Hashable, Identifiable {
    public let body: AstroBody
    public let start: Date
    public let end: Date
    public var id: String { "\(body.rawValue)-\(Int(start.timeIntervalSince1970))" }

    public init(body: AstroBody, start: Date, end: Date) {
        self.body = body; self.start = start; self.end = end
    }
}

/// Looks ahead in time: when transits perfect, and when planets station retrograde.
/// The Moon is excluded from the forecast by default (too fast / short-lived for a
/// multi-month outlook); slower bodies sample cleanly at a one-day step.
public enum Forecast {

    public static let forecastBodies: [AstroBody] =
        [.sun, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto]

    /// Exact transit dates to the natal chart over the next `days`, soonest first.
    public static func upcoming(
        for natal: NatalChart,
        days: Int = 90,
        from start: Date = Date(),
        transitingBodies: [AstroBody] = forecastBodies,
        majorOnly: Bool = true,
        ephemeris: any EphemerisProvider = CelestialCoreEphemeris()
    ) -> [ForecastEvent] {
        let zodiac = natal.settings.zodiac
        let startJD = JulianDay(start).value
        let stepDays = 1.0
        let steps = max(1, Int(Double(days) / stepDays))
        let kinds = majorOnly ? AspectKind.allCases.filter(\.isMajor) : AspectKind.allCases
        var events: [ForecastEvent] = []

        for tb in transitingBodies {
            // Sample this body's chart-frame longitude across the window.
            var times: [Double] = []
            var lons: [Double] = []
            for i in 0...steps {
                let jdv = startJD + Double(i) * stepDays
                let jd = JulianDay(jdv)
                guard let trop = ephemeris.longitude(of: tb, at: jd) else { continue }
                times.append(jdv)
                lons.append(zodiac.longitude(fromTropical: trop, at: jd).degrees)
            }
            guard lons.count > 1 else { continue }

            for np in natal.positions {
                let natalLon = np.longitude.degrees
                // r(t) = transitingLon − natalLon, brought near each target.
                for kind in kinds {
                    for base in targets(for: kind) {
                        // Search each daily interval for a crossing of r == base (mod 360).
                        for i in 0..<(times.count - 1) {
                            let f0 = wrapNear(lons[i] - natalLon, base)
                            let f1 = wrapNear(lons[i + 1] - natalLon, base)
                            if (f0 - base) == 0 { addEvent(times[i]) }
                            if (f0 - base) * (f1 - base) < 0 {
                                let jdRoot = bisect(times[i], times[i + 1], base: base, natalLon: natalLon) { jdv in
                                    let jd = JulianDay(jdv)
                                    guard let trop = ephemeris.longitude(of: tb, at: jd) else { return nil }
                                    return zodiac.longitude(fromTropical: trop, at: jd).degrees
                                }
                                if let jdRoot { addEvent(jdRoot) }
                            }
                            func addEvent(_ jdv: Double) {
                                events.append(ForecastEvent(date: date(jdv), transiting: tb,
                                                            natal: np.body, kind: kind))
                            }
                        }
                    }
                }
            }
        }
        // De-duplicate near-coincident events and sort by date.
        let unique = Dictionary(grouping: events) { "\($0.transiting.rawValue)-\($0.kind.rawValue)-\($0.natal.rawValue)-\(Int($0.date.timeIntervalSince1970 / 86400))" }
            .compactMap { $0.value.first }
        return unique.sorted { $0.date < $1.date }
    }

    /// Retrograde spans of a body over the window (Mercury by default).
    public static func retrogrades(
        of body: AstroBody = .mercury,
        days: Int = 120,
        from start: Date = Date(),
        ephemeris: any EphemerisProvider = CelestialCoreEphemeris()
    ) -> [RetrogradePeriod] {
        let startJD = JulianDay(start).value
        let steps = max(1, days)
        var times: [Double] = []
        var speeds: [Double] = []
        for i in 0...steps {
            let jdv = startJD + Double(i)
            guard let s = ephemeris.speed(of: body, at: JulianDay(jdv)) else { continue }
            times.append(jdv); speeds.append(s)
        }
        guard speeds.count > 1 else { return [] }

        // Stations are sign changes in speed.
        var stationRetro: Double?
        var periods: [RetrogradePeriod] = []
        for i in 0..<(speeds.count - 1) {
            if speeds[i] > 0, speeds[i + 1] < 0 {
                stationRetro = stationTime(times[i], times[i + 1], body: body, ephemeris: ephemeris)
            } else if speeds[i] < 0, speeds[i + 1] > 0, let sr = stationRetro {
                let sd = stationTime(times[i], times[i + 1], body: body, ephemeris: ephemeris)
                periods.append(RetrogradePeriod(body: body, start: date(sr), end: date(sd)))
                stationRetro = nil
            }
        }
        // An open retrograde already in progress at window start.
        if let sr = stationRetro {
            periods.append(RetrogradePeriod(body: body, start: date(sr), end: date(times.last!)))
        }
        if speeds.first! < 0, periods.first?.start != date(times.first!) {
            // Retrograde already underway before the window opened.
            periods.insert(RetrogradePeriod(body: body, start: date(times.first!),
                                            end: periods.first?.start ?? date(times.last!)),
                           at: 0)
        }
        return periods
    }

    // MARK: Helpers

    /// Exact-aspect target offsets for a kind, as signed values in (−180, 180].
    private static func targets(for kind: AspectKind) -> [Double] {
        let a = kind.angle
        if a == 0 { return [0] }
        if a == 180 { return [180] }
        return [a, -a]
    }

    /// Bring `x` to within 180° of `base` (so a daily step never aliases).
    private static func wrapNear(_ x: Double, _ base: Double) -> Double {
        var v = x
        while v - base > 180 { v -= 360 }
        while v - base < -180 { v += 360 }
        return v
    }

    private static func bisect(_ lo: Double, _ hi: Double, base: Double, natalLon: Double,
                               lon: (Double) -> Double?) -> Double? {
        var a = lo, b = hi
        guard let la = lon(a), let lb = lon(b) else { return nil }
        var fa = wrapNear(la - natalLon, base) - base
        var fb = wrapNear(lb - natalLon, base) - base
        if fa * fb > 0 { return nil }
        for _ in 0..<40 {
            let m = (a + b) / 2
            guard let lm = lon(m) else { return nil }
            let fm = wrapNear(lm - natalLon, base) - base
            if abs(fm) < 1e-4 || (b - a) < 1e-4 { return m }
            if fa * fm < 0 { b = m; fb = fm } else { a = m; fa = fm }
        }
        return (a + b) / 2
    }

    private static func stationTime(_ lo: Double, _ hi: Double, body: AstroBody,
                                    ephemeris: any EphemerisProvider) -> Double {
        var a = lo, b = hi
        for _ in 0..<40 {
            let m = (a + b) / 2
            let sa = ephemeris.speed(of: body, at: JulianDay(a)) ?? 0
            let sm = ephemeris.speed(of: body, at: JulianDay(m)) ?? 0
            if abs(sm) < 1e-5 || (b - a) < 1e-4 { return m }
            if sa * sm < 0 { b = m } else { a = m }
        }
        return (a + b) / 2
    }

    private static func date(_ jdValue: Double) -> Date {
        Date(timeIntervalSince1970: (jdValue - JulianDay.unixEpoch.value) * 86400.0)
    }
}
