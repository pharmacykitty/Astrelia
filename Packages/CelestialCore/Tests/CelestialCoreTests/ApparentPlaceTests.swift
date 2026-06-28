import Testing
import Foundation
@testable import CelestialCore

/// Helpers shared by these suites.
private func arcsec(_ angle: Angle) -> Double { angle.degrees * 3600.0 }

@Suite("Nutation (Meeus ch. 22)")
struct NutationTests {
    // Meeus example 22.a — 1987 April 10, 0h TD → JD 2446895.5.
    // Reference results: Δψ = −3.788″, Δε = +9.443″.
    private let jd = JulianDay(2446895.5)

    @Test("Meeus 22.a — Δψ (nutation in longitude)")
    func deltaPsi() {
        let (deltaPsi, _) = Nutation.nutation(at: jd)
        #expect(abs(arcsec(deltaPsi) - (-3.788)) < 0.1)
    }

    @Test("Meeus 22.a — Δε (nutation in obliquity)")
    func deltaEpsilon() {
        let (_, deltaEps) = Nutation.nutation(at: jd)
        #expect(abs(arcsec(deltaEps) - 9.443) < 0.1)
    }

    @Test("convenience accessors agree with the tuple")
    func accessors() {
        let (deltaPsi, deltaEps) = Nutation.nutation(at: jd)
        #expect(Nutation.longitude(at: jd) == deltaPsi)
        #expect(Nutation.obliquity(at: jd) == deltaEps)
    }
}

@Suite("Obliquity — mean vs true")
struct TrueObliquityTests {
    private let jd = JulianDay(2446895.5)

    // Meeus 22.a: mean obliquity ε₀ = 23°26′27.407″.
    @Test("Meeus 22.a — mean obliquity")
    func meanObliquity() {
        let expected = 23.0 + 26.0 / 60.0 + 27.407 / 3600.0
        #expect(abs(Earth.meanObliquity(at: jd).degrees - expected) < 0.5 / 3600.0)
    }

    // Meeus 22.a: true obliquity ε = 23°26′36.850″ = ε₀ + Δε.
    @Test("Meeus 22.a — true obliquity = mean + Δε")
    func trueObliquity() {
        let expected = 23.0 + 26.0 / 60.0 + 36.850 / 3600.0
        #expect(abs(Earth.trueObliquity(at: jd).degrees - expected) < 0.5 / 3600.0)

        // And it is exactly mean + Δε.
        let rebuilt = Earth.meanObliquity(at: jd) + Nutation.obliquity(at: jd)
        #expect(Earth.trueObliquity(at: jd) == rebuilt)
    }
}

@Suite("Apparent sidereal time")
struct ApparentSiderealTests {
    private let jd = JulianDay(2446895.5)

    @Test("apparent − mean Greenwich = equation of the equinoxes")
    func equationOfEquinoxes() {
        let mean = SiderealTime.greenwichMean(at: jd)
        let apparent = SiderealTime.greenwichApparent(at: jd)
        let eoe = SiderealTime.equationOfEquinoxes(at: jd)
        #expect(abs((apparent - mean).radians - eoe.radians) < 1e-12)
    }

    @Test("equation of the equinoxes magnitude (Meeus 22.a date)")
    func equationMagnitude() {
        // Δψ·cos ε ≈ −3.788″ · cos(23.444°) ≈ −3.476″ of arc (~−0.232 s of time).
        let eoe = SiderealTime.equationOfEquinoxes(at: jd)
        #expect(abs(arcsec(eoe) - (-3.476)) < 0.1)
    }

    @Test("local apparent = greenwich apparent + longitude")
    func localApparent() {
        let lon = Angle.degrees(-77.065556) // some observer, east-positive
        let expected = (SiderealTime.greenwichApparent(at: jd) + lon).normalized
        #expect(SiderealTime.localApparent(at: jd, longitude: lon) == expected)
    }
}

@Suite("ΔT (Espenak–Meeus)")
struct DeltaTTests {
    @Test("ΔT ≈ 70 s around the year 2020")
    func around2020() {
        let dt = DeltaT.seconds(at: JulianDay(year: 2020, month: 1, day: 1.0))
        #expect(dt > 65.0 && dt < 75.0)
    }

    @Test("ΔT near zero around the year 1900")
    func around1900() {
        // Espenak–Meeus gives ΔT(1900) ≈ −2.8 s.
        #expect(abs(DeltaT.seconds(forDecimalYear: 1900.0)) < 5.0)
    }

    @Test("ΔT(1800) ≈ 13.7 s (range-boundary spot check)")
    func around1800() {
        #expect(abs(DeltaT.seconds(forDecimalYear: 1800.0) - 13.72) < 0.5)
    }

    @Test("TD leads UT by ΔT, and UT↔TD round-trips")
    func conversion() {
        let ut = JulianDay(year: 2020, month: 6, day: 15.0)
        let td = DeltaT.dynamicalTime(fromUniversalTime: ut)
        #expect(td.value > ut.value)
        // (td − ut) recovers ΔT; tolerance reflects double precision at JD ~2.46e6.
        #expect(abs((td.value - ut.value) * 86400.0 - DeltaT.seconds(at: ut)) < 1e-3)

        let back = DeltaT.universalTime(fromDynamicalTime: td)
        #expect(abs(back.value - ut.value) < 1e-6) // sub-second
    }
}

@Suite("Precession (Meeus ch. 21)")
struct PrecessionTests {
    // Meeus example 21.b — θ Persei, precessed from J2000.0 to 2028 Nov 13.19 TD
    // (JD 2462088.69). Meeus applies proper motion first; we start from his
    // proper-motion-corrected J2000 position and verify the precession step.
    @Test("Meeus 21.b — θ Persei to 2028")
    func meeus21b() {
        let start = EquatorialCoordinates(
            rightAscension: .degrees(41.054063),
            declination: .degrees(49.227750)
        )
        let result = Precession.fromJ2000(start, toJD: JulianDay(2462088.69))

        // Meeus result: α = 2h46m11.331s, δ = +49°20′54.54″.
        let expectedRA = (2.0 + 46.0 / 60.0 + 11.331 / 3600.0) * 15.0   // 41.547213°
        let expectedDec = 49.0 + 20.0 / 60.0 + 54.54 / 3600.0          // 49.348483°
        #expect(abs(result.rightAscension.degrees - expectedRA) < 0.5 / 3600.0)
        #expect(abs(result.declination.degrees - expectedDec) < 0.5 / 3600.0)
    }

    @Test("identity — precessing across a zero interval is a no-op")
    func identity() {
        let coords = EquatorialCoordinates(
            rightAscension: .degrees(123.456),
            declination: .degrees(-12.345)
        )
        let result = Precession.precess(coords, fromJD: .j2000, toJD: .j2000)
        #expect(abs(result.rightAscension.degrees - 123.456) < 1e-9)
        #expect(abs(result.declination.degrees - (-12.345)) < 1e-9)
    }
}
