import Testing
@testable import CelestialCore

@Suite("Atmospheric refraction")
struct RefractionTests {
    // At the horizon refraction is the familiar ~34′ (≈0.566°): the reason the
    // setting Sun appears wholly above the horizon when geometrically it is below.
    @Test("≈ 34′ at the horizon")
    func horizon() {
        let lift = Refraction.apparentAltitude(fromTrue: .degrees(0)).degrees
        // Bennett's fit gives ~0.575° at h=0; assert it lands near the textbook 34′.
        #expect(abs(lift - 0.566) < 0.05)
        #expect(lift > 0.5 && lift < 0.65)
    }

    @Test("near zero high up (< 0.02° at 45°)")
    func highUp() {
        let lift = Refraction.apparentAltitude(fromTrue: .degrees(45)).degrees - 45.0
        #expect(lift > 0)
        #expect(lift < 0.02)
    }

    @Test("refraction always lifts the body upward")
    func alwaysPositive() {
        for trueAlt in stride(from: 0.0, through: 89.0, by: 7.0) {
            let lift = Refraction.apparentAltitude(fromTrue: .degrees(trueAlt)).degrees - trueAlt
            #expect(lift >= 0)
        }
    }

    @Test("refraction shrinks monotonically with altitude")
    func monotonic() {
        let low = Refraction.apparentAltitude(fromTrue: .degrees(5)).degrees - 5.0
        let mid = Refraction.apparentAltitude(fromTrue: .degrees(30)).degrees - 30.0
        let high = Refraction.apparentAltitude(fromTrue: .degrees(70)).degrees - 70.0
        #expect(low > mid)
        #expect(mid > high)
    }

    // The two formulae are independent fits, but well away from the horizon they
    // invert each other to better than ~0.01°.
    @Test("true ↔ apparent round-trips above the horizon")
    func roundTrip() {
        for trueAlt in [10.0, 20.0, 45.0, 70.0] {
            let apparent = Refraction.apparentAltitude(fromTrue: .degrees(trueAlt))
            let back = Refraction.trueAltitude(fromApparent: apparent)
            #expect(abs(back.degrees - trueAlt) < 0.01)
        }
    }

    @Test("at the zenith refraction is negligible")
    func zenith() {
        let lift = Refraction.apparentAltitude(fromTrue: .degrees(90)).degrees - 90.0
        #expect(abs(lift) < 1e-3)
    }
}
