import SwiftUI
import simd

/// A notable deep-sky landmark — nebula, cluster, black hole, satellite galaxy.
/// Curated (not a full catalog): the famous objects worth flying to. Positions are
/// real (RA/Dec + distance → equatorial XYZ in parsecs, Sun at origin), matching
/// the star catalog's frame so they sit correctly in the Galaxy Map.
struct Landmark: Identifiable, Hashable {
    let id: String
    let name: String
    let designation: String?          // e.g. "M42", "NGC 7000"
    let type: LandmarkType
    let raDegrees: Double
    let decDegrees: Double
    let distanceLightYears: Double
    let summary: String

    var distanceParsecs: Double { distanceLightYears / 3.2616 }

    var positionParsecs: SIMD3<Float> {
        let ra = Float(raDegrees * .pi / 180)
        let dec = Float(decDegrees * .pi / 180)
        let d = Float(distanceParsecs)
        return SIMD3(d * cos(dec) * cos(ra), d * cos(dec) * sin(ra), d * sin(dec))
    }

    /// How far back the camera should sit when flying to this landmark.
    var suggestedViewDistance: Float {
        switch type {
        case .galaxy: 25000
        case .blackHole: id == "sgr-a" ? 5000 : 250
        default: 300
        }
    }
}

enum LandmarkType: String, CaseIterable {
    case emissionNebula, planetaryNebula, supernovaRemnant
    case openCluster, globularCluster
    case blackHole, galaxy

    var label: String {
        switch self {
        case .emissionNebula: "Emission Nebula"
        case .planetaryNebula: "Planetary Nebula"
        case .supernovaRemnant: "Supernova Remnant"
        case .openCluster: "Open Cluster"
        case .globularCluster: "Globular Cluster"
        case .blackHole: "Black Hole"
        case .galaxy: "Galaxy"
        }
    }

    var symbol: String {
        switch self {
        case .emissionNebula: "smoke.fill"
        case .planetaryNebula: "circle.circle.fill"
        case .supernovaRemnant: "rays"
        case .openCluster: "sparkles"
        case .globularCluster: "circle.hexagongrid.fill"
        case .blackHole: "circle.circle"
        case .galaxy: "hurricane"
        }
    }

    var color: Color {
        switch self {
        case .emissionNebula: Color(red: 1.0, green: 0.45, blue: 0.6)
        case .planetaryNebula: Color(red: 0.40, green: 0.92, blue: 0.85)
        case .supernovaRemnant: Color(red: 0.78, green: 0.55, blue: 1.0)
        case .openCluster: Color(red: 0.72, green: 0.86, blue: 1.0)
        case .globularCluster: Color(red: 1.0, green: 0.85, blue: 0.55)
        case .blackHole: Color(red: 1.0, green: 0.82, blue: 0.6)
        case .galaxy: Color(white: 0.92)
        }
    }
}

enum Landmarks {
    /// Curated list of famous galactic (and a couple of satellite) landmarks.
    static let all: [Landmark] = [
        Landmark(id: "sgr-a", name: "Sagittarius A*", designation: "Sgr A*", type: .blackHole,
                 raDegrees: 266.417, decDegrees: -29.008, distanceLightYears: 26673,
                 summary: "The supermassive black hole at the centre of the Milky Way, ~4.3 million times the Sun's mass."),
        Landmark(id: "m42", name: "Orion Nebula", designation: "M42", type: .emissionNebula,
                 raDegrees: 83.82, decDegrees: -5.39, distanceLightYears: 1344,
                 summary: "A vast stellar nursery in Orion's Sword — the nearest large region of massive star formation."),
        Landmark(id: "m16", name: "Eagle Nebula", designation: "M16", type: .emissionNebula,
                 raDegrees: 274.70, decDegrees: -13.79, distanceLightYears: 7000,
                 summary: "Home of the Pillars of Creation, towering columns of gas and dust forming new stars."),
        Landmark(id: "m8", name: "Lagoon Nebula", designation: "M8", type: .emissionNebula,
                 raDegrees: 270.92, decDegrees: -24.38, distanceLightYears: 4100,
                 summary: "A bright, giant interstellar cloud in Sagittarius, faintly visible to the naked eye."),
        Landmark(id: "m20", name: "Trifid Nebula", designation: "M20", type: .emissionNebula,
                 raDegrees: 270.60, decDegrees: -22.97, distanceLightYears: 5200,
                 summary: "A striking combination of emission, reflection, and dark nebulae split by dust lanes."),
        Landmark(id: "carina", name: "Carina Nebula", designation: "NGC 3372", type: .emissionNebula,
                 raDegrees: 161.27, decDegrees: -59.87, distanceLightYears: 8500,
                 summary: "An enormous southern nebula housing the unstable hypergiant Eta Carinae."),
        Landmark(id: "rosette", name: "Rosette Nebula", designation: "NGC 2237", type: .emissionNebula,
                 raDegrees: 98.44, decDegrees: 4.95, distanceLightYears: 5200,
                 summary: "A flower-shaped cloud in Monoceros with a young open cluster at its heart."),
        Landmark(id: "naamerica", name: "North America Nebula", designation: "NGC 7000", type: .emissionNebula,
                 raDegrees: 314.75, decDegrees: 44.52, distanceLightYears: 2590,
                 summary: "A glowing cloud in Cygnus whose shape resembles the North American continent."),
        Landmark(id: "horsehead", name: "Horsehead Nebula", designation: "Barnard 33", type: .emissionNebula,
                 raDegrees: 85.24, decDegrees: -2.46, distanceLightYears: 1375,
                 summary: "A dark column of dust silhouetted against the glowing nebula IC 434 in Orion."),
        Landmark(id: "tarantula", name: "Tarantula Nebula", designation: "NGC 2070", type: .emissionNebula,
                 raDegrees: 84.68, decDegrees: -69.10, distanceLightYears: 160000,
                 summary: "The most active starburst region in the Local Group, sitting within the Large Magellanic Cloud."),
        Landmark(id: "m1", name: "Crab Nebula", designation: "M1", type: .supernovaRemnant,
                 raDegrees: 83.63, decDegrees: 22.01, distanceLightYears: 6500,
                 summary: "The expanding remnant of a supernova seen on Earth in 1054 AD, with a pulsar at its core."),
        Landmark(id: "veil", name: "Veil Nebula", designation: "NGC 6960", type: .supernovaRemnant,
                 raDegrees: 311.65, decDegrees: 30.72, distanceLightYears: 2400,
                 summary: "Delicate filaments of a supernova that exploded 10,000–20,000 years ago in Cygnus."),
        Landmark(id: "m57", name: "Ring Nebula", designation: "M57", type: .planetaryNebula,
                 raDegrees: 283.40, decDegrees: 33.03, distanceLightYears: 2300,
                 summary: "A dying Sun-like star that shed its outer layers into a glowing ring in Lyra."),
        Landmark(id: "helix", name: "Helix Nebula", designation: "NGC 7293", type: .planetaryNebula,
                 raDegrees: 337.41, decDegrees: -20.84, distanceLightYears: 655,
                 summary: "One of the closest planetary nebulae — the 'Eye of God' — in Aquarius."),
        Landmark(id: "m45", name: "Pleiades", designation: "M45", type: .openCluster,
                 raDegrees: 56.87, decDegrees: 24.11, distanceLightYears: 444,
                 summary: "The Seven Sisters — a brilliant young open cluster wrapped in blue reflection nebulosity."),
        Landmark(id: "hyades", name: "Hyades", designation: "Mel 25", type: .openCluster,
                 raDegrees: 66.75, decDegrees: 15.87, distanceLightYears: 153,
                 summary: "The nearest open cluster to the Sun, forming the V-shaped face of Taurus."),
        Landmark(id: "m44", name: "Beehive Cluster", designation: "M44", type: .openCluster,
                 raDegrees: 130.10, decDegrees: 19.67, distanceLightYears: 577,
                 summary: "A bright open cluster in Cancer, known to ancient observers as Praesepe."),
        Landmark(id: "double", name: "Double Cluster", designation: "NGC 869 / 884", type: .openCluster,
                 raDegrees: 34.74, decDegrees: 57.13, distanceLightYears: 7500,
                 summary: "A dazzling pair of open clusters in Perseus, both young and rich in hot stars."),
        Landmark(id: "m11", name: "Wild Duck Cluster", designation: "M11", type: .openCluster,
                 raDegrees: 282.77, decDegrees: -6.27, distanceLightYears: 6200,
                 summary: "One of the richest and most compact open clusters, in Scutum."),
        Landmark(id: "omegacen", name: "Omega Centauri", designation: "NGC 5139", type: .globularCluster,
                 raDegrees: 201.70, decDegrees: -47.48, distanceLightYears: 17000,
                 summary: "The Milky Way's largest globular cluster — millions of stars, possibly a captured dwarf galaxy's core."),
        Landmark(id: "m13", name: "Hercules Cluster", designation: "M13", type: .globularCluster,
                 raDegrees: 250.42, decDegrees: 36.46, distanceLightYears: 22200,
                 summary: "A spectacular northern globular cluster of several hundred thousand stars."),
        Landmark(id: "tuc47", name: "47 Tucanae", designation: "NGC 104", type: .globularCluster,
                 raDegrees: 6.02, decDegrees: -72.08, distanceLightYears: 13000,
                 summary: "The second-brightest globular cluster, a dense southern jewel near the SMC."),
        Landmark(id: "cygx1", name: "Cygnus X-1", designation: "Cyg X-1", type: .blackHole,
                 raDegrees: 299.59, decDegrees: 35.20, distanceLightYears: 7200,
                 summary: "A stellar-mass black hole devouring a blue supergiant — the first widely accepted black hole."),
        Landmark(id: "lmc", name: "Large Magellanic Cloud", designation: "LMC", type: .galaxy,
                 raDegrees: 80.89, decDegrees: -69.76, distanceLightYears: 163000,
                 summary: "A satellite dwarf galaxy of the Milky Way, the largest of its companions."),
        Landmark(id: "smc", name: "Small Magellanic Cloud", designation: "SMC", type: .galaxy,
                 raDegrees: 13.19, decDegrees: -72.83, distanceLightYears: 200000,
                 summary: "A smaller satellite dwarf galaxy, visible to the naked eye from the southern hemisphere."),
    ]
}
