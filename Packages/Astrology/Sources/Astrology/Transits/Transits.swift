import CelestialCore

/// A transiting body forming an aspect to a natal body. Distinct from `Aspect`
/// because the two ends come from different charts (and may be the same body —
/// e.g. transiting Saturn to natal Saturn is a Saturn return).
public struct TransitHit: Sendable, Hashable {
    public let transiting: AstroBody
    public let natal: AstroBody
    public let kind: AspectKind
    /// Deviation from exact, in degrees.
    public let orb: Double
    /// True when the transiting body is moving toward exact (tightening).
    public let isApplying: Bool?

    public init(transiting: AstroBody, natal: AstroBody, kind: AspectKind, orb: Double, isApplying: Bool?) {
        self.transiting = transiting
        self.natal = natal
        self.kind = kind
        self.orb = orb
        self.isApplying = isApplying
    }
}

/// Cross-aspects between a moving (transiting) chart and a fixed natal chart.
public enum Transits {

    /// All transit→natal aspects within the orb policy, tightest first.
    /// `transiting` should carry speeds (for applying/separating); `natal` is fixed.
    public static func hits(
        transiting: [BodyPosition],
        natal: [BodyPosition],
        policy: OrbPolicy = .default
    ) -> [TransitHit] {
        let kinds = policy.includeMinor ? AspectKind.allCases : AspectKind.allCases.filter(\.isMajor)
        var results: [TransitHit] = []

        for t in transiting {
            for n in natal {
                let separation = AspectFinder.separationDegrees(t.longitude, n.longitude)
                var best: (kind: AspectKind, orb: Double)?
                for kind in kinds {
                    let deviation = abs(separation - kind.angle)
                    let allowed = policy.orb(for: kind, between: t.body, and: n.body)
                    if deviation <= allowed, best == nil || deviation < best!.orb {
                        best = (kind, deviation)
                    }
                }
                guard let best else { continue }
                results.append(
                    TransitHit(transiting: t.body, natal: n.body, kind: best.kind,
                               orb: best.orb, isApplying: applying(t, n, kind: best.kind))
                )
            }
        }
        return results.sorted { $0.orb < $1.orb }
    }

    /// Whether the transit is applying: only the transiting body moves.
    static func applying(_ t: BodyPosition, _ n: BodyPosition, kind: AspectKind) -> Bool? {
        guard let speed = t.speed else { return nil }
        let eps = 1.0 / 24.0 // an hour, in days
        let now = AspectFinder.separationDegrees(t.longitude, n.longitude)
        let next = AspectFinder.separationDegrees(
            Angle.degrees(t.longitude.degrees + speed * eps), n.longitude)
        return abs(next - kind.angle) < abs(now - kind.angle)
    }
}
