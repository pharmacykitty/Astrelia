import CelestialCore

/// The house-division schemes shipped in v1.
///
/// `.placidus` is the Western mainstream default but is **undefined toward the
/// poles** (the ecliptic degree never rises). Above `Houses.placidusLatitudeLimit`
/// it falls back to `.porphyry` automatically — see `HouseCusps`.
public enum HouseSystem: String, Sendable, Hashable, CaseIterable {
    case wholeSign
    case equal
    case porphyry
    case placidus

    public var name: String {
        switch self {
        case .wholeSign: return "Whole Sign"
        case .equal: return "Equal"
        case .porphyry: return "Porphyry"
        case .placidus: return "Placidus"
        }
    }
}

/// The twelve house cusps of a chart, as tropical ecliptic longitudes, plus the
/// angles they were derived from.
public struct HouseCusps: Sendable, Hashable {
    /// Cusp longitudes, index 0 = house 1 … index 11 = house 12.
    public let cusps: [Angle]
    public let angles: ChartAngles
    /// The system actually used (may differ from the requested one if a
    /// high-latitude fallback kicked in).
    public let system: HouseSystem
    /// True when the requested system was unavailable and a fallback was used.
    public let fellBack: Bool

    /// Longitude of a given house cusp (1...12).
    public func cusp(_ house: Int) -> Angle {
        precondition((1...12).contains(house), "house must be 1...12")
        return cusps[house - 1]
    }

    /// The house (1...12) containing a given ecliptic longitude.
    public func house(of longitude: Angle) -> Int {
        let lon = longitude.normalized.degrees
        for i in 0..<12 {
            let start = cusps[i].normalized.degrees
            let end = cusps[(i + 1) % 12].normalized.degrees
            let span = (end - start).truncatingRemainder(dividingBy: 360.0)
            let normSpan = span < 0 ? span + 360 : span
            var offset = (lon - start).truncatingRemainder(dividingBy: 360.0)
            if offset < 0 { offset += 360 }
            if offset < normSpan { return i + 1 }
        }
        return 1
    }
}

public enum Houses {
    /// Beyond this geographic latitude, Placidus/Koch are undefined; we fall
    /// back to Porphyry rather than emit NaN.
    public static let placidusLatitudeLimit = Angle.degrees(66.0)

    /// Compute house cusps for the given system and chart angles.
    public static func cusps(_ system: HouseSystem, angles: ChartAngles) -> HouseCusps {
        switch system {
        case .wholeSign:
            return HouseCusps(cusps: wholeSign(angles), angles: angles, system: .wholeSign, fellBack: false)
        case .equal:
            return HouseCusps(cusps: equal(angles), angles: angles, system: .equal, fellBack: false)
        case .porphyry:
            return HouseCusps(cusps: porphyry(angles), angles: angles, system: .porphyry, fellBack: false)
        case .placidus:
            if abs(angles.latitude.degrees) >= placidusLatitudeLimit.degrees {
                return HouseCusps(cusps: porphyry(angles), angles: angles, system: .porphyry, fellBack: true)
            }
            guard let p = placidus(angles) else {
                return HouseCusps(cusps: porphyry(angles), angles: angles, system: .porphyry, fellBack: true)
            }
            return HouseCusps(cusps: p, angles: angles, system: .placidus, fellBack: false)
        }
    }

    // MARK: Whole Sign — house 1 is the whole sign containing the Ascendant.

    static func wholeSign(_ a: ChartAngles) -> [Angle] {
        let firstCusp = ZodiacSign(longitude: a.ascendant).startLongitude
        return (0..<12).map { (firstCusp + .degrees(Double($0) * 30.0)).normalized }
    }

    // MARK: Equal — 30° houses measured from the Ascendant degree.

    static func equal(_ a: ChartAngles) -> [Angle] {
        (0..<12).map { (a.ascendant + .degrees(Double($0) * 30.0)).normalized }
    }

    // MARK: Porphyry — trisect each ecliptic quadrant between the angles.

    static func porphyry(_ a: ChartAngles) -> [Angle] {
        let asc = a.ascendant, mc = a.midheaven
        let ic = a.imumCoeli, desc = a.descendant

        // Quadrant spans, each measured forward (increasing longitude).
        let q1 = forwardArc(from: mc, to: asc)   // 10 → 1
        let q2 = forwardArc(from: asc, to: ic)    // 1 → 4
        let q3 = forwardArc(from: ic, to: desc)   // 4 → 7
        let q4 = forwardArc(from: desc, to: mc)   // 7 → 10

        var c = [Angle](repeating: .zero, count: 12)
        c[0] = asc                                   // 1
        c[1] = (asc + .degrees(q2 / 3)).normalized   // 2
        c[2] = (asc + .degrees(2 * q2 / 3)).normalized // 3
        c[3] = ic                                    // 4
        c[4] = (ic + .degrees(q3 / 3)).normalized    // 5
        c[5] = (ic + .degrees(2 * q3 / 3)).normalized // 6
        c[6] = desc                                  // 7
        c[7] = (desc + .degrees(q4 / 3)).normalized  // 8
        c[8] = (desc + .degrees(2 * q4 / 3)).normalized // 9
        c[9] = mc                                     // 10
        c[10] = (mc + .degrees(q1 / 3)).normalized   // 11
        c[11] = (mc + .degrees(2 * q1 / 3)).normalized // 12
        return c
    }

    // MARK: Placidus — trisect the diurnal/nocturnal semi-arcs (iterative).

    /// Returns nil if the geometry is degenerate (circumpolar ecliptic point),
    /// signalling the caller to fall back.
    static func placidus(_ a: ChartAngles) -> [Angle]? {
        let ramc = a.ramc.degrees
        let ε = a.obliquity
        let φ = a.latitude

        // Solve one intermediate cusp by iterating ecliptic longitude until the
        // point's right ascension matches its semi-arc-derived target.
        func solve(initialOffset: Double, target: (_ semiDiurnalArc: Double) -> Double) -> Double? {
            var lon = (ramc + initialOffset).truncatingRemainder(dividingBy: 360.0)
            if lon < 0 { lon += 360 }
            for _ in 0..<30 {
                let λ = Angle.degrees(lon)
                let δ = Angle.asin(ε.sine * λ.sine)            // declination of the point
                let cosSA = -φ.tangent * δ.tangent             // cos(semi-diurnal arc)
                if abs(cosSA) > 1 { return nil }               // circumpolar → fall back
                let sa = Angle.acos(cosSA).degrees             // semi-diurnal arc, degrees
                let αt = Angle.degrees(target(sa))
                // Inverse RA→ecliptic longitude (β = 0): same quadrant as αt.
                let newLon = Angle.atan2(y: αt.sine, x: αt.cosine * ε.cosine).normalized.degrees
                if abs(angularDelta(newLon, lon)) < 1e-9 { return newLon }
                lon = newLon
            }
            return lon
        }

        // Intermediate cusps; opposite cusps follow by +180°.
        // 11: RAMC + ⅓·SA   12: RAMC + ⅔·SA
        //  2: RAMC + 180 − ⅔·(180−SA)    3: RAMC + 180 − ⅓·(180−SA)
        guard
            let c11 = solve(initialOffset: 30, target: { ramc + (1.0 / 3.0) * $0 }),
            let c12 = solve(initialOffset: 60, target: { ramc + (2.0 / 3.0) * $0 }),
            let c2  = solve(initialOffset: 120, target: { ramc + 180 - (2.0 / 3.0) * (180 - $0) }),
            let c3  = solve(initialOffset: 150, target: { ramc + 180 - (1.0 / 3.0) * (180 - $0) })
        else { return nil }

        let asc = a.ascendant, mc = a.midheaven
        var c = [Angle](repeating: .zero, count: 12)
        c[0] = asc                              // 1
        c[1] = Angle.degrees(c2).normalized      // 2
        c[2] = Angle.degrees(c3).normalized      // 3
        c[3] = a.imumCoeli                       // 4
        c[4] = (Angle.degrees(c11) + .degrees(180)).normalized // 5 = 11 + 180
        c[5] = (Angle.degrees(c12) + .degrees(180)).normalized // 6 = 12 + 180
        c[6] = a.descendant                      // 7
        c[7] = (Angle.degrees(c2) + .degrees(180)).normalized  // 8 = 2 + 180
        c[8] = (Angle.degrees(c3) + .degrees(180)).normalized  // 9 = 3 + 180
        c[9] = mc                               // 10
        c[10] = Angle.degrees(c11).normalized    // 11
        c[11] = Angle.degrees(c12).normalized    // 12
        return c
    }

    // MARK: helpers

    /// Forward (increasing-longitude) arc length in degrees, in (0, 360].
    static func forwardArc(from: Angle, to: Angle) -> Double {
        var d = (to.normalized.degrees - from.normalized.degrees)
            .truncatingRemainder(dividingBy: 360.0)
        if d <= 0 { d += 360 }
        return d
    }

    /// Smallest signed difference a − b in degrees, range (−180, 180].
    static func angularDelta(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360.0)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }
}
