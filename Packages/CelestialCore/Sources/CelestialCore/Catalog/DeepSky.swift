/// A deep-sky object — a nebula, star cluster, or galaxy — from a curated,
/// bundled catalog: the full Messier list (M1–M110) plus a handful of famous
/// non-Messier NGC objects.
///
/// Coordinates are J2000.0 (the same frame as ``Star`` and the galaxy map), so
/// these sit correctly alongside the star catalog in any view. The Messier and
/// NGC catalogs are public-domain reference data; add a source attribution at the
/// UI/integration layer.
public struct DeepSkyObject: Sendable, Hashable, Identifiable {
    /// Stable identifier, e.g. "M31" (Messier) or "NGC 7000" (NGC-only objects).
    public let id: String

    /// Messier number (1…110), or `nil` for non-Messier objects.
    public var messier: Int?
    /// New General Catalogue number, or `nil` if not catalogued / not applicable.
    public var ngc: Int?

    /// Common name, e.g. "Andromeda Galaxy", when one is in popular use.
    public var name: String?

    public var kind: Kind

    /// J2000.0 right ascension / declination of the object's centre.
    public var equatorial: EquatorialCoordinates

    /// Integrated visual magnitude (lower = brighter), or `nil` if unknown.
    public var magnitude: Double?
    /// Host constellation, 3-letter IAU abbreviation (e.g. "And").
    public var constellation: String?
    /// Apparent angular size (largest dimension) in arcminutes, or `nil`.
    public var angularSizeArcmin: Double?
    /// Distance from the Sun in light-years, or `nil` if poorly known.
    public var distanceLightYears: Double?
    /// A short, accurate one-line description.
    public var summary: String

    public init(
        id: String,
        messier: Int? = nil,
        ngc: Int? = nil,
        name: String? = nil,
        kind: Kind,
        equatorial: EquatorialCoordinates,
        magnitude: Double? = nil,
        constellation: String? = nil,
        angularSizeArcmin: Double? = nil,
        distanceLightYears: Double? = nil,
        summary: String
    ) {
        self.id = id
        self.messier = messier
        self.ngc = ngc
        self.name = name
        self.kind = kind
        self.equatorial = equatorial
        self.magnitude = magnitude
        self.constellation = constellation
        self.angularSizeArcmin = angularSizeArcmin
        self.distanceLightYears = distanceLightYears
        self.summary = summary
    }

    /// The kind of deep-sky object.
    public enum Kind: Sendable, Hashable, CaseIterable {
        case galaxy
        case globularCluster
        case openCluster
        case planetaryNebula
        case emissionNebula
        case reflectionNebula
        case supernovaRemnant
        /// A nebula with an embedded/associated star cluster (e.g. the Eagle Nebula).
        case nebulaCluster
        /// Asterisms, star clouds, double stars and anything not otherwise classified.
        case other

        public var label: String {
            switch self {
            case .galaxy: "Galaxy"
            case .globularCluster: "Globular Cluster"
            case .openCluster: "Open Cluster"
            case .planetaryNebula: "Planetary Nebula"
            case .emissionNebula: "Emission Nebula"
            case .reflectionNebula: "Reflection Nebula"
            case .supernovaRemnant: "Supernova Remnant"
            case .nebulaCluster: "Nebula & Cluster"
            case .other: "Other"
            }
        }
    }
}

/// The bundled deep-sky catalog: Messier 1–110 plus famous NGC objects, with
/// J2000.0 coordinates. Pure, immutable reference data.
public enum DeepSky {
    /// Convenience constructor (decimal-degree RA/Dec) that mirrors the catalog frame.
    private static func obj(
        _ id: String,
        m messier: Int? = nil,
        ngc: Int? = nil,
        _ name: String? = nil,
        kind: DeepSkyObject.Kind,
        ra: Double, dec: Double,
        mag: Double? = nil,
        con: String? = nil,
        size: Double? = nil,
        dist: Double? = nil,
        _ summary: String
    ) -> DeepSkyObject {
        DeepSkyObject(
            id: id,
            messier: messier,
            ngc: ngc,
            name: name,
            kind: kind,
            equatorial: EquatorialCoordinates(
                rightAscension: .degrees(ra),
                declination: .degrees(dec)
            ),
            magnitude: mag,
            constellation: con,
            angularSizeArcmin: size,
            distanceLightYears: dist,
            summary: summary
        )
    }

    /// Every catalogued object (Messier 1–110 followed by the NGC extras).
    public static let all: [DeepSkyObject] = messier + ngcExtras

    // MARK: Queries

    /// Objects in the given constellation (3-letter IAU abbreviation, case-insensitive).
    public static func inConstellation(_ abbreviation: String) -> [DeepSkyObject] {
        let key = abbreviation.lowercased()
        return all.filter { $0.constellation?.lowercased() == key }
    }

    /// Objects of a given kind.
    public static func ofKind(_ kind: DeepSkyObject.Kind) -> [DeepSkyObject] {
        all.filter { $0.kind == kind }
    }

    /// Objects sorted brightest-first; those with unknown magnitude sort last.
    public static var brightest: [DeepSkyObject] {
        all.sorted { ($0.magnitude ?? .greatestFiniteMagnitude) < ($1.magnitude ?? .greatestFiniteMagnitude) }
    }

    // MARK: The Messier catalogue (M1–M110), J2000.0

    public static let messier: [DeepSkyObject] = [
        obj("M1", m: 1, ngc: 1952, "Crab Nebula", kind: .supernovaRemnant, ra: 83.6287, dec: 22.0145, mag: 8.4, con: "Tau", size: 6, dist: 6500,
            "Expanding remnant of a supernova recorded in 1054 AD, with a pulsar at its heart."),
        obj("M2", m: 2, ngc: 7089, kind: .globularCluster, ra: 323.3625, dec: -0.8233, mag: 6.5, con: "Aqr", size: 16, dist: 37500,
            "A rich, compact globular cluster in Aquarius, one of the larger known."),
        obj("M3", m: 3, ngc: 5272, kind: .globularCluster, ra: 205.5484, dec: 28.3773, mag: 6.2, con: "CVn", size: 18, dist: 33900,
            "A bright globular in Canes Venatici with around half a million stars."),
        obj("M4", m: 4, ngc: 6121, kind: .globularCluster, ra: 245.8967, dec: -26.5256, mag: 5.6, con: "Sco", size: 26, dist: 7200,
            "One of the closest globular clusters, near Antares in Scorpius."),
        obj("M5", m: 5, ngc: 5904, kind: .globularCluster, ra: 229.6384, dec: 2.0810, mag: 5.6, con: "Ser", size: 23, dist: 24500,
            "A large, ancient globular cluster in Serpens, faintly naked-eye."),
        obj("M6", m: 6, ngc: 6405, "Butterfly Cluster", kind: .openCluster, ra: 265.0833, dec: -32.2167, mag: 4.2, con: "Sco", size: 25, dist: 1600,
            "A bright open cluster in Scorpius whose stars trace a butterfly shape."),
        obj("M7", m: 7, ngc: 6475, "Ptolemy Cluster", kind: .openCluster, ra: 268.4625, dec: -34.7928, mag: 3.3, con: "Sco", size: 80, dist: 980,
            "A brilliant naked-eye open cluster noted by Ptolemy in 130 AD."),
        obj("M8", m: 8, ngc: 6523, "Lagoon Nebula", kind: .emissionNebula, ra: 270.9042, dec: -24.3867, mag: 6.0, con: "Sgr", size: 90, dist: 4100,
            "A giant star-forming cloud in Sagittarius, faintly visible to the naked eye."),
        obj("M9", m: 9, ngc: 6333, kind: .globularCluster, ra: 259.7992, dec: -18.5161, mag: 7.7, con: "Oph", size: 12, dist: 25800,
            "A globular cluster in Ophiuchus near the galactic centre."),
        obj("M10", m: 10, ngc: 6254, kind: .globularCluster, ra: 254.2877, dec: -4.1003, mag: 6.6, con: "Oph", size: 20, dist: 14300,
            "A bright globular cluster roughly midway across Ophiuchus."),
        obj("M11", m: 11, ngc: 6705, "Wild Duck Cluster", kind: .openCluster, ra: 282.7708, dec: -6.2667, mag: 6.3, con: "Sct", size: 14, dist: 6200,
            "One of the richest, most compact open clusters, in Scutum."),
        obj("M12", m: 12, ngc: 6218, kind: .globularCluster, ra: 251.8092, dec: -1.9486, mag: 6.7, con: "Oph", size: 16, dist: 15700,
            "A loose globular cluster in Ophiuchus, neighbour to M10."),
        obj("M13", m: 13, ngc: 6205, "Hercules Cluster", kind: .globularCluster, ra: 250.4235, dec: 36.4613, mag: 5.8, con: "Her", size: 20, dist: 22200,
            "The finest globular cluster of the northern sky, with several hundred thousand stars."),
        obj("M14", m: 14, ngc: 6402, kind: .globularCluster, ra: 264.4008, dec: -3.2459, mag: 7.6, con: "Oph", size: 11, dist: 30300,
            "A fairly distant globular cluster in Ophiuchus."),
        obj("M15", m: 15, ngc: 7078, kind: .globularCluster, ra: 322.4930, dec: 12.1670, mag: 6.2, con: "Peg", size: 18, dist: 33600,
            "A dense globular in Pegasus with one of the most concentrated cores known."),
        obj("M16", m: 16, ngc: 6611, "Eagle Nebula", kind: .nebulaCluster, ra: 274.7000, dec: -13.8067, mag: 6.0, con: "Ser", size: 35, dist: 7000,
            "A young open cluster wrapped in the nebula of the Pillars of Creation."),
        obj("M17", m: 17, ngc: 6618, "Omega Nebula", kind: .emissionNebula, ra: 275.1958, dec: -16.1717, mag: 6.0, con: "Sgr", size: 11, dist: 5000,
            "A bright emission nebula in Sagittarius, also called the Swan or Horseshoe."),
        obj("M18", m: 18, ngc: 6613, kind: .openCluster, ra: 274.9875, dec: -17.1333, mag: 7.5, con: "Sgr", size: 9, dist: 4900,
            "A small, sparse open cluster between M17 and M24."),
        obj("M19", m: 19, ngc: 6273, kind: .globularCluster, ra: 255.6571, dec: -26.2680, mag: 6.8, con: "Oph", size: 14, dist: 28700,
            "A notably oblate globular cluster near the galactic centre."),
        obj("M20", m: 20, ngc: 6514, "Trifid Nebula", kind: .emissionNebula, ra: 270.6042, dec: -22.9717, mag: 6.3, con: "Sgr", size: 28, dist: 5200,
            "A photogenic emission/reflection nebula split into lobes by dark dust lanes."),
        obj("M21", m: 21, ngc: 6531, kind: .openCluster, ra: 271.0500, dec: -22.4833, mag: 5.9, con: "Sgr", size: 13, dist: 4250,
            "A young open cluster in Sagittarius near the Trifid Nebula."),
        obj("M22", m: 22, ngc: 6656, "Sagittarius Cluster", kind: .globularCluster, ra: 279.0997, dec: -23.9047, mag: 5.1, con: "Sgr", size: 24, dist: 10600,
            "One of the brightest globular clusters, near the galactic bulge."),
        obj("M23", m: 23, ngc: 6494, kind: .openCluster, ra: 269.2667, dec: -19.0167, mag: 5.5, con: "Sgr", size: 27, dist: 2150,
            "A rich open cluster of around 150 stars in Sagittarius."),
        obj("M24", m: 24, "Sagittarius Star Cloud", kind: .other, ra: 274.2000, dec: -18.5500, mag: 4.6, con: "Sgr", size: 90, dist: 10000,
            "Not a true cluster but a dense star cloud — a window onto a distant spiral arm."),
        obj("M25", m: 25, kind: .openCluster, ra: 277.9417, dec: -19.1167, mag: 4.6, con: "Sgr", size: 32, dist: 2000,
            "A bright, scattered open cluster in Sagittarius."),
        obj("M26", m: 26, ngc: 6694, kind: .openCluster, ra: 281.3208, dec: -9.3833, mag: 8.0, con: "Sct", size: 15, dist: 5000,
            "A modest open cluster in Scutum near M11."),
        obj("M27", m: 27, ngc: 6853, "Dumbbell Nebula", kind: .planetaryNebula, ra: 299.9015, dec: 22.7212, mag: 7.5, con: "Vul", size: 8, dist: 1360,
            "The first planetary nebula discovered — a dying star's glowing shell in Vulpecula."),
        obj("M28", m: 28, ngc: 6626, kind: .globularCluster, ra: 276.1371, dec: -24.8697, mag: 6.8, con: "Sgr", size: 11, dist: 17900,
            "A compact globular cluster near Lambda Sagittarii."),
        obj("M29", m: 29, ngc: 6913, kind: .openCluster, ra: 305.9833, dec: 38.5167, mag: 7.1, con: "Cyg", size: 7, dist: 4000,
            "A small open cluster embedded in the rich star fields of Cygnus."),
        obj("M30", m: 30, ngc: 7099, kind: .globularCluster, ra: 325.0922, dec: -23.1799, mag: 7.2, con: "Cap", size: 12, dist: 27100,
            "A globular cluster in Capricornus with a collapsed, dense core."),
        obj("M31", m: 31, ngc: 224, "Andromeda Galaxy", kind: .galaxy, ra: 10.6847, dec: 41.2687, mag: 3.4, con: "And", size: 178, dist: 2537000,
            "The nearest large spiral galaxy and the most distant object visible to the naked eye."),
        obj("M32", m: 32, ngc: 221, kind: .galaxy, ra: 10.6743, dec: 40.8652, mag: 8.1, con: "And", size: 8, dist: 2490000,
            "A compact dwarf elliptical galaxy, a close satellite of Andromeda."),
        obj("M33", m: 33, ngc: 598, "Triangulum Galaxy", kind: .galaxy, ra: 23.4621, dec: 30.6600, mag: 5.7, con: "Tri", size: 70, dist: 2730000,
            "A nearby face-on spiral, third-largest member of the Local Group."),
        obj("M34", m: 34, ngc: 1039, kind: .openCluster, ra: 40.5167, dec: 42.7667, mag: 5.5, con: "Per", size: 35, dist: 1500,
            "A bright, loose open cluster in Perseus, fine in binoculars."),
        obj("M35", m: 35, ngc: 2168, kind: .openCluster, ra: 92.2708, dec: 24.3333, mag: 5.3, con: "Gem", size: 28, dist: 2800,
            "A large naked-eye open cluster near the feet of Gemini."),
        obj("M36", m: 36, ngc: 1960, kind: .openCluster, ra: 84.0833, dec: 34.1333, mag: 6.3, con: "Aur", size: 12, dist: 4100,
            "A young open cluster of hot blue stars in Auriga."),
        obj("M37", m: 37, ngc: 2099, kind: .openCluster, ra: 88.0750, dec: 32.5500, mag: 6.2, con: "Aur", size: 24, dist: 4500,
            "The richest of Auriga's three Messier open clusters."),
        obj("M38", m: 38, ngc: 1912, kind: .openCluster, ra: 82.1750, dec: 35.8333, mag: 7.4, con: "Aur", size: 21, dist: 4200,
            "An open cluster in Auriga whose brighter stars suggest a cross."),
        obj("M39", m: 39, ngc: 7092, kind: .openCluster, ra: 322.9667, dec: 48.4333, mag: 4.6, con: "Cyg", size: 32, dist: 825,
            "A large, sparse, nearby open cluster in Cygnus."),
        obj("M40", m: 40, "Winnecke 4", kind: .other, ra: 185.5521, dec: 58.0828, mag: 8.4, con: "UMa", size: 1, dist: 510,
            "Not a deep-sky object at all but an optical double star in Ursa Major."),
        obj("M41", m: 41, ngc: 2287, kind: .openCluster, ra: 101.5042, dec: -20.7167, mag: 4.5, con: "CMa", size: 38, dist: 2300,
            "A bright open cluster just south of Sirius in Canis Major."),
        obj("M42", m: 42, ngc: 1976, "Orion Nebula", kind: .emissionNebula, ra: 83.8221, dec: -5.3911, mag: 4.0, con: "Ori", size: 85, dist: 1344,
            "The nearest large star-forming region — the glowing heart of Orion's Sword."),
        obj("M43", m: 43, ngc: 1982, "De Mairan's Nebula", kind: .emissionNebula, ra: 83.8804, dec: -5.2700, mag: 9.0, con: "Ori", size: 20, dist: 1600,
            "A detached lobe of the Orion Nebula, separated by a dark dust lane."),
        obj("M44", m: 44, ngc: 2632, "Beehive Cluster", kind: .openCluster, ra: 130.1000, dec: 19.6667, mag: 3.7, con: "Cnc", size: 95, dist: 577,
            "A bright naked-eye open cluster in Cancer, known since antiquity as Praesepe."),
        obj("M45", m: 45, "Pleiades", kind: .openCluster, ra: 56.8710, dec: 24.1054, mag: 1.6, con: "Tau", size: 110, dist: 444,
            "The Seven Sisters — a brilliant young cluster veiled in blue reflection nebulosity."),
        obj("M46", m: 46, ngc: 2437, kind: .openCluster, ra: 115.4375, dec: -14.8167, mag: 6.1, con: "Pup", size: 27, dist: 5400,
            "A rich open cluster in Puppis with a planetary nebula superimposed."),
        obj("M47", m: 47, ngc: 2422, kind: .openCluster, ra: 114.1458, dec: -14.4833, mag: 4.4, con: "Pup", size: 30, dist: 1600,
            "A bright, coarse open cluster near its richer neighbour M46."),
        obj("M48", m: 48, ngc: 2548, kind: .openCluster, ra: 123.4292, dec: -5.7500, mag: 5.5, con: "Hya", size: 54, dist: 2500,
            "A large open cluster in Hydra, just visible to the naked eye."),
        obj("M49", m: 49, ngc: 4472, kind: .galaxy, ra: 187.4447, dec: 8.0004, mag: 8.4, con: "Vir", size: 9, dist: 56000000,
            "A giant elliptical galaxy, the brightest member of the Virgo Cluster."),
        obj("M50", m: 50, ngc: 2323, kind: .openCluster, ra: 105.6917, dec: -8.3333, mag: 5.9, con: "Mon", size: 16, dist: 3000,
            "A heart-shaped open cluster in Monoceros."),
        obj("M51", m: 51, ngc: 5194, "Whirlpool Galaxy", kind: .galaxy, ra: 202.4696, dec: 47.1952, mag: 8.4, con: "CVn", size: 11, dist: 23000000,
            "A classic grand-design spiral interacting with a smaller companion galaxy."),
        obj("M52", m: 52, ngc: 7654, kind: .openCluster, ra: 351.2000, dec: 61.5833, mag: 6.9, con: "Cas", size: 13, dist: 5000,
            "A rich open cluster in the Milky Way fields of Cassiopeia."),
        obj("M53", m: 53, ngc: 5024, kind: .globularCluster, ra: 198.2304, dec: 18.1681, mag: 7.6, con: "Com", size: 13, dist: 58000,
            "A distant globular cluster in Coma Berenices."),
        obj("M54", m: 54, ngc: 6715, kind: .globularCluster, ra: 283.7638, dec: -30.4799, mag: 7.6, con: "Sgr", size: 12, dist: 87400,
            "A globular belonging to the Sagittarius Dwarf Galaxy being absorbed by the Milky Way."),
        obj("M55", m: 55, ngc: 6809, kind: .globularCluster, ra: 294.9988, dec: -30.9648, mag: 6.3, con: "Sgr", size: 19, dist: 17600,
            "A large, loose globular cluster low in Sagittarius."),
        obj("M56", m: 56, ngc: 6779, kind: .globularCluster, ra: 289.1483, dec: 30.1834, mag: 8.3, con: "Lyr", size: 8, dist: 32900,
            "A modest globular cluster between Albireo and Lyra."),
        obj("M57", m: 57, ngc: 6720, "Ring Nebula", kind: .planetaryNebula, ra: 283.3962, dec: 33.0292, mag: 8.8, con: "Lyr", size: 1.4, dist: 2300,
            "The iconic smoke ring of an aged star shedding its outer layers, in Lyra."),
        obj("M58", m: 58, ngc: 4579, kind: .galaxy, ra: 189.4314, dec: 11.8181, mag: 9.7, con: "Vir", size: 6, dist: 62000000,
            "A barred spiral galaxy in the Virgo Cluster."),
        obj("M59", m: 59, ngc: 4621, kind: .galaxy, ra: 190.5096, dec: 11.6469, mag: 9.6, con: "Vir", size: 5, dist: 60000000,
            "An elliptical galaxy in the Virgo Cluster."),
        obj("M60", m: 60, ngc: 4649, kind: .galaxy, ra: 190.9167, dec: 11.5526, mag: 8.8, con: "Vir", size: 7, dist: 55000000,
            "A giant elliptical galaxy paired with the spiral NGC 4647."),
        obj("M61", m: 61, ngc: 4303, kind: .galaxy, ra: 185.4788, dec: 4.4736, mag: 9.7, con: "Vir", size: 6, dist: 52500000,
            "A bright barred spiral galaxy and frequent supernova host in Virgo."),
        obj("M62", m: 62, ngc: 6266, kind: .globularCluster, ra: 255.3033, dec: -30.1124, mag: 6.5, con: "Oph", size: 15, dist: 22500,
            "An asymmetric globular cluster near the galactic centre."),
        obj("M63", m: 63, ngc: 5055, "Sunflower Galaxy", kind: .galaxy, ra: 198.9554, dec: 42.0294, mag: 8.6, con: "CVn", size: 13, dist: 29300000,
            "A flocculent spiral with many short, patchy arms, in Canes Venatici."),
        obj("M64", m: 64, ngc: 4826, "Black Eye Galaxy", kind: .galaxy, ra: 194.1821, dec: 21.6829, mag: 8.5, con: "Com", size: 10, dist: 17000000,
            "A spiral with a dramatic dark dust band across its bright nucleus."),
        obj("M65", m: 65, ngc: 3623, kind: .galaxy, ra: 169.7330, dec: 13.0923, mag: 9.3, con: "Leo", size: 10, dist: 35000000,
            "A spiral galaxy in the Leo Triplet."),
        obj("M66", m: 66, ngc: 3627, kind: .galaxy, ra: 170.0626, dec: 12.9915, mag: 8.9, con: "Leo", size: 9, dist: 36000000,
            "The largest member of the Leo Triplet, distorted by gravitational interaction."),
        obj("M67", m: 67, ngc: 2682, kind: .openCluster, ra: 132.8250, dec: 11.8000, mag: 6.1, con: "Cnc", size: 30, dist: 2700,
            "One of the oldest known open clusters, in Cancer."),
        obj("M68", m: 68, ngc: 4590, kind: .globularCluster, ra: 189.8665, dec: -26.7449, mag: 7.8, con: "Hya", size: 11, dist: 33600,
            "A globular cluster in Hydra below Corvus."),
        obj("M69", m: 69, ngc: 6637, kind: .globularCluster, ra: 277.8463, dec: -32.3481, mag: 7.6, con: "Sgr", size: 7, dist: 29700,
            "A metal-rich globular cluster near the galactic bulge."),
        obj("M70", m: 70, ngc: 6681, kind: .globularCluster, ra: 280.8031, dec: -32.2921, mag: 7.9, con: "Sgr", size: 8, dist: 29400,
            "A small globular cluster low in Sagittarius, twin to M69."),
        obj("M71", m: 71, ngc: 6838, kind: .globularCluster, ra: 298.4438, dec: 18.7792, mag: 8.2, con: "Sge", size: 7, dist: 13000,
            "A loose globular cluster in the small constellation Sagitta."),
        obj("M72", m: 72, ngc: 6981, kind: .globularCluster, ra: 313.3654, dec: -12.5372, mag: 9.3, con: "Aqr", size: 6, dist: 54600,
            "A faint, distant globular cluster in Aquarius."),
        obj("M73", m: 73, ngc: 6994, kind: .other, ra: 314.7500, dec: -12.6333, mag: 8.9, con: "Aqr", size: 3, dist: 2500,
            "A chance asterism of four unrelated stars in Aquarius."),
        obj("M74", m: 74, ngc: 628, kind: .galaxy, ra: 24.1740, dec: 15.7836, mag: 9.4, con: "Psc", size: 10, dist: 32000000,
            "A delicate face-on grand-design spiral in Pisces."),
        obj("M75", m: 75, ngc: 6864, kind: .globularCluster, ra: 301.5202, dec: -21.9223, mag: 8.5, con: "Sgr", size: 7, dist: 67500,
            "A small, remote, highly concentrated globular cluster."),
        obj("M76", m: 76, ngc: 650, "Little Dumbbell Nebula", kind: .planetaryNebula, ra: 25.5821, dec: 51.5754, mag: 10.1, con: "Per", size: 3, dist: 2500,
            "A faint two-lobed planetary nebula in Perseus."),
        obj("M77", m: 77, ngc: 1068, kind: .galaxy, ra: 40.6696, dec: -0.0133, mag: 8.9, con: "Cet", size: 7, dist: 47000000,
            "A barred spiral and the brightest Seyfert galaxy, with an active nucleus."),
        obj("M78", m: 78, ngc: 2068, kind: .reflectionNebula, ra: 86.6908, dec: 0.0792, mag: 8.3, con: "Ori", size: 8, dist: 1600,
            "The brightest reflection nebula, glowing by light scattered from young stars in Orion."),
        obj("M79", m: 79, ngc: 1904, kind: .globularCluster, ra: 81.0442, dec: -24.5244, mag: 7.7, con: "Lep", size: 9, dist: 41000,
            "An unusual globular cluster in Lepus, likely captured from a dwarf galaxy."),
        obj("M80", m: 80, ngc: 6093, kind: .globularCluster, ra: 244.2600, dec: -22.9761, mag: 7.3, con: "Sco", size: 10, dist: 32600,
            "A dense globular cluster between Antares and Beta Scorpii."),
        obj("M81", m: 81, ngc: 3031, "Bode's Galaxy", kind: .galaxy, ra: 148.8882, dec: 69.0653, mag: 6.9, con: "UMa", size: 27, dist: 11800000,
            "A grand-design spiral, one of the brightest galaxies in the northern sky."),
        obj("M82", m: 82, ngc: 3034, "Cigar Galaxy", kind: .galaxy, ra: 148.9684, dec: 69.6797, mag: 8.4, con: "UMa", size: 11, dist: 12000000,
            "A starburst galaxy driven by its gravitational tug-of-war with M81."),
        obj("M83", m: 83, ngc: 5236, "Southern Pinwheel Galaxy", kind: .galaxy, ra: 204.2538, dec: -29.8658, mag: 7.5, con: "Hya", size: 13, dist: 15000000,
            "A bright, nearby barred spiral in Hydra, rich in supernovae."),
        obj("M84", m: 84, ngc: 4374, kind: .galaxy, ra: 186.2655, dec: 12.8870, mag: 9.1, con: "Vir", size: 6, dist: 60000000,
            "A lenticular galaxy at the heart of Markarian's Chain in Virgo."),
        obj("M85", m: 85, ngc: 4382, kind: .galaxy, ra: 186.3503, dec: 18.1912, mag: 9.1, con: "Com", size: 7, dist: 60000000,
            "A lenticular galaxy on the northern edge of the Virgo Cluster."),
        obj("M86", m: 86, ngc: 4406, kind: .galaxy, ra: 186.5492, dec: 12.9462, mag: 8.9, con: "Vir", size: 9, dist: 52000000,
            "A lenticular galaxy in Markarian's Chain, blueshifted toward us."),
        obj("M87", m: 87, ngc: 4486, "Virgo A", kind: .galaxy, ra: 187.7059, dec: 12.3911, mag: 8.6, con: "Vir", size: 7, dist: 53500000,
            "A supergiant elliptical with a relativistic jet and the first black hole ever imaged."),
        obj("M88", m: 88, ngc: 4501, kind: .galaxy, ra: 187.9967, dec: 14.4204, mag: 9.6, con: "Com", size: 7, dist: 60000000,
            "A multi-armed spiral galaxy in the Virgo Cluster."),
        obj("M89", m: 89, ngc: 4552, kind: .galaxy, ra: 188.9159, dec: 12.5563, mag: 9.8, con: "Vir", size: 5, dist: 50000000,
            "An elliptical galaxy in Virgo, nearly perfectly spherical."),
        obj("M90", m: 90, ngc: 4569, kind: .galaxy, ra: 189.2076, dec: 13.1629, mag: 9.5, con: "Vir", size: 10, dist: 58700000,
            "A spiral galaxy in Virgo, falling through the cluster and losing its gas."),
        obj("M91", m: 91, ngc: 4548, kind: .galaxy, ra: 188.8600, dec: 14.4963, mag: 10.2, con: "Com", size: 5, dist: 63000000,
            "A barred spiral galaxy in the Virgo Cluster, the faintest Messier object."),
        obj("M92", m: 92, ngc: 6341, kind: .globularCluster, ra: 259.2808, dec: 43.1359, mag: 6.4, con: "Her", size: 14, dist: 26700,
            "A bright, ancient globular cluster in Hercules, overshadowed by M13."),
        obj("M93", m: 93, ngc: 2447, kind: .openCluster, ra: 116.1167, dec: -23.8667, mag: 6.0, con: "Pup", size: 22, dist: 3600,
            "A compact, bright open cluster in Puppis."),
        obj("M94", m: 94, ngc: 4736, kind: .galaxy, ra: 192.7213, dec: 41.1203, mag: 8.2, con: "CVn", size: 11, dist: 16000000,
            "A spiral galaxy with a bright inner ring of star formation."),
        obj("M95", m: 95, ngc: 3351, kind: .galaxy, ra: 160.9904, dec: 11.7037, mag: 9.7, con: "Leo", size: 7, dist: 33000000,
            "A barred spiral galaxy in the Leo I group."),
        obj("M96", m: 96, ngc: 3368, kind: .galaxy, ra: 161.6906, dec: 11.8199, mag: 9.2, con: "Leo", size: 8, dist: 31000000,
            "The brightest galaxy of the Leo I group, an asymmetric spiral."),
        obj("M97", m: 97, ngc: 3587, "Owl Nebula", kind: .planetaryNebula, ra: 168.6987, dec: 55.0190, mag: 9.9, con: "UMa", size: 3, dist: 2030,
            "A planetary nebula in Ursa Major whose dark patches look like owl's eyes."),
        obj("M98", m: 98, ngc: 4192, kind: .galaxy, ra: 183.4513, dec: 14.9003, mag: 10.1, con: "Com", size: 10, dist: 44400000,
            "An edge-on spiral galaxy approaching the Virgo Cluster."),
        obj("M99", m: 99, ngc: 4254, kind: .galaxy, ra: 184.7067, dec: 14.4163, mag: 9.9, con: "Com", size: 5, dist: 50000000,
            "A nearly face-on spiral with one prominent, asymmetric arm."),
        obj("M100", m: 100, ngc: 4321, kind: .galaxy, ra: 185.7288, dec: 15.8224, mag: 9.3, con: "Com", size: 7, dist: 55000000,
            "A grand-design spiral, one of the brightest in the Virgo Cluster."),
        obj("M101", m: 101, ngc: 5457, "Pinwheel Galaxy", kind: .galaxy, ra: 210.8023, dec: 54.3489, mag: 7.9, con: "UMa", size: 29, dist: 21000000,
            "A large, face-on spiral galaxy in Ursa Major with sweeping arms."),
        obj("M102", m: 102, ngc: 5866, "Spindle Galaxy", kind: .galaxy, ra: 226.6233, dec: 55.7633, mag: 9.9, con: "Dra", size: 5, dist: 50000000,
            "An edge-on lenticular galaxy in Draco, the usual identification for the disputed M102."),
        obj("M103", m: 103, ngc: 581, kind: .openCluster, ra: 23.3400, dec: 60.6580, mag: 7.4, con: "Cas", size: 6, dist: 8500,
            "A fan-shaped open cluster in Cassiopeia, the last entry of Messier's own list."),
        obj("M104", m: 104, ngc: 4594, "Sombrero Galaxy", kind: .galaxy, ra: 189.9976, dec: -11.6231, mag: 8.0, con: "Vir", size: 9, dist: 29300000,
            "An edge-on spiral with a bright bulge and a striking dark dust lane."),
        obj("M105", m: 105, ngc: 3379, kind: .galaxy, ra: 161.9568, dec: 12.5816, mag: 9.8, con: "Leo", size: 5, dist: 32000000,
            "An elliptical galaxy in the Leo I group with a central black hole."),
        obj("M106", m: 106, ngc: 4258, kind: .galaxy, ra: 184.7401, dec: 47.3040, mag: 8.4, con: "CVn", size: 19, dist: 23700000,
            "A spiral with anomalous arms powered by an active galactic nucleus."),
        obj("M107", m: 107, ngc: 6171, kind: .globularCluster, ra: 248.1326, dec: -13.0537, mag: 7.9, con: "Oph", size: 13, dist: 20900,
            "A loose globular cluster in Ophiuchus, the last added to the catalogue."),
        obj("M108", m: 108, ngc: 3556, "Surfboard Galaxy", kind: .galaxy, ra: 167.8790, dec: 55.6741, mag: 10.0, con: "UMa", size: 9, dist: 46000000,
            "An edge-on barred spiral near the Big Dipper, mottled with dust."),
        obj("M109", m: 109, ngc: 3992, kind: .galaxy, ra: 179.3999, dec: 53.3745, mag: 9.8, con: "UMa", size: 8, dist: 83500000,
            "A barred spiral galaxy near Phecda in Ursa Major."),
        obj("M110", m: 110, ngc: 205, kind: .galaxy, ra: 10.0919, dec: 41.6853, mag: 8.5, con: "And", size: 22, dist: 2690000,
            "A dwarf elliptical satellite of the Andromeda Galaxy, the final Messier object."),
    ]

    // MARK: Famous non-Messier NGC objects

    public static let ngcExtras: [DeepSkyObject] = [
        obj("NGC 869", ngc: 869, "Double Cluster (h Persei)", kind: .openCluster, ra: 34.7417, dec: 57.1333, mag: 4.3, con: "Per", size: 30, dist: 7500,
            "The western half of Perseus's dazzling Double Cluster, rich in young hot stars."),
        obj("NGC 884", ngc: 884, "Double Cluster (chi Persei)", kind: .openCluster, ra: 35.5708, dec: 57.1333, mag: 4.4, con: "Per", size: 30, dist: 7500,
            "The eastern half of the Double Cluster, a companion to NGC 869."),
        obj("NGC 7000", ngc: 7000, "North America Nebula", kind: .emissionNebula, ra: 314.7500, dec: 44.5200, mag: 4.0, con: "Cyg", size: 120, dist: 2590,
            "A large emission nebula in Cygnus shaped like the North American continent."),
        obj("NGC 253", ngc: 253, "Sculptor Galaxy", kind: .galaxy, ra: 11.8879, dec: -25.2883, mag: 7.2, con: "Scl", size: 27, dist: 11400000,
            "A bright, dusty starburst spiral seen nearly edge-on, the nearest of its kind."),
        obj("NGC 5128", ngc: 5128, "Centaurus A", kind: .galaxy, ra: 201.3651, dec: -43.0191, mag: 6.8, con: "Cen", size: 26, dist: 12000000,
            "A peculiar elliptical galaxy crossed by a dust lane, with a powerful radio nucleus."),
        obj("NGC 6960", ngc: 6960, "Veil Nebula (Western)", kind: .supernovaRemnant, ra: 311.6542, dec: 30.7167, mag: 7.0, con: "Cyg", size: 70, dist: 2400,
            "The western filaments of the Cygnus Loop, a supernova remnant near 52 Cygni."),
        obj("NGC 6992", ngc: 6992, "Veil Nebula (Eastern)", kind: .supernovaRemnant, ra: 313.2333, dec: 31.7167, mag: 7.0, con: "Cyg", size: 75, dist: 2400,
            "The eastern arc of the Veil Nebula, lacework from a star that exploded millennia ago."),
        obj("NGC 7293", ngc: 7293, "Helix Nebula", kind: .planetaryNebula, ra: 337.4108, dec: -20.8372, mag: 7.6, con: "Aqr", size: 25, dist: 655,
            "One of the closest planetary nebulae — the 'Eye of God' — in Aquarius."),
        obj("NGC 5139", ngc: 5139, "Omega Centauri", kind: .globularCluster, ra: 201.6970, dec: -47.4795, mag: 3.9, con: "Cen", size: 36, dist: 17000,
            "The Milky Way's largest, brightest globular cluster, likely a stripped dwarf-galaxy core."),
        obj("NGC 104", ngc: 104, "47 Tucanae", kind: .globularCluster, ra: 6.0238, dec: -72.0814, mag: 4.0, con: "Tuc", size: 31, dist: 13000,
            "The second-brightest globular cluster, a dense southern jewel near the SMC."),
    ]
}
