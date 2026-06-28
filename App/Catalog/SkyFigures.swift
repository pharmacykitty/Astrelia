import SwiftUI
import simd
import CelestialCore

/// The collections the viewer browses. The official IAU set is kept deliberately
/// distinct from everything else: asterisms (famous patterns that aren't official
/// constellations), historical figures (constellations later dropped), and the
/// sky as other cultures drew it.
enum FigureCatalog: String, CaseIterable, Identifiable {
    case constellations = "The 88"
    case asterisms = "Asterisms"
    case historical = "Historical"
    case cultural = "Cultural"

    var id: String { rawValue }

    /// Longer heading for the section beneath the picker.
    var heading: String {
        switch self {
        case .constellations: "The 88 Constellations"
        case .asterisms: "Asterisms"
        case .historical: "Historical Constellations"
        case .cultural: "Cultural Skies"
        }
    }

    var caption: String {
        switch self {
        case .constellations: "The official modern set, fixed by the IAU in 1922 — together they tile the entire sky."
        case .asterisms: "Beloved star patterns that aren't official constellations, drawn from the stars we catalogue."
        case .historical: "Figures charted over the centuries and later dropped from the official list."
        case .cultural: "The same stars, as other peoples have connected them."
        }
    }
}

/// A unified, browsable sky figure: a name, descriptive metadata, and the polylines
/// that draw its stick figure (each point is right-ascension°, declination°). The
/// official 88 carry a genitive and family; the others carry a group (a culture, or
/// simply their category).
struct SkyFigure: Identifiable {
    let id: String
    let name: String
    let meaning: String
    let catalog: FigureCatalog
    let group: String
    let hemisphere: SkyHemisphere?
    let genitive: String?          // IAU constellations only
    let blurb: String
    let polylines: [[SIMD2<Double>]]
}

/// A star-based figure authored independently of the d3-celestial line file: its
/// vertices are named catalogue stars (so the drawn lines snap exactly to the stars
/// we render), connected by index paths.
struct FigureSpec {
    let id: String
    let name: String
    let meaning: String
    let group: String
    let hemisphere: SkyHemisphere?
    let blurb: String
    /// Stars by token: a proper name ("Vega"), a Bayer letter + constellation
    /// ("Eta Her"), or a Flamsteed number + constellation ("39 Ari").
    let stars: [String]
    /// Polylines as ordered indices into `stars`.
    let paths: [[Int]]
}

/// Resolves a star token to a sky position against the live catalogue. Tries the
/// proper name, then the Bayer (Greek-letter) designation, then the Flamsteed
/// number — picking the brightest match so figure vertices land on the intended
/// (usually brightest) star.
struct StarResolver {
    private let byProper: [String: SIMD2<Double>]
    private let byBayer: [String: SIMD2<Double>]
    private let byFlamsteed: [String: SIMD2<Double>]

    init(_ stars: [Star]) {
        // Build into locals (keeping the brightest match per key), then publish.
        var proper: [String: (pos: SIMD2<Double>, mag: Double)] = [:]
        var bayer: [String: (pos: SIMD2<Double>, mag: Double)] = [:]
        var flam: [String: (pos: SIMD2<Double>, mag: Double)] = [:]
        func keep(_ map: inout [String: (pos: SIMD2<Double>, mag: Double)],
                  _ key: String, _ pos: SIMD2<Double>, _ mag: Double) {
            if let existing = map[key], existing.mag <= mag { return }
            map[key] = (pos, mag)
        }
        for star in stars {
            let pos = SIMD2(star.equatorial.rightAscension.degrees,
                            star.equatorial.declination.degrees)
            let mag = star.apparentMagnitude
            if let name = star.properName?.lowercased() { keep(&proper, name, pos, mag) }
            guard let con = star.constellation?.lowercased(),
                  let bf = star.bayerFlamsteed else { continue }
            let chars = Array(bf)
            var i = 0
            while i < chars.count, chars[i].isNumber { i += 1 }
            let flamsteed = String(chars[0..<i])
            var greek = ""
            for c in chars[i...] {
                if c.isLetter { greek.append(c); if greek.count == 3 { break } } else { break }
            }
            if !greek.isEmpty { keep(&bayer, greek.lowercased() + "|" + con, pos, mag) }
            if !flamsteed.isEmpty { keep(&flam, flamsteed + "|" + con, pos, mag) }
        }
        byProper = proper.mapValues(\.pos)
        byBayer = bayer.mapValues(\.pos)
        byFlamsteed = flam.mapValues(\.pos)
    }

    func position(_ token: String) -> SIMD2<Double>? {
        if let p = byProper[token.lowercased()] { return p }
        let parts = token.split(separator: " ").map(String.init)
        guard parts.count == 2 else { return nil }
        let con = parts[1].lowercased()
        if parts[0].allSatisfy(\.isNumber) { return byFlamsteed[parts[0] + "|" + con] }
        return byBayer[parts[0].lowercased() + "|" + con]
    }
}

/// Builds the full set of browsable figures: the 88 from authored metadata + the
/// bundled line geometry, plus the star-based asterism/historical/cultural figures
/// resolved against the catalogue.
enum SkyFigureLibrary {
    static func build(constellationGeometry: [String: [[SIMD2<Double>]]],
                      catalog: StarCatalog?) -> [SkyFigure] {
        var figures: [SkyFigure] = []

        for info in ConstellationCatalog.all {
            guard let polylines = constellationGeometry[info.abbr] else { continue }
            figures.append(SkyFigure(
                id: "iau." + info.abbr, name: info.name, meaning: info.meaning,
                catalog: .constellations, group: info.family, hemisphere: info.hemisphere,
                genitive: info.genitive, blurb: info.blurb, polylines: polylines))
        }

        if let catalog {
            let resolver = StarResolver(catalog.stars)
            func add(_ specs: [FigureSpec], _ catalogKind: FigureCatalog) {
                for spec in specs {
                    let positions = spec.stars.map { resolver.position($0) }
                    let lines = spec.paths.map { path -> [SIMD2<Double>] in
                        path.compactMap { idx in idx < positions.count ? positions[idx] : nil }
                            .compactMap { $0 }
                    }.filter { $0.count >= 2 }
                    guard !lines.isEmpty else { continue }
                    figures.append(SkyFigure(
                        id: catalogKind.rawValue + "." + spec.id, name: spec.name,
                        meaning: spec.meaning, catalog: catalogKind, group: spec.group,
                        hemisphere: spec.hemisphere, genitive: nil, blurb: spec.blurb,
                        polylines: lines))
                }
            }
            add(asterisms, .asterisms)
            add(historical, .historical)
            add(cultural, .cultural)
        }
        return figures
    }

    // MARK: Asterisms

    static let asterisms: [FigureSpec] = [
        .init(id: "big-dipper", name: "The Big Dipper", meaning: "The Plough · in Ursa Major",
              group: "Asterism", hemisphere: .northern,
              blurb: "The most famous star pattern in the northern sky — the bright hindquarters and tail of Ursa Major. Its two 'Pointer' stars, Dubhe and Merak, line up on Polaris.",
              stars: ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"],
              paths: [[0, 1, 2, 3, 0], [3, 4, 5, 6]]),
        .init(id: "summer-triangle", name: "The Summer Triangle", meaning: "across Lyra, Cygnus & Aquila",
              group: "Asterism", hemisphere: .northern,
              blurb: "A vast triangle overhead on summer evenings, made of three brilliant stars in three constellations: Vega, Deneb and Altair. The Milky Way runs right through it.",
              stars: ["Vega", "Deneb", "Altair"], paths: [[0, 1, 2, 0]]),
        .init(id: "winter-triangle", name: "The Winter Triangle", meaning: "across Orion, Canis Major & Minor",
              group: "Asterism", hemisphere: .equatorial,
              blurb: "The counterpart to the Summer Triangle: Betelgeuse, Sirius and Procyon, three of winter's brightest stars forming a near-perfect equilateral triangle.",
              stars: ["Betelgeuse", "Sirius", "Procyon"], paths: [[0, 1, 2, 0]]),
        .init(id: "winter-hexagon", name: "The Winter Hexagon", meaning: "the great ring of winter",
              group: "Asterism", hemisphere: .equatorial,
              blurb: "An enormous hexagon strung from six of the brightest winter stars — Rigel, Aldebaran, Capella, Pollux, Procyon and Sirius — circling Betelgeuse at its centre.",
              stars: ["Rigel", "Aldebaran", "Capella", "Pollux", "Procyon", "Sirius"],
              paths: [[0, 1, 2, 3, 4, 5, 0]]),
        .init(id: "great-square", name: "The Great Square of Pegasus", meaning: "the body of the winged horse",
              group: "Asterism", hemisphere: .northern,
              blurb: "A huge, near-perfect rectangle marking the body of Pegasus — a signpost of the autumn sky. One corner, Alpheratz, actually belongs to neighbouring Andromeda.",
              stars: ["Alpheratz", "Scheat", "Markab", "Algenib"], paths: [[0, 1, 2, 3, 0]]),
        .init(id: "northern-cross", name: "The Northern Cross", meaning: "the body of Cygnus the Swan",
              group: "Asterism", hemisphere: .northern,
              blurb: "Cygnus the Swan flying down the Milky Way reads equally well as an upright cross: Deneb at the top, Albireo at the foot, with the wings as the crossbar.",
              stars: ["Deneb", "Sadr", "Albireo", "Aljanah", "Fawaris"],
              paths: [[0, 1, 2], [3, 1, 4]]),
        .init(id: "teapot", name: "The Teapot", meaning: "the heart of Sagittarius",
              group: "Asterism", hemisphere: .southern,
              blurb: "The brightest stars of Sagittarius pour out a perfect teapot. Steam from its spout is the Milky Way's brightest cloud — and the direction of the galaxy's centre.",
              stars: ["Alnasl", "Kaus Media", "Kaus Australis", "Kaus Borealis", "Phi Sgr", "Nunki", "Tau Sgr", "Ascella"],
              paths: [[0, 1, 2, 7], [1, 3, 4, 5, 6, 7]]),
        .init(id: "sickle", name: "The Sickle of Leo", meaning: "the lion's head & mane",
              group: "Asterism", hemisphere: .northern,
              blurb: "A backwards question mark of six stars forming the head and mane of Leo, with bright Regulus as the dot at its base.",
              stars: ["Regulus", "Eta Leo", "Algieba", "Adhafera", "Ras Elased Australis", "Mu Leo"],
              paths: [[0, 1, 2, 3, 4, 5]]),
        .init(id: "keystone", name: "The Keystone", meaning: "the torso of Hercules",
              group: "Asterism", hemisphere: .northern,
              blurb: "A lopsided square forming the body of kneeling Hercules. Along its western edge sits M13, the brightest globular cluster of the northern sky.",
              stars: ["Eta Her", "Zet Her", "Eps Her", "Pi Her"], paths: [[0, 1, 2, 3, 0]]),
        .init(id: "orions-belt", name: "Orion's Belt", meaning: "the three kings",
              group: "Asterism", hemisphere: .equatorial,
              blurb: "Three bright stars in a near-perfect line — Alnitak, Alnilam and Mintaka. Extend the line down-left to Sirius, up-right to Aldebaran.",
              stars: ["Alnitak", "Alnilam", "Mintaka"], paths: [[0, 1, 2]]),
        .init(id: "false-cross", name: "The False Cross", meaning: "across Carina & Vela",
              group: "Asterism", hemisphere: .southern,
              blurb: "A cross of four stars in Carina and Vela, often mistaken for the true Southern Cross — it's larger, dimmer, and lacks the Cross's two pointer stars.",
              stars: ["Avior", "Aspidiske", "Alsephina", "Markeb"], paths: [[0, 2], [1, 3]]),
        .init(id: "pointers", name: "The Southern Pointers", meaning: "Alpha & Beta Centauri",
              group: "Asterism", hemisphere: .southern,
              blurb: "Two brilliant stars — Rigil Kentaurus (the nearest star system to the Sun) and Hadar — that point the way to the Southern Cross and help tell the true Cross from the False.",
              stars: ["Rigil Kentaurus", "Hadar"], paths: [[0, 1]]),
        .init(id: "circlet", name: "The Circlet of Pisces", meaning: "the head of the western fish",
              group: "Asterism", hemisphere: .northern,
              blurb: "A delicate ring of faint stars marking the head of one of the two fishes of Pisces, just south of the Great Square.",
              stars: ["Gam Psc", "The Psc", "Iot Psc", "Lam Psc", "Kap Psc"],
              paths: [[0, 1, 2, 3, 4, 0]]),
        .init(id: "pleiades", name: "The Pleiades", meaning: "the Seven Sisters · in Taurus",
              group: "Asterism", hemisphere: .northern,
              blurb: "A tiny, glittering dipper of stars — the closest bright star cluster to Earth. Most people see six or seven; keen eyes and binoculars reveal dozens.",
              stars: ["Alcyone", "Atlas", "Electra", "Maia", "Merope", "Taygeta", "Pleione"],
              paths: [[4, 0, 3, 5, 2, 4], [0, 1, 6]]),
        .init(id: "hyades", name: "The Hyades", meaning: "the face of Taurus the Bull",
              group: "Asterism", hemisphere: .northern,
              blurb: "A V-shaped cluster forming the bull's face, with fiery Aldebaran at one tip (though Aldebaran itself lies far closer than the true cluster behind it).",
              stars: ["Aldebaran", "Gam Tau", "Del Tau", "Eps Tau", "The Tau"],
              paths: [[0, 4, 1], [3, 2, 1]]),
        .init(id: "lozenge", name: "The Lozenge", meaning: "the head of Draco",
              group: "Asterism", hemisphere: .northern,
              blurb: "A small, neat quadrilateral marking the dragon's head, led by Eltanin. It swings high overhead near the zenith for northern observers.",
              stars: ["Eltanin", "Rastaban", "Grumium", "Nu Dra"], paths: [[0, 1, 3, 2, 0]]),
        .init(id: "coffin", name: "Job's Coffin", meaning: "the body of Delphinus",
              group: "Asterism", hemisphere: .northern,
              blurb: "A compact diamond of four stars making the little dolphin's body. Two of its stars hide a backwards joke: Sualocin and Rotanev spell an astronomer's name in reverse.",
              stars: ["Sualocin", "Rotanev", "Gam Del", "Del Del"], paths: [[0, 1, 3, 2, 0]]),
        .init(id: "kids", name: "The Kids", meaning: "the goat-kids of Auriga",
              group: "Asterism", hemisphere: .northern,
              blurb: "A slim triangle of stars beside brilliant Capella — the goat — representing the kid goats she carries on her shoulder.",
              stars: ["Almaaz", "Zet Aur", "Eta Aur"], paths: [[0, 1, 2, 0]]),
        .init(id: "little-dipper", name: "The Little Dipper", meaning: "the body of Ursa Minor",
              group: "Asterism", hemisphere: .northern,
              blurb: "A faint dipper with Polaris, the North Star, at the tip of its handle. Its two bowl stars, Kochab and Pherkad, are the 'Guardians of the Pole.'",
              stars: ["Polaris", "Yildun", "Eps UMi", "Zet UMi", "Kochab", "Pherkad"],
              paths: [[0, 1, 2, 3, 4, 5, 2]]),
        .init(id: "diamond-of-virgo", name: "The Diamond of Virgo", meaning: "the Great Diamond of spring",
              group: "Asterism", hemisphere: .northern,
              blurb: "A vast diamond of four bright stars across four constellations — Arcturus, Spica, Denebola and Cor Caroli — dominating the spring sky.",
              stars: ["Arcturus", "Spica", "Denebola", "Cor Caroli"], paths: [[0, 1, 2, 3, 0]]),
        .init(id: "spring-triangle", name: "The Spring Triangle", meaning: "across Boötes, Virgo & Leo",
              group: "Asterism", hemisphere: .equatorial,
              blurb: "Spring's answer to the Summer and Winter Triangles: golden Arcturus, blue-white Spica and Regulus, the three brightest stars of the season.",
              stars: ["Arcturus", "Spica", "Regulus"], paths: [[0, 1, 2, 0]]),
        .init(id: "kite", name: "The Kite", meaning: "the body of Boötes",
              group: "Asterism", hemisphere: .northern,
              blurb: "Boötes the herdsman reads as a kite or ice-cream cone, with brilliant Arcturus at the point where the tail would tie on.",
              stars: ["Arcturus", "Izar", "Del Boo", "Nekkar", "Seginus", "Rho Boo"],
              paths: [[0, 5, 4, 3, 2, 1, 0]]),
        .init(id: "water-jar", name: "The Water Jar", meaning: "the urn of Aquarius",
              group: "Asterism", hemisphere: .equatorial,
              blurb: "A small Y of four stars marking the water jar held by Aquarius, from which his stream of water pours toward the southern fish.",
              stars: ["Sadachbia", "Zet Aqr", "Eta Aqr", "Pi Aqr"],
              paths: [[1, 0], [1, 2], [1, 3]]),
        .init(id: "cassiopeia-w", name: "The Celestial W", meaning: "the throne of Cassiopeia",
              group: "Asterism", hemisphere: .northern,
              blurb: "Five bright stars zigzag into a 'W' (or, half a year later, an 'M') — one of the easiest patterns to find, riding opposite the Big Dipper around the pole.",
              stars: ["Caph", "Schedar", "Gam Cas", "Ruchbah", "Segin"],
              paths: [[0, 1, 2, 3, 4]]),
        .init(id: "diamond-cross", name: "The Diamond Cross", meaning: "in Carina",
              group: "Asterism", hemisphere: .southern,
              blurb: "A diamond of stars in Carina, the third of the southern sky's three cross shapes alongside the true Southern Cross and the False Cross.",
              stars: ["Miaplacidus", "The Car", "Ups Car", "Ome Car"], paths: [[0, 1, 3, 2, 0]]),
        .init(id: "hydra-head", name: "The Head of Hydra", meaning: "the water snake's head",
              group: "Asterism", hemisphere: .equatorial,
              blurb: "A neat little loop of six stars forming the head of Hydra, the largest constellation — the only part of the great snake that catches the eye.",
              stars: ["Zet Hya", "Eta Hya", "Rho Hya", "Sig Hya", "Del Hya", "Eps Hya"],
              paths: [[0, 1, 2, 3, 4, 5, 0]]),
        .init(id: "saucepan", name: "The Saucepan", meaning: "Orion's belt & sword",
              group: "Asterism", hemisphere: .equatorial,
              blurb: "The Australian name for Orion's belt and sword: the three Belt stars form the pan, and the sword hanging below becomes its handle.",
              stars: ["Alnitak", "Alnilam", "Mintaka", "Hatysa", "42 Ori"],
              paths: [[0, 1, 2], [1, 3, 4]]),
        .init(id: "sword-of-orion", name: "The Sword of Orion", meaning: "hanging from the Belt",
              group: "Asterism", hemisphere: .equatorial,
              blurb: "The short line of stars below Orion's Belt. Its middle 'star' is no star at all but the Orion Nebula — a glowing stellar nursery visible to the naked eye.",
              stars: ["Hatysa", "The Ori", "42 Ori"], paths: [[0, 1, 2]]),
        .init(id: "milk-dipper", name: "The Milk Dipper", meaning: "in Sagittarius",
              group: "Asterism", hemisphere: .southern,
              blurb: "A second, smaller dipper sharing stars with the Teapot's handle and lid — its bowl dips into the brightest clouds of the Milky Way, as if scooping up the 'milk' itself.",
              stars: ["Kaus Borealis", "Phi Sgr", "Nunki", "Tau Sgr", "Ascella"],
              paths: [[0, 1, 2, 3, 4, 1]]),
        .init(id: "head-of-cetus", name: "The Head of Cetus", meaning: "the sea monster's head",
              group: "Asterism", hemisphere: .equatorial,
              blurb: "A loose pentagon of stars led by Menkar marking the head of Cetus, the great sea monster — the only readily traced part of this sprawling, faint constellation.",
              stars: ["Menkar", "Gam Cet", "Del Cet", "Lam Cet", "Mu Cet"],
              paths: [[0, 3, 4, 1, 2, 0]]),
        .init(id: "segment-of-perseus", name: "The Segment of Perseus", meaning: "the hero's curve",
              group: "Asterism", hemisphere: .northern,
              blurb: "A graceful arc of stars sweeping out from brilliant Mirfak — the body of Perseus, set in a rich field of the Milky Way thick with star clusters.",
              stars: ["Mirfak", "Gam Per", "Del Per", "Eps Per", "Zet Per"],
              paths: [[1, 0, 2, 3, 4]]),
        .init(id: "coathanger", name: "The Coathanger", meaning: "Brocchi's Cluster · in Vulpecula",
              group: "Asterism", hemisphere: .northern,
              blurb: "A perfect upside-down coathanger — a straight bar of six stars with a hook below — hiding in the Milky Way between Cygnus and Aquila. A lovely binocular sight.",
              stars: ["5 Vul", "6 Vul", "7 Vul", "4 Vul"], paths: [[0, 1, 2], [1, 3]]),
    ]

    // MARK: Historical (former constellations)

    static let historical: [FigureSpec] = [
        .init(id: "argo-navis", name: "Argo Navis", meaning: "the ship of the Argonauts",
              group: "Former constellation", hemisphere: .southern,
              blurb: "Once the largest constellation of all — the great ship that carried Jason and the Argonauts. In 1763 it was broken up into Carina (the keel), Puppis (the stern) and Vela (the sails), which we still use today.",
              stars: ["Canopus", "Miaplacidus", "Avior", "Aspidiske", "Naos", "Suhail", "Alsephina", "Markeb", "Tureis"],
              paths: [[4, 5, 7, 6, 3, 2, 0], [2, 1]]),
        .init(id: "quadrans", name: "Quadrans Muralis", meaning: "the mural quadrant",
              group: "Former constellation", hemisphere: .northern,
              blurb: "An astronomer's wall-mounted quadrant, placed between Boötes and Draco in 1795 and dropped when the IAU fixed the 88. Its name survives in the Quadrantid meteor shower that still radiates from this spot each January.",
              stars: ["Nekkar", "The Boo", "Iot Dra", "Eta Dra"], paths: [[0, 1, 2, 3, 0]]),
        .init(id: "antinous", name: "Antinous", meaning: "the youth borne by the eagle",
              group: "Former constellation", hemisphere: .equatorial,
              blurb: "A favourite of the Emperor Hadrian, set among the lower stars of Aquila and carried by the eagle. Charted for centuries before being folded back into Aquila.",
              stars: ["Altair", "Eta Aql", "The Aql", "Del Aql", "Lam Aql", "Iot Aql"],
              paths: [[0, 3, 2, 1], [3, 4, 5]]),
        .init(id: "musca-borealis", name: "Musca Borealis", meaning: "the northern fly",
              group: "Former constellation", hemisphere: .northern,
              blurb: "A small northern fly made from a few faint stars on the back of Aries. With a southern fly also in the sky, only Musca (the southern one) survived the cull.",
              stars: ["Bharani", "39 Ari", "35 Ari", "33 Ari"], paths: [[3, 2, 1, 0]]),
        .init(id: "taurus-poniatovii", name: "Taurus Poniatovii", meaning: "Poniatowski's Bull",
              group: "Former constellation", hemisphere: .equatorial,
              blurb: "A bull honouring a Polish king, charted in 1777 in eastern Ophiuchus. Its stars form a little V echoing the Hyades — but it was dropped when the modern borders were drawn.",
              stars: ["66 Oph", "67 Oph", "68 Oph", "70 Oph", "72 Oph", "73 Oph"],
              paths: [[5, 4, 3, 2], [3, 1, 0]]),
        .init(id: "globus-aerostaticus", name: "Globus Aerostaticus", meaning: "the hot-air balloon",
              group: "Former constellation", hemisphere: .southern,
              blurb: "A hot-air balloon celebrating the Montgolfier brothers' 1783 flight, floated into the sky by Lalande near Microscopium. It drifted off the official charts a century later.",
              stars: ["Eps Mic", "Gam Mic", "The PsA", "Iot PsA"], paths: [[0, 1, 2, 3, 0]]),
        .init(id: "frederici-honores", name: "Frederici Honores", meaning: "the Glory of Frederick",
              group: "Former constellation", hemisphere: .northern,
              blurb: "A wreath and regalia honouring King Frederick the Great of Prussia, placed among the stars of Andromeda by Johann Bode in 1787 and later quietly retired.",
              stars: ["Omi And", "Phi And", "Psi And", "51 And"], paths: [[0, 1, 2, 3]]),
        .init(id: "cerberus", name: "Cerberus", meaning: "the three-headed serpent",
              group: "Former constellation", hemisphere: .northern,
              blurb: "A writhing serpent (sometimes the three-headed hound of Hades) gripped in the hand of Hercules, charted by Hevelius from a line of stars beside Rasalgethi and later dropped.",
              stars: ["Rasalgethi", "95 Her", "102 Her", "109 Her"], paths: [[0, 1, 2, 3]]),
        .init(id: "triangulum-minus", name: "Triangulum Minus", meaning: "the smaller triangle",
              group: "Former constellation", hemisphere: .northern,
              blurb: "A little triangle Hevelius set just below Triangulum, doubling the triangles in that patch of sky. The IAU kept only the larger one.",
              stars: ["6 Tri", "10 Tri", "12 Tri"], paths: [[0, 1, 2, 0]]),
        .init(id: "sceptrum", name: "Sceptrum Brandenburgicum", meaning: "the Sceptre of Brandenburg",
              group: "Former constellation", hemisphere: .equatorial,
              blurb: "A royal sceptre honouring the Brandenburg dynasty, drawn in Eridanus by Gottfried Kirch in 1688. A slender line of faint stars, long since absorbed back into the river.",
              stars: ["53 Eri", "54 Eri", "51 Eri"], paths: [[2, 0, 1]]),
        .init(id: "mons-maenalus", name: "Mons Maenalus", meaning: "Mount Maenalus",
              group: "Former constellation", hemisphere: .northern,
              blurb: "A mountain — sacred to the god Pan — placed beneath the feet of Boötes by Hevelius, so the herdsman could stand upon it. It was left off the modern list.",
              stars: ["31 Boo", "Tau Boo", "Ups Boo"], paths: [[0, 1, 2]]),
    ]

    // MARK: Cultural skies

    /// Display order for the cultural dropdowns — roughly chronological by tradition,
    /// so related skies sit together.
    static let cultureOrder = [
        "Babylonian", "Egyptian", "Chinese", "Hindu", "Arabic",
        "Norse", "Aztec", "Polynesian", "Māori", "Inuit",
    ]

    static let cultural: [FigureSpec] = [
        // Chinese
        .init(id: "beidou", name: "The Northern Dipper", meaning: "Běidǒu 北斗",
              group: "Chinese", hemisphere: .northern,
              blurb: "In Chinese astronomy the seven stars of the Big Dipper are Běidǒu, a celestial ladle at the heart of the sky. Its rotating handle was read as the hand of a cosmic clock, marking the seasons.",
              stars: ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"],
              paths: [[0, 1, 2, 3, 4, 5, 6]]),
        .init(id: "cowherd-weaver", name: "The Cowherd & the Weaver", meaning: "Niúláng Zhīnǚ 牛郎織女",
              group: "Chinese", hemisphere: .northern,
              blurb: "Altair is the cowherd Niúláng (flanked by his two children) and Vega the weaver-girl Zhīnǚ, lovers parted by the river of the Milky Way — reunited just once a year, the legend behind the Qixi festival.",
              stars: ["Altair", "Tarazed", "Alshain", "Vega"], paths: [[1, 0, 2], [0, 3]]),
        .init(id: "shen", name: "Shēn", meaning: "參 · the hunter",
              group: "Chinese", hemisphere: .equatorial,
              blurb: "The stars of Orion form Shēn, one of the 28 lunar mansions of Chinese astronomy. Its three belt stars give the mansion its name — 'three' — and were among the most carefully watched markers of the night.",
              stars: ["Betelgeuse", "Bellatrix", "Alnitak", "Alnilam", "Mintaka", "Saiph", "Rigel"],
              paths: [[0, 1], [2, 3, 4], [0, 2], [1, 4], [2, 5], [4, 6]]),

        // Hindu
        .init(id: "saptarishi", name: "Saptarishi", meaning: "सप्तर्षि · the Seven Sages",
              group: "Hindu", hemisphere: .northern,
              blurb: "In Vedic tradition the seven stars of the Big Dipper are the Saptarishi, the seven great sages who attend the pole star Dhruva. Each bowl and handle star carries a sage's name.",
              stars: ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"],
              paths: [[0, 1, 2, 3, 4, 5, 6]]),
        .init(id: "krittika", name: "Kṛttikā", meaning: "कृत्तिका · the Pleiades",
              group: "Hindu", hemisphere: .northern,
              blurb: "The Pleiades are Kṛttikā, the first of the 27 nakshatras (lunar mansions) of Hindu astronomy — the foster-mothers of the war-god Kartikeya, who takes his name from them.",
              stars: ["Alcyone", "Atlas", "Electra", "Maia", "Merope", "Taygeta", "Pleione"],
              paths: [[4, 0, 3, 5, 2, 4], [0, 1, 6]]),
        .init(id: "mrigashira", name: "Mṛgaśīrṣa", meaning: "मृगशीर्ष · the deer's head",
              group: "Hindu", hemisphere: .equatorial,
              blurb: "The faint trio at Orion's head is Mṛgaśīrṣa, the 'deer's head' nakshatra — the celestial antelope pursued across the sky by the hunter.",
              stars: ["Meissa", "Phi Ori", "Bellatrix"], paths: [[1, 0, 2]]),

        // Arabic
        .init(id: "banat-nash", name: "Banāt al-Naʿsh", meaning: "بنات نعش · the daughters of the bier",
              group: "Arabic", hemisphere: .northern,
              blurb: "To early Arab skywatchers the Big Dipper's bowl was a funeral bier (Naʿsh) and its three handle stars the mourning daughters following behind — the source of star names like Mizar and Alkaid.",
              stars: ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"],
              paths: [[0, 1, 2, 3, 0], [3, 4, 5, 6]]),
        .init(id: "al-naaim", name: "Al-Naʿāʾim", meaning: "النعائم · the ostriches",
              group: "Arabic", hemisphere: .southern,
              blurb: "The bright stars of Sagittarius — our Teapot — were seen by the Arabs as ostriches gathered to drink at the river of the Milky Way, then returning across it.",
              stars: ["Alnasl", "Kaus Media", "Kaus Australis", "Kaus Borealis", "Phi Sgr", "Nunki", "Tau Sgr", "Ascella"],
              paths: [[0, 1, 2, 7], [1, 3, 4, 5, 6, 7]]),

        // Egyptian
        .init(id: "sah", name: "Sah", meaning: "Osiris, the hunter",
              group: "Egyptian", hemisphere: .equatorial,
              blurb: "To the ancient Egyptians the stars of Orion were Sah, the celestial form of the god Osiris, striding beside his consort Isis (the star Sirius) along the Milky Way.",
              stars: ["Betelgeuse", "Bellatrix", "Alnitak", "Alnilam", "Mintaka", "Saiph", "Rigel"],
              paths: [[0, 1], [2, 3, 4], [0, 2], [1, 4], [2, 5], [4, 6]]),
        .init(id: "meskhetiu", name: "Meskhetiu", meaning: "the bull's foreleg",
              group: "Egyptian", hemisphere: .northern,
              blurb: "The Big Dipper was Meskhetiu, the foreleg of a great bull (and the shape of the adze used in the 'Opening of the Mouth' funeral rite). Never setting, it marked the imperishable northern sky.",
              stars: ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"],
              paths: [[0, 1, 2, 3, 0], [3, 4, 5, 6]]),

        // Norse
        .init(id: "friggs-distaff", name: "Frigg's Distaff", meaning: "Friggerock · the spindle",
              group: "Norse", hemisphere: .equatorial,
              blurb: "In Norse skylore the three stars of Orion's Belt are the distaff (spinning staff) of the goddess Frigg — also called Frigg's spindle or, later, Mary's distaff.",
              stars: ["Alnitak", "Alnilam", "Mintaka"], paths: [[0, 1, 2]]),
        .init(id: "great-wagon", name: "The Great Wagon", meaning: "Stóri Vagn",
              group: "Norse", hemisphere: .northern,
              blurb: "Across the Norse and Germanic world the Big Dipper rolled through the sky as a great wagon — the bowl its cart, the handle its drawn pole — circling the pole star through the long northern night.",
              stars: ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"],
              paths: [[0, 1, 2, 3, 0], [3, 4, 5, 6]]),

        // Polynesian
        .init(id: "maui-hook", name: "Māui's Fishhook", meaning: "Manaiakalani",
              group: "Polynesian", hemisphere: .southern,
              blurb: "Across Polynesia the curving tail of Scorpius is the magical fishhook with which the demigod Māui hauled up the islands from the sea. In Hawai‘i it is Manaiakalani, the chief's fishhook.",
              stars: ["Antares", "Eps Sco", "Mu Sco", "Zet Sco", "Eta Sco", "The Sco", "Iot Sco", "Kap Sco", "Ups Sco", "Lam Sco"],
              paths: [[0, 1, 2, 3, 4, 5, 6, 7, 9, 8]]),
        .init(id: "manu", name: "Manu", meaning: "the great bird",
              group: "Polynesian", hemisphere: .equatorial,
              blurb: "Many Polynesian navigators saw a vast bird spanning the sky: Sirius as its body, with Canopus and Procyon as the tips of its outstretched wings — a star compass for wayfinding across the Pacific.",
              stars: ["Sirius", "Canopus", "Procyon"], paths: [[1, 0, 2]]),

        // Māori
        .init(id: "matariki", name: "Matariki", meaning: "the Pleiades",
              group: "Māori", hemisphere: .northern,
              blurb: "To Māori, the dawn rising of the Pleiades cluster marks Matariki — the New Year, a time of remembrance and renewal. Its stars are gathered as a whānau (family) watching over the year ahead.",
              stars: ["Alcyone", "Atlas", "Electra", "Maia", "Merope", "Taygeta", "Pleione"],
              paths: [[4, 0, 3, 5, 2, 4], [0, 1, 6]]),
        .init(id: "te-punga", name: "Te Punga", meaning: "the Anchor · the Southern Cross",
              group: "Māori", hemisphere: .southern,
              blurb: "The Southern Cross is Te Punga, the anchor of the great sky-canoe of Tama-rereti, holding it steady against the south celestial pole as the heavens turn.",
              stars: ["Acrux", "Mimosa", "Gacrux", "Imai"], paths: [[2, 3, 0], [1, 3]]),
        .init(id: "tautoru", name: "Tautoru", meaning: "Orion's Belt",
              group: "Māori", hemisphere: .equatorial,
              blurb: "Orion's Belt is Tautoru, 'the row of three' — a marker of the seasons whose rising and setting helped guide planting and the navigators of the Pacific.",
              stars: ["Alnitak", "Alnilam", "Mintaka"], paths: [[0, 1, 2]]),

        // Inuit
        .init(id: "tukturjuit", name: "Tukturjuit", meaning: "the caribou",
              group: "Inuit", hemisphere: .northern,
              blurb: "In Inuit skylore the Big Dipper is Tukturjuit, a caribou wheeling around the pole. Its slow turn through the long Arctic night helped mark the passing hours.",
              stars: ["Dubhe", "Merak", "Phecda", "Megrez", "Alioth", "Mizar", "Alkaid"],
              paths: [[0, 1, 2, 3, 0], [3, 4, 5, 6]]),
        .init(id: "aagjuuk", name: "Aagjuuk", meaning: "the dawn pair",
              group: "Inuit", hemisphere: .equatorial,
              blurb: "Altair and its bright neighbour Tarazed are Aagjuuk, two stars whose pre-dawn return in midwinter announced the coming of the new year and the sun's return to the Arctic.",
              stars: ["Altair", "Tarazed"], paths: [[0, 1]]),
        .init(id: "ullaktut", name: "Ullaktut", meaning: "the runners",
              group: "Inuit", hemisphere: .equatorial,
              blurb: "Orion's Belt is Ullaktut, three hunters lost on the ice while chasing a bear — placed in the sky together, forever running across the winter night.",
              stars: ["Alnitak", "Alnilam", "Mintaka"], paths: [[0, 1, 2]]),

        // Babylonian
        .init(id: "bull-of-heaven", name: "The Bull of Heaven", meaning: "GU.AN.NA · Taurus",
              group: "Babylonian", hemisphere: .northern,
              blurb: "Four thousand years ago the Babylonians drew the Bull of Heaven across what we still call Taurus — the beast Gilgamesh slays in his epic. Many of our constellations trace back to their sky.",
              stars: ["Aldebaran", "Gam Tau", "Del Tau", "Eps Tau", "Elnath", "Zet Tau"],
              paths: [[3, 2, 1, 0], [0, 5], [3, 4]]),
        .init(id: "shepherd-of-anu", name: "The True Shepherd of Anu", meaning: "SIPA.ZI.AN.NA · Orion",
              group: "Babylonian", hemisphere: .equatorial,
              blurb: "The stars of Orion were the True Shepherd of Anu — Papsukkal, messenger of the gods — striding the sky long before the Greeks renamed him the Hunter.",
              stars: ["Betelgeuse", "Bellatrix", "Alnitak", "Alnilam", "Mintaka", "Saiph", "Rigel"],
              paths: [[0, 1], [2, 3, 4], [0, 2], [1, 4], [2, 5], [4, 6]]),
        .init(id: "great-twins", name: "The Great Twins", meaning: "MAŠ.TAB.BA.GAL.GAL · Gemini",
              group: "Babylonian", hemisphere: .northern,
              blurb: "Castor and Pollux were the Great Twins, the gods Lugal-irra and Meslamta-ea — guardians of the gateway to the underworld, standing side by side at the edge of the Milky Way.",
              stars: ["Castor", "Pollux", "Eps Gem", "Mu Gem", "Alhena", "Xi Gem"],
              paths: [[0, 2, 3], [1, 4, 5]]),
        .init(id: "the-furrow", name: "The Furrow", meaning: "AB.SÍN · Virgo",
              group: "Babylonian", hemisphere: .equatorial,
              blurb: "Virgo was the Furrow, the goddess Shala holding an ear of grain — the star we still call Spica, 'the ear of wheat.' A sign that the harvest season was near.",
              stars: ["Spica", "Gam Vir", "Eps Vir", "Zet Vir"], paths: [[0, 3, 1, 2]]),

        // Aztec
        .init(id: "tianquiztli", name: "Tianquiztli", meaning: "the marketplace · the Pleiades",
              group: "Aztec", hemisphere: .northern,
              blurb: "To the Aztecs the Pleiades were Tianquiztli, 'the marketplace' — a crowd of people gathered together. Their midnight passage overhead set the timing of the New Fire ceremony every 52 years.",
              stars: ["Alcyone", "Atlas", "Electra", "Maia", "Merope", "Taygeta", "Pleione"],
              paths: [[4, 0, 3, 5, 2, 4], [0, 1, 6]]),
        .init(id: "mamalhuaztli", name: "Mamalhuaztli", meaning: "the fire drill · Orion's Belt",
              group: "Aztec", hemisphere: .equatorial,
              blurb: "Orion's Belt was Mamalhuaztli, the fire-drill sticks used to kindle the sacred New Fire — the three stars from which the renewing flame of each new age was struck.",
              stars: ["Alnitak", "Alnilam", "Mintaka"], paths: [[0, 1, 2]]),

        // Chinese (additional)
        .init(id: "nan-dou", name: "The Southern Dipper", meaning: "Nán Dǒu 南斗",
              group: "Chinese", hemisphere: .southern,
              blurb: "The Milk Dipper in Sagittarius is Nán Dǒu, the Southern Dipper — counterpart to the northern Běidǒu. Where the northern dipper governed death, the southern was said to record the span of life.",
              stars: ["Kaus Borealis", "Phi Sgr", "Nunki", "Tau Sgr", "Ascella"],
              paths: [[0, 1, 2, 3, 4, 1]]),
        .init(id: "xin", name: "Xīn", meaning: "心 · the Heart",
              group: "Chinese", hemisphere: .southern,
              blurb: "The red heart of Scorpius — Antares, flanked by σ and τ Scorpii — was Xīn, the Heart mansion, associated with the emperor himself. A 'fire star' watched with care for omens.",
              stars: ["Antares", "Sig Sco", "Tau Sco"], paths: [[1, 0, 2]]),

        // Hindu (additional)
        .init(id: "rohini", name: "Rohiṇī", meaning: "रोहिणी · Aldebaran & the Hyades",
              group: "Hindu", hemisphere: .northern,
              blurb: "The V of the Hyades, crowned by red Aldebaran, is Rohiṇī — the favourite of the moon-god Chandra among all the nakshatras, and one of the most auspicious mansions of the sky.",
              stars: ["Aldebaran", "Gam Tau", "Del Tau", "Eps Tau", "The Tau"],
              paths: [[0, 4, 1], [3, 2, 1]]),
        .init(id: "magha", name: "Maghā", meaning: "मघा · the Sickle of Leo",
              group: "Hindu", hemisphere: .northern,
              blurb: "The Sickle of Leo, with Regulus at its base, is Maghā — 'the mighty,' the nakshatra of thrones and ancestors, with Regulus marking the seat of kings.",
              stars: ["Regulus", "Eta Leo", "Algieba", "Adhafera", "Ras Elased Australis", "Mu Leo"],
              paths: [[0, 1, 2, 3, 4, 5]]),

        // Arabic (additional)
        .init(id: "al-thurayya", name: "Al-Thurayyā", meaning: "الثريا · the Pleiades",
              group: "Arabic", hemisphere: .northern,
              blurb: "The Pleiades are Al-Thurayyā, 'the abundant ones' — among the most cherished stars of Arabic poetry and the source, through Arabic astronomy, of the cluster's lasting fame.",
              stars: ["Alcyone", "Atlas", "Electra", "Maia", "Merope", "Taygeta", "Pleione"],
              paths: [[4, 0, 3, 5, 2, 4], [0, 1, 6]]),
        .init(id: "gazelle-leaps", name: "The Leaps of the Gazelle", meaning: "Qafzat al-Ẓaby",
              group: "Arabic", hemisphere: .northern,
              blurb: "Three pairs of stars along the feet of Ursa Major were the hoofprints where a gazelle, startled from a pond, bounded across the sky in three great leaps — preserved in star names like Talitha and Tania.",
              stars: ["Talitha", "Kap UMa", "Tania Borealis", "Tania Australis", "Alula Borealis", "Alula Australis"],
              paths: [[0, 1], [2, 3], [4, 5]]),

        // Egyptian (additional)
        .init(id: "taweret", name: "Taweret", meaning: "the hippopotamus goddess",
              group: "Egyptian", hemisphere: .northern,
              blurb: "The winding stars of Draco were seen by the Egyptians as Taweret, the protective hippopotamus goddess of the northern sky, guarding the imperishable circumpolar stars.",
              stars: ["Eltanin", "Rastaban", "Grumium", "Nu Dra", "Thuban", "Edasich"],
              paths: [[0, 1, 3, 2, 0], [1, 4, 5]]),

        // Norse (additional)
        .init(id: "thjazis-eyes", name: "Thjazi's Eyes", meaning: "Castor & Pollux",
              group: "Norse", hemisphere: .northern,
              blurb: "When the giant Thjazi was slain, Thor (or Odin) hurled his eyes into the heavens to become two bright stars — identified with the twin stars Castor and Pollux.",
              stars: ["Castor", "Pollux"], paths: [[0, 1]]),
    ]
}
