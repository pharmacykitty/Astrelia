import XCTest
@testable import CelestialCore

final class VisibleSkyTests: XCTestCase {
    // New York, around local apparent noon (17:00 UTC) on a summer day.
    private let nyc = GeographicLocation(latitude: .degrees(40.71), longitude: .degrees(-74.0))
    private var noonUTC: Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 21; c.hour = 17
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testStatusCoversSunMoonAndFivePlanets() {
        let s = VisibleSky.status(at: nyc, date: noonUTC)
        XCTAssertEqual(s.count, 7)                       // Sun, Moon, 5 naked-eye planets
        XCTAssertEqual(s.first?.name, "Sun")
        XCTAssertTrue(s.contains { $0.name == "Saturn" })
    }

    func testSunIsUpAndSetsLaterAtMiddayNYC() {
        let sun = VisibleSky.status(at: nyc, date: noonUTC).first { $0.name == "Sun" }!
        XCTAssertTrue(sun.isUp)                           // midday: above the horizon
        XCTAssertGreaterThan(sun.altitude.degrees, 0)
        XCTAssertNotNil(sun.nextSet)                      // sets this evening
        if let set = sun.nextSet {
            let hours = set.timeIntervalSince(noonUTC) / 3600
            XCTAssertTrue(hours > 0 && hours < 12, "Sun should set within 12h of local noon")
        }
    }

    func testMoonPhaseFractionInRange() {
        let p = VisibleSky.moonPhase(at: noonUTC)
        XCTAssertGreaterThanOrEqual(p.illuminatedFraction, 0)
        XCTAssertLessThanOrEqual(p.illuminatedFraction, 1)
        XCTAssertFalse(p.name.isEmpty)
    }
}
