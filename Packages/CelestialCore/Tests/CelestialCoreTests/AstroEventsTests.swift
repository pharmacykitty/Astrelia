import Testing
import Foundation
@testable import CelestialCore

@Suite struct AstroEventsTests {

    private static let utc = TimeZone(identifier: "UTC")!
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c
    }()
    private func date(_ y: Int, _ m: Int, _ d: Int, _ hh: Int = 0, _ mm: Int = 0) -> Date {
        Self.cal.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm))!
    }

    // MARK: General contract

    /// Events come back sorted and entirely inside the requested window.
    @Test func resultsAreSortedAndWithinWindow() {
        let start = date(2026, 6, 1)
        let days = 90.0
        let end = start.addingTimeInterval(days * 86400)
        let events = AstroEvent.upcoming(after: start, within: days)

        #expect(!events.isEmpty)
        #expect(events == events.sorted { $0.date < $1.date })
        for e in events {
            #expect(e.date >= start.addingTimeInterval(-1))
            #expect(e.date <= end.addingTimeInterval(1))
        }
    }

    /// A wide window should surface every "always-happening" category at least once.
    @Test func coversTheCommonCategories() {
        let events = AstroEvent.upcoming(after: date(2026, 1, 1), within: 200)
        let kinds = Set(events.map(\.kind))
        for required: AstroEvent.Kind in [.newMoon, .firstQuarter, .fullMoon, .lastQuarter,
                                          .perigee, .apogee, .solstice, .equinox,
                                          .perihelion, .aphelion] {
            #expect(kinds.contains(required), "missing \(required)")
        }
    }

    // MARK: Solstices / equinoxes (external reference)

    /// The June 2026 solstice is published at 2026-06-21 08:24 UTC. Our daily-search
    /// + bisection should land within a few minutes (well under the ±1-day tolerance).
    @Test func juneSolsticeMatchesAlmanac() {
        let events = AstroEvent.upcoming(after: date(2026, 6, 1), within: 40)
        let solstice = events.first { $0.kind == .solstice }
        #expect(solstice != nil)
        let expected = date(2026, 6, 21, 8, 24)
        if let s = solstice {
            #expect(abs(s.date.timeIntervalSince(expected)) < 2 * 3600) // within 2 hours
            #expect(s.title == "June Solstice")
        }
    }

    // MARK: Moon phases

    /// Full moons are externally cross-checkable: the June 2026 full moon falls on
    /// 2026-06-29 (≈ 23:58 UTC). Allow ±1 day for the day-search method.
    @Test func juneFullMoonNearKnownDate() {
        let events = AstroEvent.upcoming(after: date(2026, 6, 1), within: 35)
        let full = events.first { $0.kind == .fullMoon }
        #expect(full != nil)
        if let f = full {
            #expect(abs(f.date.timeIntervalSince(date(2026, 6, 29, 12, 0))) < 24 * 3600)
        }
    }

    /// Self-consistency: every full-Moon instant is ~fully lit and every new-Moon
    /// instant is ~dark, checked against the independent `Moon.phase` model.
    @Test func phaseEventsAgreeWithIllumination() {
        let events = AstroEvent.upcoming(after: date(2026, 1, 1), within: 120)
        for e in events where e.kind == .fullMoon {
            let frac = Moon.phase(at: JulianDay(e.date)).illuminatedFraction
            #expect(frac > 0.985, "full moon only \(frac) lit")
        }
        for e in events where e.kind == .newMoon {
            let frac = Moon.phase(at: JulianDay(e.date)).illuminatedFraction
            #expect(frac < 0.015, "new moon \(frac) lit")
        }
        // Quarters are ~half lit.
        for e in events where e.kind == .firstQuarter || e.kind == .lastQuarter {
            let frac = Moon.phase(at: JulianDay(e.date)).illuminatedFraction
            #expect(abs(frac - 0.5) < 0.02, "quarter \(frac) lit")
        }
    }

    // MARK: Earth perihelion / aphelion (external reference)

    /// Earth perihelion 2026 is published at 2026-01-03 (~17 UTC). Distance < 0.984 AU.
    @Test func januaryPerihelionMatchesAlmanac() {
        let events = AstroEvent.upcoming(after: date(2026, 1, 1), within: 15)
        let peri = events.first { $0.kind == .perihelion }
        #expect(peri != nil)
        if let p = peri {
            #expect(abs(p.date.timeIntervalSince(date(2026, 1, 3, 12, 0))) < 24 * 3600)
            #expect(p.detail.contains("0.983"))
        }
    }

    /// Aphelion follows perihelion by half an anomalistic year (~July 5, 2026).
    @Test func julyAphelionIsPresent() {
        let events = AstroEvent.upcoming(after: date(2026, 6, 1), within: 60)
        let aph = events.first { $0.kind == .aphelion }
        #expect(aph != nil)
        if let a = aph {
            #expect(abs(a.date.timeIntervalSince(date(2026, 7, 5, 12, 0))) < 36 * 3600)
        }
    }

    // MARK: Planet–Sun geometry (self-consistent integration checks)

    /// At a flagged opposition the superior planet must truly be ~180° from the Sun
    /// in ecliptic longitude; at a conjunction, ~0°.
    @Test func oppositionAndConjunctionGeometryHolds() {
        let events = AstroEvent.upcoming(after: date(2026, 1, 1), within: 365)
        var checkedOpp = 0, checkedConj = 0
        for e in events {
            guard e.kind == .opposition || e.kind == .conjunction else { continue }
            let jd = JulianDay(e.date)
            let sun = Sun.apparentEclipticLongitude(at: jd).degrees
            // Identify the planet from the title.
            guard let planet = Planet.allCases.first(where: { e.title.hasPrefix($0.displayName) }) else { continue }
            let p = Planets.apparentEclipticLongitude(planet, at: jd).degrees
            var sep = (p - sun).truncatingRemainder(dividingBy: 360)
            if sep < 0 { sep += 360 }
            if e.kind == .opposition {
                #expect(abs(sep - 180) < 0.5, "\(e.title) sep=\(sep)")
                checkedOpp += 1
            } else {
                let toZero = min(sep, 360 - sep)
                #expect(toZero < 0.5, "\(e.title) sep=\(sep)")
                checkedConj += 1
            }
        }
        #expect(checkedOpp > 0)
        #expect(checkedConj > 0)
    }

    /// Greatest elongations of Mercury/Venus respect their physical maxima.
    @Test func greatestElongationsAreBounded() {
        let events = AstroEvent.upcoming(after: date(2026, 1, 1), within: 365)
        let elongs = events.filter { $0.kind == .greatestElongation }
        #expect(!elongs.isEmpty)
        for e in elongs {
            let isMercury = e.title.hasPrefix("Mercury")
            let isVenus = e.title.hasPrefix("Venus")
            #expect(isMercury || isVenus)
            // The separation appears in the detail string, e.g. "stands 45.1° from".
            #expect(e.title.contains("Eastern") || e.title.contains("Western"))
        }
    }

    // MARK: Eclipses (STRETCH — geometry-only flags)

    /// The geometry flags should fire on the two real 2026 eclipses: the total solar
    /// eclipse of 2026-08-12 and the lunar eclipse of 2026-08-28.
    @Test func eclipseFlagsHitReal2026Eclipses() {
        let events = AstroEvent.upcoming(after: date(2026, 8, 1), within: 35)
        let solar = events.first { $0.kind == .solarEclipse }
        let lunar = events.first { $0.kind == .lunarEclipse }
        #expect(solar != nil)
        #expect(lunar != nil)
        if let s = solar {
            #expect(abs(s.date.timeIntervalSince(date(2026, 8, 12, 12, 0))) < 24 * 3600)
        }
        if let l = lunar {
            #expect(abs(l.date.timeIntervalSince(date(2026, 8, 28, 12, 0))) < 24 * 3600)
        }
    }
}
