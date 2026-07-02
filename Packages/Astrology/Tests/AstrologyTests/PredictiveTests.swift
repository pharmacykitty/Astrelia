import Testing
import Foundation
import CelestialCore
@testable import Astrology

private func natal() -> NatalChart {
    let loc = GeographicLocation(latitude: .degrees(47.6062), longitude: .degrees(-122.3321))
    return NatalChart(at: JulianDay(year: 1971, month: 11, day: 19.79), location: loc)
}

@Suite struct ProgressionTests {

    /// "A day for a year": at age ≈ 30, the progressed JD is ≈ 30 days past birth.
    @Test func dayForAYearMapping() {
        let n = natal()
        // 30 tropical years after birth.
        let target = Date(timeIntervalSince1970:
            (n.julianDay.value + 30 * Progressions.tropicalYear - JulianDay.unixEpoch.value) * 86400)
        let pJD = Progressions.progressedJD(natalJD: n.julianDay, at: target)
        #expect(abs(pJD.value - (n.julianDay.value + 30)) < 1e-6)
    }

    /// The progressed Sun advances roughly one degree per year of life.
    @Test func progressedSunAdvance() {
        let n = natal()
        let target = Date(timeIntervalSince1970:
            (n.julianDay.value + 30 * Progressions.tropicalYear - JulianDay.unixEpoch.value) * 86400)
        let pc = Progressions.chart(for: n, at: target)
        // Solar arc after 30 years should be ~30° (Sun moves ~0.95–1.02°/day near perihelion).
        #expect(pc.solarArc.degrees > 27 && pc.solarArc.degrees < 33)
        // Directed angles are advanced by exactly the solar arc.
        let ascFrame = n.settings.zodiac.longitude(fromTropical: n.angles.ascendant, at: n.julianDay)
        let expected = (ascFrame + pc.solarArc).normalized
        #expect(abs(pc.directedAscendant.degrees - expected.degrees) < 1e-6)
    }
}

@Suite struct ReturnTests {

    /// A solar return puts the Sun back on its natal longitude (within a hair).
    @Test func solarReturnPerfectsTheSun() {
        let n = natal()
        let ephem = CelestialCoreEphemeris()
        let natalSun = ephem.longitude(of: .sun, at: n.julianDay)!
        // Search from a date a few months before the next birthday.
        let from = Date(timeIntervalSince1970:
            (n.julianDay.value + 50 * 365.25 - JulianDay.unixEpoch.value) * 86400)
        let sr = Returns.solarReturn(of: n, onOrAfter: from)
        #expect(sr != nil)
        guard let sr else { return }
        let returnSun = ephem.longitude(of: .sun, at: JulianDay(sr.exactDate))!
        let sep = AspectFinder.separationDegrees(returnSun, natalSun)
        #expect(sep < 0.001)
    }

    /// A solar return lands near the birthday (month/day), give or take a day.
    @Test func solarReturnNearBirthday() {
        let n = natal()
        let from = Date(timeIntervalSince1970:
            (n.julianDay.value + 49.6 * 365.25 - JulianDay.unixEpoch.value) * 86400)
        guard let sr = Returns.solarReturn(of: n, onOrAfter: from) else { Issue.record("no return"); return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let m = cal.component(.month, from: sr.exactDate)
        #expect(m == 11)   // born in November
    }

    /// A lunar return regains the natal Moon longitude, and twelve of them span
    /// roughly a year.
    @Test func lunarReturnsCadence() {
        let n = natal()
        let ephem = CelestialCoreEphemeris()
        let natalMoon = ephem.longitude(of: .moon, at: n.julianDay)!
        let from = Date(timeIntervalSince1970:
            (n.julianDay.value + 40 * 365.25 - JulianDay.unixEpoch.value) * 86400)
        let runs = Returns.upcoming(.lunar, of: n, count: 12, from: from)
        #expect(runs.count == 12)
        guard let first = runs.first, let last = runs.last else { return }
        let returnMoon = ephem.longitude(of: .moon, at: JulianDay(first.exactDate))!
        #expect(AspectFinder.separationDegrees(returnMoon, natalMoon) < 0.05)
        // Twelve sidereal months ≈ 327 days; allow a wide band.
        let span = last.exactDate.timeIntervalSince(first.exactDate) / 86400
        #expect(span > 290 && span < 360)
    }
}
