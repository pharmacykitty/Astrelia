import Foundation
import Testing
@testable import CelestialCore

/// Validation of the Moon's topocentric (lunar-parallax) correction, Meeus ch. 40.
///
/// Meeus's worked Example 40.a uses an observer whose exact geographic data isn't
/// reconstructed here, so instead these tests pin the *physics* the correction must
/// obey, which is a stronger guarantee against sign/convention bugs:
///   • parallax vanishes when the Moon is at the observer's zenith;
///   • parallax never exceeds the equatorial horizontal parallax (~1°);
///   • parallax always displaces the Moon *toward the horizon* (lower altitude),
///     by π·cos(altitude) to first order.
@Suite("Moon topocentric (parallax)")
struct MoonTopocentricTests {
    // The same instant used throughout Meeus's lunar examples: 1992 April 12.0 TD.
    let jd = JulianDay(2448724.5)

    /// Angular separation between two equatorial directions (degrees).
    private func separationDegrees(_ a: EquatorialCoordinates, _ b: EquatorialCoordinates) -> Double {
        let d1 = a.declination, d2 = b.declination
        let cosSep = d1.sine * d2.sine
            + d1.cosine * d2.cosine * (a.rightAscension - b.rightAscension).cosine
        return Angle.acos(min(1.0, max(-1.0, cosSep))).degrees
    }

    @Test("equatorial horizontal parallax matches the Earth–Moon distance")
    func parallaxMagnitude() {
        let distanceKm = Moon.geocentric(at: jd).distanceKm
        let parallax = Angle.asin(6378.14 / distanceKm).degrees
        // Δ ≈ 368409.7 km ⇒ π ≈ 0.991° (≈ 59.5′), the canonical lunar value.
        #expect(abs(parallax - 0.9917) < 0.01)
    }

    @Test("parallax vanishes when the Moon is at the zenith")
    func zenithHasNoParallax() {
        let geo = Moon.position(at: jd)
        // Put the Moon on the observer's meridian (LST = α) at latitude = δ ⇒ zenith.
        let gmst = SiderealTime.greenwichMean(at: jd)
        let longitude = geo.rightAscension - gmst          // east-positive
        let observer = GeographicLocation(
            latitude: geo.declination,
            longitude: longitude
        )
        let topo = Moon.topocentric(at: jd, observer: observer)
        // Only the tiny deflection of the vertical (Earth flattening) remains.
        #expect(separationDegrees(geo, topo) < 0.01)
    }

    @Test("parallax stays within the horizontal-parallax envelope")
    func envelope() {
        let geo = Moon.position(at: jd)
        let parallax = Angle.asin(6378.14 / Moon.geocentric(at: jd).distanceKm).degrees
        // Sweep a range of observers; the shift is real and never exceeds π.
        for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
            for lon in stride(from: -150.0, through: 150.0, by: 60.0) {
                let observer = GeographicLocation(latitude: .degrees(lat), longitude: .degrees(lon))
                let topo = Moon.topocentric(at: jd, observer: observer)
                let shift = separationDegrees(geo, topo)
                #expect(shift >= 0)
                #expect(shift <= parallax + 1e-6)
            }
        }
    }

    @Test("parallax lowers the altitude by ≈ π·cos(altitude)")
    func lowersAltitudeByExpectedAmount() {
        let geoEq = Moon.position(at: jd)
        let parallax = Angle.asin(6378.14 / Moon.geocentric(at: jd).distanceKm)

        // Choose an observer with the Moon high on the meridian (well above horizon).
        let gmst = SiderealTime.greenwichMean(at: jd)
        let longitude = geoEq.rightAscension - gmst                 // Moon on meridian
        let latitude = geoEq.declination + .degrees(40)            // altitude ≈ 50°
        let observer = GeographicLocation(latitude: latitude, longitude: longitude)

        let lst = SiderealTime.localMean(at: jd, longitude: observer.longitude)
        let geoHorizontal = CoordinateTransform.horizontal(geoEq, at: observer, localSiderealTime: lst)
        let topoEq = Moon.topocentric(at: jd, observer: observer)
        let topoHorizontal = CoordinateTransform.horizontal(topoEq, at: observer, localSiderealTime: lst)

        // Parallax always pushes the Moon DOWN.
        #expect(topoHorizontal.altitude < geoHorizontal.altitude)

        let drop = (geoHorizontal.altitude - topoHorizontal.altitude).degrees
        let expected = parallax.degrees * topoHorizontal.altitude.cosine
        #expect(abs(drop - expected) < 0.02)

        // Azimuth essentially unchanged for an object on the meridian.
        #expect(abs((topoHorizontal.azimuth - geoHorizontal.azimuth).degrees) < 0.05)
    }
}
