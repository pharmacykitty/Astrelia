import Testing
import Foundation
@testable import CelestialCore

private func angSep(_ a: Double, _ b: Double) -> Double {
    var d = abs(a - b).truncatingRemainder(dividingBy: 360.0)
    if d > 180 { d = 360 - d }
    return d
}

@Suite struct PlanetTests {

    /// Meeus, *Astronomical Algorithms*, Example 33.a: apparent geocentric
    /// position of Venus on 1992 December 20, 0h TD (JD 2448976.5):
    ///   α = 21ʰ04ᵐ41.454ˢ,  δ = −18°53′16.84″.
    /// Our `position` rebuilds RA/Dec from the apparent ecliptic longitude via the
    /// mean obliquity, so we allow ~1′ for the mean-vs-true-equinox difference.
    @Test func venusMatchesMeeus33a() {
        let jd = JulianDay(2448976.5)
        let eq = Planets.position(.venus, at: jd)
        let expectedRAHours = 21.0 + 4.0 / 60.0 + 41.454 / 3600.0
        let expectedDec = -(18.0 + 53.0 / 60.0 + 16.84 / 3600.0)
        #expect(abs(eq.rightAscension.hours - expectedRAHours) < 0.02)   // ~1ᵐ in RA
        #expect(abs(eq.declination.degrees - expectedDec) < 0.03)         // <2′ in Dec
    }

    /// The strongest integration check: an inferior planet's *geocentric* ecliptic
    /// longitude must stay within its maximum elongation of the Sun. This fails
    /// loudly if we ever returned heliocentric longitudes or read the wrong field.
    @Test func inferiorPlanetsStayNearSun() {
        // Sample several dates across a year.
        for day in stride(from: 0.0, to: 365.0, by: 37.0) {
            let jd = JulianDay(year: 2024, month: 1, day: 1.0 + day)
            let sun = Sun.apparentEclipticLongitude(at: jd).degrees
            let mercury = Planets.apparentEclipticLongitude(.mercury, at: jd).degrees
            let venus = Planets.apparentEclipticLongitude(.venus, at: jd).degrees
            #expect(angSep(mercury, sun) <= 28.5)  // Mercury max elongation ≈ 28°
            #expect(angSep(venus, sun) <= 47.5)    // Venus max elongation ≈ 47°
        }
    }

    @Test func allPlanetsReturnSaneCoordinates() {
        let jd = JulianDay(year: 2024, month: 7, day: 1.0)
        for planet in Planet.allCases {
            let ecl = Planets.eclipticCoordinates(planet, at: jd)
            #expect(ecl.longitude.degrees >= 0 && ecl.longitude.degrees < 360)
            // Ecliptic latitudes of the major planets stay within a few degrees
            // (Pluto reaches ~17°). Catches a longitude/latitude swap.
            #expect(abs(ecl.latitude.degrees) < 20)
        }
    }

    /// Mars takes ~687 days to lap the zodiac, so over 60 days it should advance
    /// (or, if retrograde, regress) by a sane amount — never jump > ~60°.
    @Test func longitudesAdvanceContinuously() {
        let jd1 = JulianDay(year: 2024, month: 7, day: 1.0)
        let jd2 = JulianDay(year: 2024, month: 8, day: 30.0)
        let l1 = Planets.apparentEclipticLongitude(.mars, at: jd1).degrees
        let l2 = Planets.apparentEclipticLongitude(.mars, at: jd2).degrees
        #expect(angSep(l1, l2) < 60)
    }
}

@Suite struct PlutoTests {
    /// Pluto on 2024-07-01 was ~1°23′ Aquarius (≈301.4°), retrograde — between the
    /// 2024 retrograde station at 2°06′ Aquarius (May 2) and 29°39′ Capricorn (Oct 11).
    /// This validates the full geocentric reduction *and* the J2000→date precession:
    /// without precession Pluto would land ~0.34° low (≈301.04°) and fail the band.
    @Test func plutoMatchesPublishedEphemeris() {
        let jd = JulianDay(year: 2024, month: 7, day: 1.0)
        let lon = Planets.apparentEclipticLongitude(.pluto, at: jd).degrees
        #expect(lon > 301.2 && lon < 301.6) // ≈1°12′–1°36′ Aquarius

        let after = Planets.apparentEclipticLongitude(.pluto, at: JulianDay(jd.value + 1)).degrees
        #expect(after < lon) // retrograde
    }
}
