import Testing
@testable import CelestialCore

@Suite("Coordinate transforms")
struct CoordinateTransformTests {
    // Meeus example 13.b — Venus seen from Washington, 1987 April 10 19:21 UT.
    // Meeus reports azimuth 68.0337° measured from the SOUTH; our convention is
    // from North, so the expected azimuth is 180° + 68.0337° = 248.0337°.
    let latitude = Angle.degrees(38.921389)
    let venusDeclination = Angle.degrees(-6.719891667)   // −6°43′11.61″
    let venusHourAngle = Angle.degrees(64.352133)

    @Test("Meeus 13.b — equatorial → horizontal")
    func venusHorizontal() {
        let horizon = CoordinateTransform.horizontal(
            rightAscensionHourAngle: venusHourAngle,
            declination: venusDeclination,
            latitude: latitude
        )
        #expect(abs(horizon.azimuth.degrees - 248.0337) < 2e-3)
        #expect(abs(horizon.altitude.degrees - 15.1249) < 2e-3)
    }

    @Test("horizontal ⇄ equatorial round-trips")
    func roundTrip() {
        let horizon = CoordinateTransform.horizontal(
            rightAscensionHourAngle: venusHourAngle,
            declination: venusDeclination,
            latitude: latitude
        )
        let back = CoordinateTransform.equatorial(horizon, latitude: latitude)
        #expect(abs(back.declination.degrees - venusDeclination.degrees) < 1e-9)
        #expect(abs(back.hourAngle.normalized.degrees - venusHourAngle.normalized.degrees) < 1e-9)
    }

    // Full pipeline: calendar date + observer → horizontal, via mean sidereal time.
    // Looser tolerance: apparent sidereal time (nutation) isn't modelled yet, a
    // sub-arcminute difference here.
    @Test("Meeus 13.b — full pipeline from a date")
    func venusFullPipeline() {
        let jd = JulianDay(year: 1987, month: 4, day: 10 + (19.0 + 21.0 / 60.0) / 24.0)
        let washington = GeographicLocation(
            latitude: .degrees(38.921389),
            longitude: .degrees(-77.065556)        // east-positive
        )
        let venus = EquatorialCoordinates(
            rightAscension: .degrees(347.3193375), // 23h09m16.641s
            declination: .degrees(-6.719891667)
        )
        let horizon = CoordinateTransform.horizontal(venus, at: washington, time: jd)
        #expect(abs(horizon.azimuth.degrees - 248.0337) < 2e-2)
        #expect(abs(horizon.altitude.degrees - 15.1249) < 2e-2)
    }
}
