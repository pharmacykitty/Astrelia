import Testing
import Foundation
@testable import CelestialCore

@Suite("Julian Day")
struct JulianDayTests {
    @Test("J2000.0 standard epoch → 2451545.0")
    func j2000() {
        #expect(abs(JulianDay(year: 2000, month: 1, day: 1.5).value - 2451545.0) < 1e-6)
    }

    @Test("Meeus 7.a — Sputnik launch (1957 Oct 4.81)")
    func sputnik() {
        #expect(abs(JulianDay(year: 1957, month: 10, day: 4.81).value - 2436116.31) < 1e-6)
    }

    @Test("1900 January 1.0 → 2415020.5")
    func y1900() {
        #expect(abs(JulianDay(year: 1900, month: 1, day: 1.0).value - 2415020.5) < 1e-6)
    }

    @Test("absolute Date in UTC maps to J2000")
    func fromDate() {
        var components = DateComponents()
        components.year = 2000; components.month = 1; components.day = 1
        components.hour = 12; components.minute = 0; components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: components)!
        #expect(abs(JulianDay(date).value - 2451545.0) < 1e-6)
    }

    @Test("Julian centuries since J2000 is zero at the epoch")
    func centuries() {
        #expect(abs(JulianDay.j2000.julianCenturiesSinceJ2000) < 1e-12)
    }
}

@Suite("Sidereal time")
struct SiderealTimeTests {
    // Meeus example 12.a: 1987 April 10, 0h UT → JD 2446895.5, GMST = 13h10m46.3668s.
    @Test("Meeus 12.a — GMST at 0h UT")
    func meeus12a() {
        let gmst = SiderealTime.greenwichMean(at: JulianDay(2446895.5))
        #expect(abs(gmst.degrees - 197.693195) < 1e-3)
    }

    // Meeus example 12.b: 1987 April 10, 19h21m00s UT → JD 2446896.30625.
    @Test("Meeus 12.b — GMST at 19h21m UT")
    func meeus12b() {
        let gmst = SiderealTime.greenwichMean(at: JulianDay(2446896.30625))
        #expect(abs(gmst.degrees - 128.7378734) < 1e-3)
    }
}
