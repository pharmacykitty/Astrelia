import Foundation

/// An in-memory star catalog with lookup indices and common queries.
///
/// Immutable and `Sendable`, so it can be built once and shared freely across
/// actors / rendering tasks.
public struct StarCatalog: Sendable {
    public let stars: [Star]

    private let indexById: [Int: Int]
    private let indexByHipparcos: [Int: Int]
    private let indexByProperName: [String: Int]   // keyed on lowercased name

    public init(stars: [Star]) {
        self.stars = stars
        var byId: [Int: Int] = [:]
        var byHip: [Int: Int] = [:]
        var byName: [String: Int] = [:]
        for (offset, star) in stars.enumerated() {
            byId[star.id] = offset
            if let hip = star.hipparcos { byHip[hip] = offset }
            if let name = star.properName { byName[name.lowercased()] = offset }
        }
        self.indexById = byId
        self.indexByHipparcos = byHip
        self.indexByProperName = byName
    }

    public var count: Int { stars.count }

    /// Look up a star by its HYG database id.
    public func star(id: Int) -> Star? {
        indexById[id].map { stars[$0] }
    }

    /// Look up a star by its Hipparcos catalog number.
    public func star(hipparcos: Int) -> Star? {
        indexByHipparcos[hipparcos].map { stars[$0] }
    }

    /// Look up a star by proper name (case-insensitive), e.g. "Vega".
    public func star(named name: String) -> Star? {
        indexByProperName[name.lowercased()].map { stars[$0] }
    }

    /// All stars at least as bright as `magnitude` (apparent; lower = brighter).
    public func stars(brighterThan magnitude: Double) -> [Star] {
        stars.filter { $0.apparentMagnitude <= magnitude }
    }

    /// The `count` brightest stars, brightest first.
    public func brightest(_ count: Int) -> [Star] {
        Array(stars.sorted { $0.apparentMagnitude < $1.apparentMagnitude }.prefix(count))
    }

    /// Only stars with a known distance (usable in 3D / Galaxy Map mode).
    public var starsWithKnownDistance: [Star] {
        stars.filter { $0.distanceParsecs != nil }
    }
}

extension StarCatalog {
    /// Build a catalog by parsing HYG CSV data.
    public static func hyg(csv data: Data) throws -> StarCatalog {
        StarCatalog(stars: try HYGCatalog.parse(csv: data))
    }

    /// Build a catalog by parsing a HYG CSV string.
    public static func hyg(csv string: String) throws -> StarCatalog {
        StarCatalog(stars: try HYGCatalog.parse(csv: string))
    }
}
