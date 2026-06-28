import XCTest
@testable import CelestialCore

final class MeteorShowerTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testPerseidsActiveInMidAugust() {
        let active = MeteorShowers.active(on: date(2026, 8, 12))
        XCTAssertTrue(active.contains { $0.name == "Perseids" })
    }

    func testQuadrantidsWrapNewYear() {
        // Active window Dec 28 → Jan 12, spanning the year boundary.
        XCTAssertTrue(MeteorShowers.isActive(quadrantids, on: date(2026, 12, 30)))
        XCTAssertTrue(MeteorShowers.isActive(quadrantids, on: date(2027, 1, 3)))
        XCTAssertFalse(MeteorShowers.isActive(quadrantids, on: date(2026, 6, 15)))
    }

    func testNoShowerActiveInLateJune() {
        XCTAssertTrue(MeteorShowers.active(on: date(2026, 6, 24)).isEmpty)
    }

    func testDaysUntilPeakIsZeroOnPeakDay() {
        XCTAssertEqual(MeteorShowers.daysUntilPeak(geminids, from: date(2026, 12, 14)), 0)
    }

    func testDaysUntilPeakCountsForward() {
        XCTAssertEqual(MeteorShowers.daysUntilPeak(geminids, from: date(2026, 12, 4)), 10)
    }

    func testNextUpcomingFromLateJuneIsDeltaAquariids() {
        // After late June, the next peak (Jul 30) is the Delta Aquariids.
        XCTAssertEqual(MeteorShowers.nextUpcoming(after: date(2026, 6, 24))?.name, "Delta Aquariids")
    }

    private var quadrantids: MeteorShower { MeteorShowers.all.first { $0.name == "Quadrantids" }! }
    private var geminids: MeteorShower { MeteorShowers.all.first { $0.name == "Geminids" }! }
}
