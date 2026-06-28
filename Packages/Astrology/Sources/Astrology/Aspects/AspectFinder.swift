import CelestialCore

/// Detects aspects among a set of body positions.
public enum AspectFinder {

    /// All aspects among `positions` within the orb policy. O(n²) over bodies
    /// (n ≈ 12), so trivial. Each unordered pair yields at most one aspect — the
    /// tightest matching kind.
    public static func aspects(
        among positions: [BodyPosition],
        policy: OrbPolicy = .default
    ) -> [Aspect] {
        var results: [Aspect] = []
        let kinds = policy.includeMinor
            ? AspectKind.allCases
            : AspectKind.allCases.filter(\.isMajor)

        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let a = positions[i]
                let b = positions[j]
                let separation = separationDegrees(a.longitude, b.longitude)

                var best: (kind: AspectKind, orb: Double)?
                for kind in kinds {
                    let deviation = abs(separation - kind.angle)
                    let allowed = policy.orb(for: kind, between: a.body, and: b.body)
                    if deviation <= allowed {
                        if best == nil || deviation < best!.orb {
                            best = (kind, deviation)
                        }
                    }
                }

                guard let best else { continue }
                results.append(
                    Aspect(
                        bodyA: a.body,
                        bodyB: b.body,
                        kind: best.kind,
                        orb: best.orb,
                        isApplying: applying(a, b, kind: best.kind)
                    )
                )
            }
        }
        return results
    }

    /// Absolute separation between two longitudes, folded to [0°, 180°].
    static func separationDegrees(_ a: Angle, _ b: Angle) -> Double {
        var d = abs(a.normalized.degrees - b.normalized.degrees)
            .truncatingRemainder(dividingBy: 360.0)
        if d > 180 { d = 360 - d }
        return d
    }

    /// Whether the aspect is applying (orb tightening). Needs both speeds; nil
    /// otherwise. Uses the sign of d(separation−exact)/dt.
    static func applying(_ a: BodyPosition, _ b: BodyPosition, kind: AspectKind) -> Bool? {
        guard let sa = a.speed, let sb = b.speed else { return nil }
        let eps = 1.0 / 86400.0 // one second of time, in days
        let future = separationDegrees(
            Angle.degrees(a.longitude.degrees + sa * eps),
            Angle.degrees(b.longitude.degrees + sb * eps)
        )
        let now = separationDegrees(a.longitude, b.longitude)
        let deviationNow = abs(now - kind.angle)
        let deviationNext = abs(future - kind.angle)
        return deviationNext < deviationNow
    }
}
