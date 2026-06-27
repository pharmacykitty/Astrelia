import Foundation
import simd

/// A constellation's stick-figure: one or more polylines of equatorial points.
/// Source: d3-celestial constellation lines (Olaf Frohn, BSD-2-Clause).
struct Constellation: Identifiable, Sendable {
    let id: String                       // IAU abbreviation, e.g. "Ori"
    let polylines: [[SIMD2<Double>]]     // each point is (rightAscension°, declination°)
}

enum ConstellationData {
    /// Loads and parses the bundled GeoJSON line set.
    static func loadBundled() -> [Constellation] {
        guard let url = Bundle.main.url(forResource: "constellation_lines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(FeatureCollection.self, from: data) else {
            return []
        }
        return collection.features.map { feature in
            Constellation(
                id: feature.id,
                polylines: feature.geometry.coordinates.map { line in
                    line.compactMap { pair in
                        pair.count == 2 ? SIMD2(pair[0], pair[1]) : nil
                    }
                }
            )
        }
    }

    // Minimal GeoJSON shapes for the line file (MultiLineString features).
    private struct FeatureCollection: Decodable { let features: [Feature] }
    private struct Feature: Decodable {
        let id: String
        let geometry: Geometry
    }
    private struct Geometry: Decodable {
        let coordinates: [[[Double]]]    // [polyline][point][ra, dec]
    }
}
