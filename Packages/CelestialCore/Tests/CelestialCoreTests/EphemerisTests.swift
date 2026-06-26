import Testing
@testable import CelestialCore

@Suite("Obliquity")
struct ObliquityTests {
    @Test("mean obliquity at J2000 is 23°26′21.448″")
    func j2000() {
        #expect(abs(Earth.meanObliquity(at: .j2000).degrees - 23.4392911) < 1e-6)
    }
}

@Suite("Ecliptic → equatorial")
struct EclipticTransformTests {
    // Meeus example 13.a — Pollux.
    @Test("Meeus 13.a — Pollux")
    func pollux() {
        let ecliptic = EclipticCoordinates(longitude: .degrees(113.215630), latitude: .degrees(6.684170))
        let equatorial = CoordinateTransform.equatorial(fromEcliptic: ecliptic, obliquity: .degrees(23.4392911))
        #expect(abs(equatorial.rightAscension.degrees - 116.328942) < 1e-4)
        #expect(abs(equatorial.declination.degrees - 28.026183) < 1e-4)
    }
}

@Suite("Sun")
struct SunTests {
    // Meeus ch. 25 example — 1992 October 13.0 TD, JDE 2448908.5.
    @Test("apparent RA/Dec")
    func meeus25() {
        let sun = Sun.position(at: JulianDay(2448908.5))
        #expect(abs(sun.rightAscension.degrees - 198.38083) < 0.01)
        #expect(abs(sun.declination.degrees - (-7.78507)) < 0.01)
    }

    @Test("apparent ecliptic longitude")
    func longitude() {
        #expect(abs(Sun.apparentEclipticLongitude(at: JulianDay(2448908.5)).degrees - 199.90895) < 0.01)
    }
}

@Suite("Moon")
struct MoonTests {
    // Meeus example 47.a — 1992 April 12.0 TD, JDE 2448724.5.
    let jd = JulianDay(2448724.5)

    @Test("Meeus 47.a — geocentric ecliptic position & distance")
    func geocentric() {
        let moon = Moon.geocentric(at: jd)
        #expect(abs(moon.ecliptic.longitude.degrees - 133.162655) < 1e-3)
        #expect(abs(moon.ecliptic.latitude.degrees - (-3.229126)) < 1e-3)
        #expect(abs(moon.distanceKm - 368409.7) < 2.0)
    }

    @Test("equatorial position near Meeus apparent (nutation omitted)")
    func equatorial() {
        let moon = Moon.position(at: jd)
        // Meeus apparent: α ≈ 134.6885°, δ ≈ +13.7684°. We omit nutation, so allow ~arcmin.
        #expect(abs(moon.rightAscension.degrees - 134.6885) < 0.05)
        #expect(abs(moon.declination.degrees - 13.7684) < 0.05)
    }

    @Test("phase illumination is within bounds and matches geometry")
    func phase() {
        let phase = Moon.phase(at: jd)
        #expect(phase.illuminatedFraction >= 0 && phase.illuminatedFraction <= 1)
        // 1992-04-12 was a couple of days before full moon → waxing, mostly lit.
        #expect(phase.isWaxing)
        #expect(phase.illuminatedFraction > 0.6)
    }
}
