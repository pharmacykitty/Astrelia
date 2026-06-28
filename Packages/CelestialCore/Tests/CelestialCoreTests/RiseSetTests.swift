import XCTest
@testable import CelestialCore

final class PlanetComparisonTests: XCTestCase {
    func testEarthSurfaceGravityIsUnity() {
        XCTAssertEqual(Astrophysics.surfaceGravityEarths(massEarth: 1, radiusEarth: 1)!, 1.0, accuracy: 1e-9)
    }

    func testSuperEarthGravity() {
        // 5 M⊕ in 1.5 R⊕ → 5 / 2.25 ≈ 2.22 g.
        XCTAssertEqual(Astrophysics.surfaceGravityEarths(massEarth: 5, radiusEarth: 1.5)!, 2.222, accuracy: 0.001)
    }

    func testGravityRejectsNonPositive() {
        XCTAssertNil(Astrophysics.surfaceGravityEarths(massEarth: 0, radiusEarth: 1))
        XCTAssertNil(Astrophysics.surfaceGravityEarths(massEarth: 1, radiusEarth: 0))
    }

    func testCelsius() {
        XCTAssertEqual(Astrophysics.celsius(fromKelvin: 273.15), 0, accuracy: 1e-9)
        XCTAssertEqual(Astrophysics.celsius(fromKelvin: 288), 14.85, accuracy: 1e-9)
    }
}

final class RiseSetTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// A synthetic altitude modelling a body below the horizon at midnight, rising
    /// at h=6, peaking at +60° at h=12 (local noon), and setting at h=18.
    private func sineAltitude(_ date: Date) -> Angle {
        let hours = date.timeIntervalSince(t0) / 3600
        return .degrees(-60 * cos(2 * .pi * hours / 24))
    }

    func testFindsRise() {
        let rise = RiseSet.next(.rise, from: t0, horizon: .degrees(0), altitude: sineAltitude)
        XCTAssertNotNil(rise)
        let hours = rise!.timeIntervalSince(t0) / 3600
        XCTAssertEqual(hours, 6, accuracy: 0.1)
    }

    func testFindsSet() {
        let set = RiseSet.next(.set, from: t0, horizon: .degrees(0), altitude: sineAltitude)
        XCTAssertNotNil(set)
        let hours = set!.timeIntervalSince(t0) / 3600
        XCTAssertEqual(hours, 18, accuracy: 0.1)
    }

    func testIsUp() {
        let noon = t0.addingTimeInterval(12 * 3600)    // peak altitude
        XCTAssertTrue(RiseSet.isUp(at: noon, horizon: .degrees(0), altitude: sineAltitude))
        let midnight = t0                              // trough (below horizon)
        XCTAssertFalse(RiseSet.isUp(at: midnight, horizon: .degrees(0), altitude: sineAltitude))
    }

    func testNoCrossingReturnsNil() {
        // Always above the horizon → no set.
        let alwaysUp: (Date) -> Angle = { _ in .degrees(45) }
        XCTAssertNil(RiseSet.next(.set, from: t0, horizon: .degrees(0), altitude: alwaysUp))
    }
}
