import Testing
import Foundation
import CelestialCore
@testable import Astrology

private func pos(_ b: AstroBody, _ deg: Double) -> BodyPosition {
    BodyPosition(body: b, longitude: .degrees(deg))
}
private func sampleChart() -> NatalChart {
    let loc = GeographicLocation(latitude: .degrees(47.6062), longitude: .degrees(-122.3321))
    return NatalChart(at: JulianDay(year: 1971, month: 11, day: 19.79), location: loc)
}

@Suite struct DignityTests {
    @Test func classicalDignities() {
        #expect(Dignities.dignity(of: .sun, in: .leo) == .domicile)
        #expect(Dignities.dignity(of: .sun, in: .aquarius) == .detriment)
        #expect(Dignities.dignity(of: .sun, in: .aries) == .exaltation)
        #expect(Dignities.dignity(of: .sun, in: .libra) == .fall)
        #expect(Dignities.dignity(of: .mars, in: .cancer) == .fall)
        #expect(Dignities.dignity(of: .venus, in: .pisces) == .exaltation)
        #expect(Dignities.dignity(of: .jupiter, in: .gemini) == .detriment) // opposite Sagittarius
        #expect(Dignities.dignity(of: .jupiter, in: .taurus) == .none)
    }
    @Test func chartRuler() {
        #expect(Dignities.chartRuler(ascendantSign: .capricorn) == .saturn)
        #expect(Dignities.chartRuler(ascendantSign: .leo) == .sun)
    }
}

@Suite struct PatternTests {
    @Test func grandTrine() {
        let p = [pos(.sun, 0), pos(.jupiter, 120), pos(.saturn, 240)]
        let a = AspectFinder.aspects(among: p)
        let found = Patterns.detect(positions: p, aspects: a)
        #expect(found.contains { $0.kind == .grandTrine })
    }
    @Test func tSquare() {
        let p = [pos(.sun, 0), pos(.mars, 180), pos(.saturn, 90)]
        let a = AspectFinder.aspects(among: p)
        let found = Patterns.detect(positions: p, aspects: a)
        let t = found.first { $0.kind == .tSquare }
        #expect(t != nil)
        #expect(t?.bodies.first == .saturn)   // apex listed first
    }
    @Test func stellium() {
        let p = [pos(.sun, 5), pos(.mercury, 10), pos(.venus, 15)]
        let found = Patterns.detect(positions: p, aspects: AspectFinder.aspects(among: p))
        #expect(found.contains { $0.kind == .stellium && $0.detail.contains("Aries") })
    }
}

@Suite struct SynastryCompositeTests {
    @Test func harmoniousContact() {
        let a = [pos(.sun, 0)]
        let b = [pos(.moon, 120)]
        let asps = Synastry.aspects(a, b)
        #expect(asps.contains { $0.kind == .trine && $0.a == .sun && $0.b == .moon })
    }
    @Test func scoreInRange() {
        let a = sampleChart()
        let report = Synastry.report(a, a)   // identical charts → all conjunctions
        #expect(report.score >= 0 && report.score <= 100)
        #expect(!report.aspects.isEmpty)
    }
    @Test func midpointShorterArc() {
        #expect(abs(Composite.midpoint(.degrees(10), .degrees(20)).degrees - 15) < 1e-6)
        // 350 and 10 → 0, not 180.
        #expect(abs(Composite.midpoint(.degrees(350), .degrees(10)).degrees - 0) < 1e-6)
    }
}

@Suite struct ForecastTests {
    @Test func upcomingIsSortedAndInWindow() {
        let natal = sampleChart()
        let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01
        let events = Forecast.upcoming(for: natal, days: 60, from: start)
        #expect(!events.isEmpty)
        #expect(events == events.sorted { $0.date < $1.date })
        let end = start.addingTimeInterval(61 * 86400)
        #expect(events.allSatisfy { $0.date >= start && $0.date <= end })
    }
    @Test func mercuryRetrogradesAboutThreeAYear() {
        let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01
        let periods = Forecast.retrogrades(of: .mercury, days: 365, from: start)
        // Mercury retrogrades ~3× per year.
        #expect(periods.count >= 2 && periods.count <= 5)
        #expect(periods.allSatisfy { $0.start < $0.end })
    }
}

@Suite struct MinorBodyTests {
    // JPL Horizons geocentric ecliptic longitude (of date), 2026-Jun-28 00:00 UT.
    @Test func matchesHorizons() {
        let jd = JulianDay(year: 2026, month: 6, day: 28.0)
        let refs: [(MinorBody, Double)] = [
            (.ceres, 72.2406), (.chiron, 30.2762), (.vesta, 17.1942),
            (.pallas, 17.0780), (.juno, 309.4973),
        ]
        for (b, ref) in refs {
            let got = MinorBodies.apparentEclipticLongitude(b, at: jd).degrees
            var d = abs(got - ref).truncatingRemainder(dividingBy: 360)
            if d > 180 { d = 360 - d }
            #expect(d < 0.5, "\(b): got \(got)°, Horizons \(ref)°, Δ\(d)°")
        }
    }

    @Test func lilithMovesAboutFortyDegreesAYear() {
        let l0 = MinorBodies.blackMoonLilith(at: JulianDay(year: 2026, month: 1, day: 1)).degrees
        let l1 = MinorBodies.blackMoonLilith(at: JulianDay(year: 2027, month: 1, day: 1)).degrees
        var d = (l1 - l0).truncatingRemainder(dividingBy: 360); if d < 0 { d += 360 }
        #expect(abs(d - 40.69) < 0.6)
    }
}

@Suite struct DailyTests {
    @Test func producesReading() {
        let r = Daily.reading(for: sampleChart(),
                              on: Date(timeIntervalSince1970: 1_767_225_600))
        #expect(!r.headline.isEmpty)
        #expect(!r.body.isEmpty)
    }
}
