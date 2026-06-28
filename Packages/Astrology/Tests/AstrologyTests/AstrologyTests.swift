import Testing
import CelestialCore
@testable import Astrology

// Smallest absolute angular difference in degrees, range [0,180].
private func angDiff(_ a: Double, _ b: Double) -> Double {
    var d = abs(a - b).truncatingRemainder(dividingBy: 360.0)
    if d > 180 { d = 360 - d }
    return d
}

// MARK: - Zodiac

@Test func zodiacSignPlacement() {
    #expect(ZodiacSign(longitude: .degrees(0)) == .aries)
    #expect(ZodiacSign(longitude: .degrees(29.9)) == .aries)
    #expect(ZodiacSign(longitude: .degrees(30)) == .taurus)
    #expect(ZodiacSign(longitude: .degrees(215)) == .scorpio) // 215 = 5° Scorpio
    #expect(ZodiacSign(longitude: .degrees(359.5)) == .pisces)
    #expect(ZodiacSign(longitude: .degrees(360)) == .aries)  // wraps
}

@Test func zodiacPositionDMS() {
    // Scorpio begins at 210°, so 14°23′ Scorpio = 210 + 14 + 23/60.
    let p = ZodiacPosition(longitude: .degrees(210.0 + 14.0 + 23.0 / 60.0))
    #expect(p.sign == .scorpio)
    #expect(p.dms.degrees == 14)
    #expect(p.dms.minutes == 23)
    #expect(p.description == "14°23′ Scorpio")
}

@Test func signProperties() {
    #expect(ZodiacSign.aries.element == .fire)
    #expect(ZodiacSign.taurus.modality == .fixed)
    #expect(ZodiacSign.leo.traditionalRuler == .sun)
    #expect(ZodiacSign.scorpio.traditionalRuler == .mars) // traditional ruler
}

// MARK: - Ayanamsa

@Test func lahiriAyanamsaModernValue() {
    // ~24°11′ in mid-2024; allow a couple arcminutes for the linear model.
    let jd = JulianDay(year: 2024, month: 7, day: 1.0)
    let a = Ayanamsa.lahiri.value(at: jd).degrees
    #expect(abs(a - 24.18) < 0.1)
}

@Test func siderealSubtractsAyanamsa() {
    let jd = JulianDay(year: 2024, month: 7, day: 1.0)
    let tropical = Angle.degrees(50) // 20° Taurus
    let sidereal = Zodiac.sidereal(.lahiri).longitude(fromTropical: tropical, at: jd)
    let expected = (50.0 - Ayanamsa.lahiri.value(at: jd).degrees)
    #expect(angDiff(sidereal.degrees, expected) < 1e-6)
}

// MARK: - Chart angles (Ascendant / MC)

@Test func equatorAnalyticCase() {
    // At the equator with the vernal point culminating (RAMC = 0):
    //   MC  = 0° (0° Aries),  ASC = 90° (0° Cancer).
    let angles = ChartAngles(localSiderealTime: .degrees(0),
                             obliquity: .degrees(23.4392911),
                             latitude: .degrees(0))
    #expect(angDiff(angles.midheaven.degrees, 0) < 1e-6)
    #expect(angDiff(angles.ascendant.degrees, 90) < 1e-6)
}

@Test func midheavenRightAscensionEqualsRAMC() {
    // The MC is the ecliptic point on the meridian, so its RA must equal RAMC.
    let ε = Angle.degrees(23.4392911)
    let ramc = Angle.degrees(123.456)
    let angles = ChartAngles(localSiderealTime: ramc, obliquity: ε, latitude: .degrees(51.5))
    let eq = CoordinateTransform.equatorial(
        fromEcliptic: EclipticCoordinates(longitude: angles.midheaven, latitude: .zero),
        obliquity: ε)
    #expect(angDiff(eq.rightAscension.degrees, ramc.degrees) < 1e-6)
}

@Test func ascendantLiesOnEasternHorizon() {
    // The Ascendant, as an ecliptic point, must sit on the horizon (alt ≈ 0)
    // on the eastern side (azimuth in 0°–180°).
    let ε = Angle.degrees(23.4392911)
    let ramc = Angle.degrees(200.0)
    let lat = Angle.degrees(40.0)
    let location = GeographicLocation(latitude: lat, longitude: .degrees(0))
    let angles = ChartAngles(localSiderealTime: ramc, obliquity: ε, latitude: lat)

    let eq = CoordinateTransform.equatorial(
        fromEcliptic: EclipticCoordinates(longitude: angles.ascendant, latitude: .zero),
        obliquity: ε)
    let horiz = CoordinateTransform.horizontal(eq, at: location, localSiderealTime: ramc)
    #expect(abs(horiz.altitude.degrees) < 1e-6)               // on the horizon
    #expect(horiz.azimuth.degrees > 0 && horiz.azimuth.degrees < 180) // rising in the east
}

// MARK: - House systems

@Test func wholeSignCuspsAreSignBoundaries() {
    let angles = ChartAngles(localSiderealTime: .degrees(200), obliquity: .degrees(23.44), latitude: .degrees(40))
    let h = Houses.cusps(.wholeSign, angles: angles)
    let firstSign = ZodiacSign(longitude: angles.ascendant)
    #expect(angDiff(h.cusp(1).degrees, firstSign.startLongitude.degrees) < 1e-6)
    for i in 1...12 {
        let rem = h.cusp(i).degrees.truncatingRemainder(dividingBy: 30)
        #expect(min(rem, 30 - rem) < 1e-6) // on a 30° boundary
    }
}

@Test func equalHousesAre30Apart() {
    let angles = ChartAngles(localSiderealTime: .degrees(200), obliquity: .degrees(23.44), latitude: .degrees(40))
    let h = Houses.cusps(.equal, angles: angles)
    #expect(angDiff(h.cusp(1).degrees, angles.ascendant.degrees) < 1e-9)
    for i in 1...12 {
        let next = h.cusp(i % 12 + 1)
        #expect(angDiff(Houses.forwardArc(from: h.cusp(i), to: next), 30) < 1e-9)
    }
}

@Test func porphyryOppositeCuspsAndAngles() {
    let angles = ChartAngles(localSiderealTime: .degrees(200), obliquity: .degrees(23.44), latitude: .degrees(40))
    let h = Houses.cusps(.porphyry, angles: angles)
    #expect(angDiff(h.cusp(1).degrees, angles.ascendant.degrees) < 1e-9)
    #expect(angDiff(h.cusp(10).degrees, angles.midheaven.degrees) < 1e-9)
    for i in 1...6 {
        #expect(angDiff(h.cusp(i).degrees, h.cusp(i + 6).degrees) > 179.999) // opposite (≈180°)
    }
}

@Test func placidusSatisfiesSemiArcConditionAndOrdering() {
    let ε = Angle.degrees(23.4392911)
    let ramc = Angle.degrees(200.0)
    let lat = Angle.degrees(40.0)
    let angles = ChartAngles(localSiderealTime: ramc, obliquity: ε, latitude: lat)
    let h = Houses.cusps(.placidus, angles: angles)
    #expect(!h.fellBack)
    #expect(h.system == .placidus)

    // Angles land on the right cusps.
    #expect(angDiff(h.cusp(1).degrees, angles.ascendant.degrees) < 1e-6)
    #expect(angDiff(h.cusp(10).degrees, angles.midheaven.degrees) < 1e-6)

    // Cusp 11 must satisfy the Placidus definition: its right-ascension offset
    // from RAMC equals one third of its own semi-diurnal arc.
    func ra(_ λ: Angle) -> Angle {
        CoordinateTransform.equatorial(
            fromEcliptic: EclipticCoordinates(longitude: λ, latitude: .zero),
            obliquity: ε).rightAscension
    }
    let c11 = h.cusp(11)
    let δ = Angle.asin(ε.sine * c11.sine)
    let sa = Angle.acos(-lat.tangent * δ.tangent).degrees
    var mdoffset = (ra(c11).degrees - ramc.degrees).truncatingRemainder(dividingBy: 360)
    if mdoffset < 0 { mdoffset += 360 }
    #expect(angDiff(mdoffset, sa / 3) < 1e-4)

    // Cusps strictly advance around the wheel.
    for i in 1...12 {
        let arc = Houses.forwardArc(from: h.cusp(i), to: h.cusp(i % 12 + 1))
        #expect(arc > 0 && arc < 360)
    }
}

@Test func placidusFallsBackAtHighLatitude() {
    let angles = ChartAngles(localSiderealTime: .degrees(200), obliquity: .degrees(23.44), latitude: .degrees(70))
    let h = Houses.cusps(.placidus, angles: angles)
    #expect(h.fellBack)
    #expect(h.system == .porphyry)
    // Still a valid, complete set of cusps.
    #expect(h.cusps.count == 12)
}

@Test func houseLookup() {
    let angles = ChartAngles(localSiderealTime: .degrees(200), obliquity: .degrees(23.44), latitude: .degrees(40))
    let h = Houses.cusps(.equal, angles: angles)
    // A point just past cusp 1 is in house 1; just before cusp 1 is in house 12.
    #expect(h.house(of: angles.ascendant + .degrees(1)) == 1)
    #expect(h.house(of: angles.ascendant - .degrees(1)) == 12)
}

// MARK: - Aspects

@Test func aspectDetectionBasics() {
    let positions = [
        BodyPosition(body: .sun, longitude: .degrees(10)),
        BodyPosition(body: .moon, longitude: .degrees(130)),   // trine to Sun (120)
        BodyPosition(body: .mars, longitude: .degrees(100)),   // square to Sun (90)
        BodyPosition(body: .venus, longitude: .degrees(11)),   // conjunct Sun (~1°)
    ]
    let aspects = AspectFinder.aspects(among: positions)
    func kind(_ a: AstroBody, _ b: AstroBody) -> AspectKind? {
        aspects.first { ($0.bodyA == a && $0.bodyB == b) || ($0.bodyA == b && $0.bodyB == a) }?.kind
    }
    #expect(kind(.sun, .moon) == .trine)
    #expect(kind(.sun, .mars) == .square)
    #expect(kind(.sun, .venus) == .conjunction)
}

@Test func aspectRespectsOrb() {
    // 128° apart = 8° off a trine: inside the luminary-boosted orb (7+2=9°)…
    let withLuminary = [
        BodyPosition(body: .sun, longitude: .degrees(0)),
        BodyPosition(body: .mars, longitude: .degrees(128)),
    ]
    #expect(AspectFinder.aspects(among: withLuminary).contains { $0.kind == .trine })

    // …but outside the base 7° orb between two non-luminaries.
    let noLuminary = [
        BodyPosition(body: .jupiter, longitude: .degrees(0)),
        BodyPosition(body: .mars, longitude: .degrees(128)),
    ]
    #expect(!AspectFinder.aspects(among: noLuminary).contains { $0.kind == .trine })
}

@Test func minorAspectsTogglable() {
    let positions = [
        BodyPosition(body: .sun, longitude: .degrees(0)),
        BodyPosition(body: .mars, longitude: .degrees(150)), // quincunx
    ]
    #expect(AspectFinder.aspects(among: positions, policy: OrbPolicy(includeMinor: true))
        .contains { $0.kind == .quincunx })
    #expect(!AspectFinder.aspects(among: positions, policy: OrbPolicy(includeMinor: false))
        .contains { $0.kind == .quincunx })
}

@Test func applyingVsSeparating() {
    // Sun at 8°, Moon at 0°; Moon faster and catching up → applying conjunction.
    let positions = [
        BodyPosition(body: .sun, longitude: .degrees(8), speed: 1.0),
        BodyPosition(body: .moon, longitude: .degrees(0), speed: 13.0),
    ]
    let a = AspectFinder.aspects(among: positions).first { $0.kind == .conjunction }
    #expect(a?.isApplying == true)
}

// MARK: - Ephemeris & chart

@Test func allBodiesResolve() {
    let ephem = CelestialCoreEphemeris()
    let jd = JulianDay(year: 2024, month: 7, day: 1.0)
    for body in AstroBody.allCases {
        #expect(ephem.longitude(of: body, at: jd) != nil, "\(body.name) should resolve")
    }
}

@Test func sunInExpectedSignJuly() {
    // Around 1 July the Sun is in Cancer (tropical).
    let jd = JulianDay(year: 2024, month: 7, day: 1.0)
    let lon = CelestialCoreEphemeris().longitude(of: .sun, at: jd)!
    #expect(ZodiacSign(longitude: lon) == .cancer)
}

@Test func nodesAreOppositeAndRetrograde() {
    let jd = JulianDay(year: 2024, month: 7, day: 1.0)
    let ephem = CelestialCoreEphemeris()
    let north = ephem.longitude(of: .northNode, at: jd)!
    let south = ephem.longitude(of: .southNode, at: jd)!
    #expect(angDiff(north.degrees, south.degrees) - 180 < 1e-6)
    let pos = ephem.position(of: .northNode, at: jd, zodiac: .tropical)!
    #expect(pos.isRetrograde) // mean node always moves backward
}

@Test func natalChartAssembles() {
    let jd = JulianDay(year: 1990, month: 3, day: 21.5)
    let loc = GeographicLocation(latitude: .degrees(40.7128), longitude: .degrees(-74.0060)) // NYC
    let chart = NatalChart(at: jd, location: loc,
                           settings: ChartSettings(houseSystem: .placidus, zodiac: .tropical))
    #expect(chart.position(of: .sun) != nil)
    #expect(chart.position(of: .pluto) != nil) // planets now resolve
    #expect(chart.house(of: .sun) != nil)
    #expect(chart.partOfFortune != nil)        // Sun & Moon both available
    #expect(chart.missingBodies.isEmpty)       // every requested body computed
    #expect(chart.houses.cusps.count == 12)
}
