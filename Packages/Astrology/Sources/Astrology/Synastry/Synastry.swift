import CelestialCore

/// An aspect between one person's body and another's — the building block of
/// relationship astrology.
public struct SynastryAspect: Sendable, Hashable, Identifiable {
    public let a: AstroBody   // person A's body
    public let b: AstroBody   // person B's body
    public let kind: AspectKind
    public let orb: Double

    /// How harmonious this contact reads, in −1 (challenging) … +1 (flowing).
    public var harmony: Double {
        switch kind {
        case .trine: 1.0
        case .sextile: 0.6
        case .conjunction: 0.4
        case .biquintile, .quintile: 0.3
        case .semisextile: 0.1
        case .opposition: -0.4
        case .quincunx: -0.3
        case .square: -0.7
        case .semisquare, .sesquiquadrate: -0.3
        }
    }

    public var id: String { "\(a.rawValue)-\(kind.rawValue)-\(b.rawValue)" }

    public init(a: AstroBody, b: AstroBody, kind: AspectKind, orb: Double) {
        self.a = a; self.b = b; self.kind = kind; self.orb = orb
    }
}

/// A compatibility read between two charts.
public struct SynastryReport: Sendable {
    public let aspects: [SynastryAspect]   // tightest first
    public let score: Int                  // 0…100 (50 = neutral)
    public let summary: String
}

/// Cross-aspects and a compatibility score between two people's charts.
public enum Synastry {

    public static func report(_ chartA: NatalChart, _ chartB: NatalChart,
                              policy: OrbPolicy = .default) -> SynastryReport {
        let aspects = self.aspects(chartA.positions, chartB.positions, policy: policy)
        let (score, summary) = compatibility(aspects)
        return SynastryReport(aspects: aspects, score: score, summary: summary)
    }

    /// All inter-chart aspects within the orb policy, tightest first.
    public static func aspects(_ a: [BodyPosition], _ b: [BodyPosition],
                               policy: OrbPolicy = .default) -> [SynastryAspect] {
        let kinds = policy.includeMinor ? AspectKind.allCases : AspectKind.allCases.filter(\.isMajor)
        var out: [SynastryAspect] = []
        for pa in a {
            for pb in b {
                let sep = AspectFinder.separationDegrees(pa.longitude, pb.longitude)
                var best: (AspectKind, Double)?
                for kind in kinds {
                    let dev = abs(sep - kind.angle)
                    let allowed = policy.orb(for: kind, between: pa.body, and: pb.body)
                    if dev <= allowed, best == nil || dev < best!.1 { best = (kind, dev) }
                }
                if let best { out.append(.init(a: pa.body, b: pb.body, kind: best.0, orb: best.1)) }
            }
        }
        return out.sorted { $0.orb < $1.orb }
    }

    /// A 0…100 score from harmony weighted by tightness and the bodies involved.
    private static func compatibility(_ aspects: [SynastryAspect]) -> (Int, String) {
        var weightedSum = 0.0
        var totalWeight = 0.0
        for asp in aspects {
            let allowed = OrbPolicy.default.orb(for: asp.kind, between: asp.a, and: asp.b)
            let closeness = max(0.1, 1.0 - asp.orb / max(allowed, 0.1))
            let importance = bodyWeight(asp.a) * bodyWeight(asp.b)
            let w = closeness * importance
            weightedSum += asp.harmony * w
            totalWeight += w
        }
        let raw = totalWeight > 0 ? weightedSum / totalWeight : 0   // −1…1
        let score = max(0, min(100, Int((50.0 + 45.0 * raw).rounded())))
        let summary: String
        switch score {
        case 75...: summary = "Strong, easy flow — you bring out the best in each other."
        case 60..<75: summary = "Warm and supportive, with room to grow."
        case 45..<60: summary = "A balanced mix of ease and friction — workable chemistry."
        case 30..<45: summary = "Real attraction, but with tension that needs tending."
        default: summary = "Challenging contacts dominate — intense, and hard work."
        }
        return (score, summary)
    }

    /// Relationship bodies (luminaries, Venus, Mars) carry more weight.
    private static func bodyWeight(_ b: AstroBody) -> Double {
        switch b {
        case .sun, .moon: 1.4
        case .venus, .mars: 1.3
        case .mercury, .jupiter: 1.0
        case .saturn: 0.9
        default: 0.6
        }
    }
}
