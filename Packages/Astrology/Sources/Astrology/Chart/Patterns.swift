import CelestialCore

/// A configuration of three or more bodies — the shapes astrologers read first.
public struct ChartPattern: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case stellium, grandTrine, tSquare, grandCross, yod

        public var title: String {
            switch self {
            case .stellium: "Stellium"
            case .grandTrine: "Grand Trine"
            case .tSquare: "T-Square"
            case .grandCross: "Grand Cross"
            case .yod: "Yod"
            }
        }
        /// A plain text mark (not an emoji) for chips.
        public var glyph: String {
            switch self {
            case .stellium: "✦"
            case .grandTrine: "△"
            case .tSquare: "⊤"
            case .grandCross: "✛"
            case .yod: "⅄"
            }
        }
    }

    public let kind: Kind
    /// The bodies involved (apex first for T-square / yod).
    public let bodies: [AstroBody]
    /// Short context, e.g. the sign of a stellium or element of a grand trine.
    public let detail: String

    public var id: String {
        kind.rawValue + ":" + bodies.map { String($0.rawValue) }.joined(separator: ",")
    }

    public init(kind: Kind, bodies: [AstroBody], detail: String) {
        self.kind = kind
        self.bodies = bodies
        self.detail = detail
    }
}

/// Detects chart-shape patterns from a chart's positions and aspects. Lunar
/// nodes are excluded (their fixed opposition would manufacture false shapes).
public enum Patterns {

    public static func detect(in chart: NatalChart) -> [ChartPattern] {
        detect(positions: chart.positions, aspects: chart.aspects)
    }

    /// Core detection over raw positions + aspects (testable without a full chart).
    public static func detect(positions: [BodyPosition], aspects: [Aspect]) -> [ChartPattern] {
        let pts = positions.filter { $0.body != .northNode && $0.body != .southNode }
        let bodies = pts.map(\.body)
        let signOf = Dictionary(uniqueKeysWithValues: pts.map { ($0.body, $0.position.sign) })
        let lookup = aspectLookup(aspects)
        func aspect(_ a: AstroBody, _ b: AstroBody) -> AspectKind? { lookup[key(a, b)] }
        func has(_ k: AspectKind, _ a: AstroBody, _ b: AstroBody) -> Bool { aspect(a, b) == k }

        var out: [ChartPattern] = []
        out += stelliums(pts)

        // Triple shapes: grand trine, yod, T-square apex.
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                for k in (j + 1)..<bodies.count {
                    let (a, b, c) = (bodies[i], bodies[j], bodies[k])

                    if has(.trine, a, b), has(.trine, b, c), has(.trine, a, c) {
                        out.append(.init(kind: .grandTrine, bodies: [a, b, c],
                                         detail: commonElement([a, b, c], signOf) ?? "mixed"))
                    }
                    // Yod: a sextile, both quincunx the apex.
                    if let apex = yodApex(a, b, c, has: has) {
                        let base = [a, b, c].filter { $0 != apex }
                        out.append(.init(kind: .yod, bodies: [apex] + base, detail: "apex \(apex.name)"))
                    }
                    // T-square: an opposition with a third body squaring both (apex).
                    if let apex = tSquareApex(a, b, c, has: has) {
                        let ends = [a, b, c].filter { $0 != apex }
                        out.append(.init(kind: .tSquare, bodies: [apex] + ends,
                                         detail: "apex \(apex.name)"))
                    }
                }
            }
        }

        out += grandCrosses(bodies, has: has)
        return out
    }

    // MARK: Shape helpers

    private static func stelliums(_ pts: [BodyPosition]) -> [ChartPattern] {
        var bySign: [ZodiacSign: [AstroBody]] = [:]
        for p in pts { bySign[p.position.sign, default: []].append(p.body) }
        return bySign
            .filter { $0.value.count >= 3 }
            .sorted { $0.value.count > $1.value.count }
            .map { ChartPattern(kind: .stellium, bodies: $0.value,
                                detail: "\($0.value.count) in \($0.key.name)") }
    }

    private static func yodApex(_ a: AstroBody, _ b: AstroBody, _ c: AstroBody,
                                has: (AspectKind, AstroBody, AstroBody) -> Bool) -> AstroBody? {
        if has(.sextile, a, b), has(.quincunx, c, a), has(.quincunx, c, b) { return c }
        if has(.sextile, a, c), has(.quincunx, b, a), has(.quincunx, b, c) { return b }
        if has(.sextile, b, c), has(.quincunx, a, b), has(.quincunx, a, c) { return a }
        return nil
    }

    private static func tSquareApex(_ a: AstroBody, _ b: AstroBody, _ c: AstroBody,
                                    has: (AspectKind, AstroBody, AstroBody) -> Bool) -> AstroBody? {
        if has(.opposition, a, b), has(.square, c, a), has(.square, c, b) { return c }
        if has(.opposition, a, c), has(.square, b, a), has(.square, b, c) { return b }
        if has(.opposition, b, c), has(.square, a, b), has(.square, a, c) { return a }
        return nil
    }

    private static func grandCrosses(_ bodies: [AstroBody],
                                     has: (AspectKind, AstroBody, AstroBody) -> Bool) -> [ChartPattern] {
        var out: [ChartPattern] = []
        let n = bodies.count
        for i in 0..<n { for j in (i + 1)..<n { for k in (j + 1)..<n { for l in (k + 1)..<n {
            let q = [bodies[i], bodies[j], bodies[k], bodies[l]]
            // Two oppositions + four squares closing the cross.
            for (x, y) in [(0, 1), (0, 2), (0, 3)] {
                let rest = [0, 1, 2, 3].filter { $0 != x && $0 != y }
                let (p, r) = (rest[0], rest[1])
                if has(.opposition, q[x], q[y]), has(.opposition, q[p], q[r]),
                   has(.square, q[x], q[p]), has(.square, q[x], q[r]),
                   has(.square, q[y], q[p]), has(.square, q[y], q[r]) {
                    out.append(.init(kind: .grandCross, bodies: q, detail: "four-square cross"))
                    break
                }
            }
        }}}}
        return out
    }

    private static func commonElement(_ bodies: [AstroBody], _ signOf: [AstroBody: ZodiacSign]) -> String? {
        let signs = bodies.compactMap { signOf[$0] }
        guard let first = signs.first else { return nil }
        let el = first.element
        guard signs.allSatisfy({ $0.element == el }) else { return nil }
        switch el { case .fire: return "fire"; case .earth: return "earth"
        case .air: return "air"; case .water: return "water" }
    }

    // MARK: Aspect lookup

    private static func aspectLookup(_ aspects: [Aspect]) -> [Int: AspectKind] {
        var d: [Int: AspectKind] = [:]
        for a in aspects { d[key(a.bodyA, a.bodyB)] = a.kind }
        return d
    }
    private static func key(_ a: AstroBody, _ b: AstroBody) -> Int {
        let lo = min(a.rawValue, b.rawValue), hi = max(a.rawValue, b.rawValue)
        return lo * 100 + hi
    }
}
