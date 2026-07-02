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
    let radiusLightYears: Double       // physical half-extent, for true-scale rendering
    let summary: String

    var distanceParsecs: Double { distanceLightYears / 3.2616 }
    var radiusParsecs: Double { radiusLightYears / 3.2616 }

    var positionParsecs: SIMD3<Float> {
        let ra = Float(raDegrees * .pi / 180)
        let dec = Float(decDegrees * .pi / 180)
        let d = Float(distanceParsecs)
        return SIMD3(d * cos(dec) * cos(ra), d * cos(dec) * sin(ra), d * sin(dec))
    }

    /// How far back the camera should sit when flying to this landmark — framed by
    /// its physical size so the object fills a good portion of the screen.
    var suggestedViewDistance: Float {
        if id == "sgr-a" { return 6000 }   // pull back to take in the galactic core
        return max(25, Float(radiusParsecs) * 6)
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

    /// The broad bucket this type rolls up into, used to group landmarks into a
    /// handful of catalog dropdowns rather than seven thin ones.
    var group: LandmarkGroup {
        switch self {
        case .emissionNebula, .planetaryNebula, .supernovaRemnant: .nebulae
        case .openCluster, .globularCluster: .clusters
        case .blackHole: .blackHoles
        case .galaxy: .galaxies
        }
    }
}

/// A broad landmark category — the top level of the catalog's dropdown grouping.
enum LandmarkGroup: String, CaseIterable {
    case nebulae, clusters, blackHoles, galaxies

    var title: String {
        switch self {
        case .nebulae: "Nebulae"
        case .clusters: "Star Clusters"
        case .blackHoles: "Black Holes"
        case .galaxies: "Galaxies"
        }
    }

    var symbol: String {
        switch self {
        case .nebulae: "smoke.fill"
        case .clusters: "sparkles"
        case .blackHoles: "circle.circle"
        case .galaxies: "hurricane"
        }
    }

    var color: Color {
        switch self {
        case .nebulae: Color(red: 1.0, green: 0.45, blue: 0.6)
        case .clusters: Color(red: 0.72, green: 0.86, blue: 1.0)
        case .blackHoles: Color(red: 1.0, green: 0.82, blue: 0.6)
        case .galaxies: Color(white: 0.92)
        }
    }
}

enum Landmarks {
    /// Curated list of famous galactic (and a couple of satellite) landmarks.
    static let all: [Landmark] = [
        Landmark(id: "sgr-a", name: "Sagittarius A*", designation: "Sgr A*", type: .blackHole,
                 raDegrees: 266.417, decDegrees: -29.008, distanceLightYears: 26673, radiusLightYears: 3,
                 summary: "The supermassive black hole at the centre of the Milky Way, ~4.3 million times the Sun's mass."),
        Landmark(id: "m42", name: "Orion Nebula", designation: "M42", type: .emissionNebula,
                 raDegrees: 83.82, decDegrees: -5.39, distanceLightYears: 1344, radiusLightYears: 12,
                 summary: "A vast stellar nursery in Orion's Sword — the nearest large region of massive star formation."),
        Landmark(id: "m16", name: "Eagle Nebula", designation: "M16", type: .emissionNebula,
                 raDegrees: 274.70, decDegrees: -13.79, distanceLightYears: 7000, radiusLightYears: 30,
                 summary: "Home of the Pillars of Creation, towering columns of gas and dust forming new stars."),
        Landmark(id: "m8", name: "Lagoon Nebula", designation: "M8", type: .emissionNebula,
                 raDegrees: 270.92, decDegrees: -24.38, distanceLightYears: 4100, radiusLightYears: 55,
                 summary: "A bright, giant interstellar cloud in Sagittarius, faintly visible to the naked eye."),
        Landmark(id: "m20", name: "Trifid Nebula", designation: "M20", type: .emissionNebula,
                 raDegrees: 270.60, decDegrees: -22.97, distanceLightYears: 5200, radiusLightYears: 14,
                 summary: "A striking combination of emission, reflection, and dark nebulae split by dust lanes."),
        Landmark(id: "carina", name: "Carina Nebula", designation: "NGC 3372", type: .emissionNebula,
                 raDegrees: 161.27, decDegrees: -59.87, distanceLightYears: 8500, radiusLightYears: 150,
                 summary: "An enormous southern nebula housing the unstable hypergiant Eta Carinae."),
        Landmark(id: "rosette", name: "Rosette Nebula", designation: "NGC 2237", type: .emissionNebula,
                 raDegrees: 98.44, decDegrees: 4.95, distanceLightYears: 5200, radiusLightYears: 65,
                 summary: "A flower-shaped cloud in Monoceros with a young open cluster at its heart."),
        Landmark(id: "naamerica", name: "North America Nebula", designation: "NGC 7000", type: .emissionNebula,
                 raDegrees: 314.75, decDegrees: 44.52, distanceLightYears: 2590, radiusLightYears: 50,
                 summary: "A glowing cloud in Cygnus whose shape resembles the North American continent."),
        Landmark(id: "horsehead", name: "Horsehead Nebula", designation: "Barnard 33", type: .emissionNebula,
                 raDegrees: 85.24, decDegrees: -2.46, distanceLightYears: 1375, radiusLightYears: 3.5,
                 summary: "A dark column of dust silhouetted against the glowing nebula IC 434 in Orion."),
        Landmark(id: "tarantula", name: "Tarantula Nebula", designation: "NGC 2070", type: .emissionNebula,
                 raDegrees: 84.68, decDegrees: -69.10, distanceLightYears: 160000, radiusLightYears: 300,
                 summary: "The most active starburst region in the Local Group, sitting within the Large Magellanic Cloud."),
        Landmark(id: "m1", name: "Crab Nebula", designation: "M1", type: .supernovaRemnant,
                 raDegrees: 83.63, decDegrees: 22.01, distanceLightYears: 6500, radiusLightYears: 5.5,
                 summary: "The expanding remnant of a supernova seen on Earth in 1054 AD, with a pulsar at its core."),
        Landmark(id: "veil", name: "Veil Nebula", designation: "NGC 6960", type: .supernovaRemnant,
                 raDegrees: 311.65, decDegrees: 30.72, distanceLightYears: 2400, radiusLightYears: 55,
                 summary: "Delicate filaments of a supernova that exploded 10,000–20,000 years ago in Cygnus."),
        Landmark(id: "m57", name: "Ring Nebula", designation: "M57", type: .planetaryNebula,
                 raDegrees: 283.40, decDegrees: 33.03, distanceLightYears: 2300, radiusLightYears: 1.3,
                 summary: "A dying Sun-like star that shed its outer layers into a glowing ring in Lyra."),
        Landmark(id: "helix", name: "Helix Nebula", designation: "NGC 7293", type: .planetaryNebula,
                 raDegrees: 337.41, decDegrees: -20.84, distanceLightYears: 655, radiusLightYears: 2.5,
                 summary: "One of the closest planetary nebulae — the 'Eye of God' — in Aquarius."),
        Landmark(id: "m45", name: "Pleiades", designation: "M45", type: .openCluster,
                 raDegrees: 56.87, decDegrees: 24.11, distanceLightYears: 444, radiusLightYears: 14,
                 summary: "The Seven Sisters — a brilliant young open cluster wrapped in blue reflection nebulosity."),
        Landmark(id: "hyades", name: "Hyades", designation: "Mel 25", type: .openCluster,
                 raDegrees: 66.75, decDegrees: 15.87, distanceLightYears: 153, radiusLightYears: 10,
                 summary: "The nearest open cluster to the Sun, forming the V-shaped face of Taurus."),
        Landmark(id: "m44", name: "Beehive Cluster", designation: "M44", type: .openCluster,
                 raDegrees: 130.10, decDegrees: 19.67, distanceLightYears: 577, radiusLightYears: 12,
                 summary: "A bright open cluster in Cancer, known to ancient observers as Praesepe."),
        Landmark(id: "double", name: "Double Cluster", designation: "NGC 869 / 884", type: .openCluster,
                 raDegrees: 34.74, decDegrees: 57.13, distanceLightYears: 7500, radiusLightYears: 35,
                 summary: "A dazzling pair of open clusters in Perseus, both young and rich in hot stars."),
        Landmark(id: "m11", name: "Wild Duck Cluster", designation: "M11", type: .openCluster,
                 raDegrees: 282.77, decDegrees: -6.27, distanceLightYears: 6200, radiusLightYears: 14,
                 summary: "One of the richest and most compact open clusters, in Scutum."),
        Landmark(id: "omegacen", name: "Omega Centauri", designation: "NGC 5139", type: .globularCluster,
                 raDegrees: 201.70, decDegrees: -47.48, distanceLightYears: 17000, radiusLightYears: 75,
                 summary: "The Milky Way's largest globular cluster — millions of stars, possibly a captured dwarf galaxy's core."),
        Landmark(id: "m13", name: "Hercules Cluster", designation: "M13", type: .globularCluster,
                 raDegrees: 250.42, decDegrees: 36.46, distanceLightYears: 22200, radiusLightYears: 72,
                 summary: "A spectacular northern globular cluster of several hundred thousand stars."),
        Landmark(id: "tuc47", name: "47 Tucanae", designation: "NGC 104", type: .globularCluster,
                 raDegrees: 6.02, decDegrees: -72.08, distanceLightYears: 13000, radiusLightYears: 60,
                 summary: "The second-brightest globular cluster, a dense southern jewel near the SMC."),
        Landmark(id: "cygx1", name: "Cygnus X-1", designation: "Cyg X-1", type: .blackHole,
                 raDegrees: 299.59, decDegrees: 35.20, distanceLightYears: 7200, radiusLightYears: 3,
                 summary: "A stellar-mass black hole devouring a blue supergiant — the first widely accepted black hole."),
        Landmark(id: "lmc", name: "Large Magellanic Cloud", designation: "LMC", type: .galaxy,
                 raDegrees: 80.89, decDegrees: -69.76, distanceLightYears: 163000, radiusLightYears: 7000,
                 summary: "A satellite dwarf galaxy of the Milky Way, the largest of its companions."),
        Landmark(id: "smc", name: "Small Magellanic Cloud", designation: "SMC", type: .galaxy,
                 raDegrees: 13.19, decDegrees: -72.83, distanceLightYears: 200000, radiusLightYears: 3500,
                 summary: "A smaller satellite dwarf galaxy, visible to the naked eye from the southern hemisphere."),

        // ── More emission / star-forming nebulae ──────────────────────────────
        Landmark(id: "m17", name: "Omega Nebula", designation: "M17", type: .emissionNebula,
                 raDegrees: 275.10, decDegrees: -16.18, distanceLightYears: 5500, radiusLightYears: 15,
                 summary: "Also called the Swan or Horseshoe Nebula — one of the brightest star-forming regions in Sagittarius."),
        Landmark(id: "flame", name: "Flame Nebula", designation: "NGC 2024", type: .emissionNebula,
                 raDegrees: 85.43, decDegrees: -1.90, distanceLightYears: 1400, radiusLightYears: 6,
                 summary: "A glowing emission nebula beside Alnitak in Orion's Belt, threaded with dark dust lanes."),
        Landmark(id: "cone", name: "Cone Nebula", designation: "NGC 2264", type: .emissionNebula,
                 raDegrees: 100.25, decDegrees: 9.88, distanceLightYears: 2600, radiusLightYears: 20,
                 summary: "A pillar of cold gas in the Christmas Tree Cluster region of Monoceros."),
        Landmark(id: "california", name: "California Nebula", designation: "NGC 1499", type: .emissionNebula,
                 raDegrees: 60.40, decDegrees: 36.62, distanceLightYears: 1000, radiusLightYears: 50,
                 summary: "A long, faint red cloud in Perseus shaped like the US state of California."),
        Landmark(id: "bubble", name: "Bubble Nebula", designation: "NGC 7635", type: .emissionNebula,
                 raDegrees: 350.20, decDegrees: 61.20, distanceLightYears: 7100, radiusLightYears: 5,
                 summary: "A near-perfect bubble blown by the fierce stellar wind of a hot massive star in Cassiopeia."),
        Landmark(id: "pacman", name: "Pacman Nebula", designation: "NGC 281", type: .emissionNebula,
                 raDegrees: 13.00, decDegrees: 56.62, distanceLightYears: 9200, radiusLightYears: 25,
                 summary: "An emission nebula in Cassiopeia whose dark dust lanes give it a Pac-Man-like profile."),
        Landmark(id: "elephanttrunk", name: "Elephant's Trunk Nebula", designation: "IC 1396", type: .emissionNebula,
                 raDegrees: 324.70, decDegrees: 57.50, distanceLightYears: 2400, radiusLightYears: 50,
                 summary: "A sinuous column of gas and dust in Cepheus, a nursery of newborn stars."),
        Landmark(id: "crescent", name: "Crescent Nebula", designation: "NGC 6888", type: .emissionNebula,
                 raDegrees: 303.00, decDegrees: 38.35, distanceLightYears: 5000, radiusLightYears: 13,
                 summary: "A shell of gas in Cygnus cast off by a Wolf–Rayet star nearing the end of its life."),
        Landmark(id: "lobster", name: "Cat's Paw / Lobster Nebula", designation: "NGC 6357", type: .emissionNebula,
                 raDegrees: 261.50, decDegrees: -34.20, distanceLightYears: 5500, radiusLightYears: 40,
                 summary: "A vast, turbulent emission nebula in Scorpius forging some of the galaxy's most massive stars."),

        // ── More planetary nebulae ────────────────────────────────────────────
        Landmark(id: "m27", name: "Dumbbell Nebula", designation: "M27", type: .planetaryNebula,
                 raDegrees: 299.90, decDegrees: 22.72, distanceLightYears: 1360, radiusLightYears: 1.4,
                 summary: "The first planetary nebula ever discovered — a Sun-like star's glowing shed atmosphere in Vulpecula."),
        Landmark(id: "m97", name: "Owl Nebula", designation: "M97", type: .planetaryNebula,
                 raDegrees: 168.70, decDegrees: 55.02, distanceLightYears: 2030, radiusLightYears: 0.9,
                 summary: "A round planetary nebula in Ursa Major with two dark 'eyes' giving it an owlish face."),
        Landmark(id: "saturn", name: "Saturn Nebula", designation: "NGC 7009", type: .planetaryNebula,
                 raDegrees: 316.05, decDegrees: -11.36, distanceLightYears: 5000, radiusLightYears: 0.4,
                 summary: "A blue-green planetary nebula in Aquarius with handle-like jets resembling Saturn's rings."),
        Landmark(id: "bug", name: "Butterfly Nebula", designation: "NGC 6302", type: .planetaryNebula,
                 raDegrees: 258.43, decDegrees: -37.10, distanceLightYears: 3400, radiusLightYears: 1.5,
                 summary: "A bipolar planetary nebula in Scorpius with wings of gas heated past 200,000 °C."),
        Landmark(id: "eskimo", name: "Eskimo Nebula", designation: "NGC 2392", type: .planetaryNebula,
                 raDegrees: 112.30, decDegrees: 20.91, distanceLightYears: 6500, radiusLightYears: 0.5,
                 summary: "A bright double-shelled planetary nebula in Gemini, framed like a face in a fur hood."),
        Landmark(id: "southernring", name: "Southern Ring Nebula", designation: "NGC 3132", type: .planetaryNebula,
                 raDegrees: 151.76, decDegrees: -40.44, distanceLightYears: 2000, radiusLightYears: 0.4,
                 summary: "A glowing shell around a dying star in Vela, famously imaged by JWST."),
        Landmark(id: "m76", name: "Little Dumbbell Nebula", designation: "M76", type: .planetaryNebula,
                 raDegrees: 25.58, decDegrees: 51.58, distanceLightYears: 2500, radiusLightYears: 0.8,
                 summary: "A small, faint bipolar planetary nebula in Perseus."),

        // ── More supernova remnants ───────────────────────────────────────────
        Landmark(id: "vela", name: "Vela Supernova Remnant", designation: "Vela SNR", type: .supernovaRemnant,
                 raDegrees: 128.75, decDegrees: -45.17, distanceLightYears: 800, radiusLightYears: 50,
                 summary: "The nearby remnant of a star that exploded ~11,000 years ago, hosting the Vela pulsar."),
        Landmark(id: "casa", name: "Cassiopeia A", designation: "Cas A", type: .supernovaRemnant,
                 raDegrees: 350.85, decDegrees: 58.81, distanceLightYears: 11000, radiusLightYears: 5,
                 summary: "The youngest known supernova remnant in the Milky Way and the sky's brightest radio source."),
        Landmark(id: "jellyfish", name: "Jellyfish Nebula", designation: "IC 443", type: .supernovaRemnant,
                 raDegrees: 94.30, decDegrees: 22.78, distanceLightYears: 5000, radiusLightYears: 35,
                 summary: "A supernova remnant in Gemini with trailing filaments like a jellyfish's tendrils."),
        Landmark(id: "simeis147", name: "Spaghetti Nebula", designation: "Simeis 147", type: .supernovaRemnant,
                 raDegrees: 84.75, decDegrees: 27.99, distanceLightYears: 3000, radiusLightYears: 75,
                 summary: "An enormous, faint web of supernova filaments straddling Taurus and Auriga."),

        // ── More open clusters ────────────────────────────────────────────────
        Landmark(id: "m6", name: "Butterfly Cluster", designation: "M6", type: .openCluster,
                 raDegrees: 265.08, decDegrees: -32.25, distanceLightYears: 1600, radiusLightYears: 6,
                 summary: "A bright open cluster in Scorpius whose stars trace the outline of a butterfly."),
        Landmark(id: "m7", name: "Ptolemy Cluster", designation: "M7", type: .openCluster,
                 raDegrees: 268.46, decDegrees: -34.79, distanceLightYears: 980, radiusLightYears: 12,
                 summary: "A naked-eye open cluster in Scorpius recorded by Ptolemy in 130 AD."),
        Landmark(id: "m35", name: "M35", designation: "M35", type: .openCluster,
                 raDegrees: 92.27, decDegrees: 24.34, distanceLightYears: 2800, radiusLightYears: 11,
                 summary: "A large, bright open cluster at the feet of Gemini."),
        Landmark(id: "m41", name: "M41", designation: "M41", type: .openCluster,
                 raDegrees: 101.50, decDegrees: -20.76, distanceLightYears: 2300, radiusLightYears: 13,
                 summary: "An open cluster just south of Sirius in Canis Major, visible to the naked eye."),
        Landmark(id: "m37", name: "M37", designation: "M37", type: .openCluster,
                 raDegrees: 88.07, decDegrees: 32.55, distanceLightYears: 4500, radiusLightYears: 12,
                 summary: "The richest of Auriga's three fine open clusters."),
        Landmark(id: "m23", name: "M23", designation: "M23", type: .openCluster,
                 raDegrees: 269.27, decDegrees: -19.02, distanceLightYears: 2150, radiusLightYears: 8,
                 summary: "A rich, symmetric open cluster in Sagittarius."),
        Landmark(id: "ic2602", name: "Southern Pleiades", designation: "IC 2602", type: .openCluster,
                 raDegrees: 160.74, decDegrees: -64.40, distanceLightYears: 480, radiusLightYears: 6,
                 summary: "A bright, nearby open cluster in Carina, the southern echo of the Pleiades."),

        // ── More globular clusters ────────────────────────────────────────────
        Landmark(id: "m3", name: "M3", designation: "M3", type: .globularCluster,
                 raDegrees: 205.55, decDegrees: 28.38, distanceLightYears: 33900, radiusLightYears: 90,
                 summary: "A showpiece globular in Canes Venatici with half a million stars and many variables."),
        Landmark(id: "m5", name: "M5", designation: "M5", type: .globularCluster,
                 raDegrees: 229.64, decDegrees: 2.08, distanceLightYears: 24500, radiusLightYears: 80,
                 summary: "One of the oldest and largest globular clusters, in Serpens."),
        Landmark(id: "m15", name: "M15", designation: "M15", type: .globularCluster,
                 raDegrees: 322.49, decDegrees: 12.17, distanceLightYears: 33600, radiusLightYears: 88,
                 summary: "A dense globular in Pegasus with one of the most concentrated cores known."),
        Landmark(id: "m22", name: "M22", designation: "M22", type: .globularCluster,
                 raDegrees: 279.10, decDegrees: -23.90, distanceLightYears: 10600, radiusLightYears: 50,
                 summary: "A bright, nearby globular in Sagittarius — one of the first ever discovered."),
        Landmark(id: "m4", name: "M4", designation: "M4", type: .globularCluster,
                 raDegrees: 245.90, decDegrees: -26.53, distanceLightYears: 7200, radiusLightYears: 35,
                 summary: "The closest globular cluster to the Sun, just west of Antares in Scorpius."),
        Landmark(id: "m2", name: "M2", designation: "M2", type: .globularCluster,
                 raDegrees: 323.36, decDegrees: -0.82, distanceLightYears: 37500, radiusLightYears: 87,
                 summary: "A rich, ancient globular cluster in Aquarius, ~13 billion years old."),
        Landmark(id: "ngc6397", name: "NGC 6397", designation: "NGC 6397", type: .globularCluster,
                 raDegrees: 265.18, decDegrees: -53.67, distanceLightYears: 7800, radiusLightYears: 35,
                 summary: "One of the two closest globular clusters, in Ara — a 'core-collapsed' system."),

        // ── More black holes ──────────────────────────────────────────────────
        Landmark(id: "v404cyg", name: "V404 Cygni", designation: "V404 Cyg", type: .blackHole,
                 raDegrees: 306.02, decDegrees: 33.87, distanceLightYears: 7800, radiusLightYears: 2,
                 summary: "A stellar-mass black hole in Cygnus famous for dramatic X-ray outbursts as it feeds."),
        Landmark(id: "grs1915", name: "GRS 1915+105", designation: "GRS 1915+105", type: .blackHole,
                 raDegrees: 288.80, decDegrees: 10.95, distanceLightYears: 28000, radiusLightYears: 2,
                 summary: "A rapidly spinning black hole in Aquila that launches near-light-speed jets."),

        // ── Galaxies beyond the Milky Way (true positions; very distant) ───────
        Landmark(id: "m31", name: "Andromeda Galaxy", designation: "M31", type: .galaxy,
                 raDegrees: 10.68, decDegrees: 41.27, distanceLightYears: 2_537_000, radiusLightYears: 110_000,
                 summary: "The nearest large spiral galaxy and the most distant object visible to the naked eye, racing toward us."),
        Landmark(id: "m33", name: "Triangulum Galaxy", designation: "M33", type: .galaxy,
                 raDegrees: 23.46, decDegrees: 30.66, distanceLightYears: 2_730_000, radiusLightYears: 30_000,
                 summary: "The third-largest galaxy in the Local Group, a face-on spiral in Triangulum."),
        Landmark(id: "cena", name: "Centaurus A", designation: "NGC 5128", type: .galaxy,
                 raDegrees: 201.36, decDegrees: -43.02, distanceLightYears: 12_000_000, radiusLightYears: 30_000,
                 summary: "A peculiar galaxy bisected by a dark dust lane, with a supermassive black hole firing vast radio jets."),
        Landmark(id: "m81", name: "Bode's Galaxy", designation: "M81", type: .galaxy,
                 raDegrees: 148.89, decDegrees: 69.07, distanceLightYears: 11_800_000, radiusLightYears: 45_000,
                 summary: "A grand-design spiral in Ursa Major, anchor of the nearby M81 galaxy group."),
        Landmark(id: "m82", name: "Cigar Galaxy", designation: "M82", type: .galaxy,
                 raDegrees: 148.97, decDegrees: 69.68, distanceLightYears: 11_500_000, radiusLightYears: 18_000,
                 summary: "An edge-on starburst galaxy beside M81, blasting plumes of gas from its disk."),
        Landmark(id: "m51", name: "Whirlpool Galaxy", designation: "M51", type: .galaxy,
                 raDegrees: 202.47, decDegrees: 47.20, distanceLightYears: 23_000_000, radiusLightYears: 30_000,
                 summary: "A classic face-on spiral in Canes Venatici interacting with a small companion galaxy."),
        Landmark(id: "m104", name: "Sombrero Galaxy", designation: "M104", type: .galaxy,
                 raDegrees: 190.00, decDegrees: -11.62, distanceLightYears: 29_300_000, radiusLightYears: 25_000,
                 summary: "An edge-on spiral in Virgo with a bright bulge and a sharp rim of dust like a sombrero's brim."),
        Landmark(id: "m101", name: "Pinwheel Galaxy", designation: "M101", type: .galaxy,
                 raDegrees: 210.80, decDegrees: 54.35, distanceLightYears: 21_000_000, radiusLightYears: 85_000,
                 summary: "A huge, face-on spiral in Ursa Major with sprawling, asymmetric arms."),
        Landmark(id: "ngc253", name: "Sculptor Galaxy", designation: "NGC 253", type: .galaxy,
                 raDegrees: 11.89, decDegrees: -25.29, distanceLightYears: 11_400_000, radiusLightYears: 35_000,
                 summary: "A bright, dusty starburst spiral seen nearly edge-on, the largest of the Sculptor Group."),
    ]
}
