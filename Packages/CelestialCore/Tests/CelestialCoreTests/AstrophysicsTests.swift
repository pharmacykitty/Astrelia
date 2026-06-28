import XCTest
@testable import CelestialCore

final class AstrophysicsTests: XCTestCase {

    func testLightYearConversion() {
        // 1 pc = 3.2616 ly; Sirius at ~2.64 pc ≈ 8.6 ly.
        XCTAssertEqual(Astrophysics.lightYears(fromParsecs: 1), 3.2616, accuracy: 1e-6)
        XCTAssertEqual(Astrophysics.lightYears(fromParsecs: 2.637), 8.6, accuracy: 0.05)
    }

    func testLightTravelMatchesLightYears() {
        XCTAssertEqual(Astrophysics.lightTravelYears(fromParsecs: 10),
                       Astrophysics.lightYears(fromParsecs: 10), accuracy: 1e-9)
    }

    func testSolarRadiusIsUnity() {
        // The Sun: L = 1 L☉, T = T☉ → R ≈ 1 R☉ by construction.
        let r = Astrophysics.stellarRadiusSolar(
            luminositySolar: 1, temperatureKelvin: Astrophysics.solarEffectiveTemperatureK)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!, 1.0, accuracy: 1e-9)
    }

    func testRedSupergiantIsHuge() {
        // Betelgeuse-like: L ≈ 90,000 L☉, T ≈ 3600 K → R of order several hundred R☉.
        let r = Astrophysics.stellarRadiusSolar(luminositySolar: 90_000, temperatureKelvin: 3600)
        XCTAssertNotNil(r)
        XCTAssertGreaterThan(r!, 600)
        XCTAssertLessThan(r!, 1000)
    }

    func testWhiteDwarfIsTiny() {
        // Hot but faint: L ≈ 0.001 L☉, T ≈ 25,000 K → R well under a tenth of the Sun.
        let r = Astrophysics.stellarRadiusSolar(luminositySolar: 0.001, temperatureKelvin: 25_000)
        XCTAssertNotNil(r)
        XCTAssertLessThan(r!, 0.05)
    }

    func testNonPositiveInputsReturnNil() {
        XCTAssertNil(Astrophysics.stellarRadiusSolar(luminositySolar: 0, temperatureKelvin: 5000))
        XCTAssertNil(Astrophysics.stellarRadiusSolar(luminositySolar: 1, temperatureKelvin: 0))
        XCTAssertNil(Astrophysics.stellarRadiusSolar(luminositySolar: -1, temperatureKelvin: 5000))
    }
}
