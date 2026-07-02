import CelestialCore

/// The midpoint "relationship chart": each body placed at the midpoint of the
/// two people's positions, with composite angles. A single chart that describes
/// the relationship as its own entity.
public struct CompositeChart: Sendable {
    public let positions: [BodyPosition]
    public let ascendant: Angle
    public let midheaven: Angle
    public let aspects: [Aspect]

    public func position(of body: AstroBody) -> BodyPosition? {
        positions.first { $0.body == body }
    }
}

public enum Composite {

    public static func chart(_ a: NatalChart, _ b: NatalChart,
                             policy: OrbPolicy = .default) -> CompositeChart {
        var positions: [BodyPosition] = []
        for pa in a.positions {
            guard let pb = b.position(of: pa.body) else { continue }
            positions.append(BodyPosition(body: pa.body,
                                          longitude: midpoint(pa.longitude, pb.longitude)))
        }
        let asc = midpoint(a.angles.ascendant, b.angles.ascendant)
        let mc = midpoint(a.angles.midheaven, b.angles.midheaven)
        let aspects = AspectFinder.aspects(among: positions, policy: policy)
        return CompositeChart(positions: positions, ascendant: asc, midheaven: mc, aspects: aspects)
    }

    /// The closer of the two midpoints of two ecliptic longitudes (shorter arc).
    static func midpoint(_ x: Angle, _ y: Angle) -> Angle {
        var d = (y.degrees - x.degrees).truncatingRemainder(dividingBy: 360.0)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return Angle.degrees(x.degrees + d / 2.0).normalized
    }
}
