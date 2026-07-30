import Foundation
import CelestialCore

/// Descriptive and derived data for stars. The catalog ships ~110k stars; we can't
/// hand-write prose for each, so this layer provides two things:
///
/// 1. **Derived facts for every star** — surface temperature (from the B−V colour
///    index), the meaning of its spectral class, and the full constellation name.
///    These are computed from catalog columns, so they apply to the whole catalog.
/// 2. **Curated prose for famous stars** — hand-written summaries for the brightest
///    and most storied stars, keyed by proper name.
///
/// Sources are listed in the About → Sources screen and `CLAUDE.md`.
enum StarFacts {

    // MARK: Derived temperature (Ballesteros 2012)

    /// Effective surface temperature in kelvin, estimated from the B−V colour index
    /// using the Ballesteros (2012) two-blackbody formula. `nil` if no colour index.
    /// Accurate to a few percent for main-sequence stars; a rough guide for giants.
    static func temperatureKelvin(colorIndex: Double?) -> Double? {
        guard let bv = colorIndex else { return nil }
        return 4600 * (1 / (0.92 * bv + 1.7) + 1 / (0.92 * bv + 0.62))
    }

    // MARK: Spectral class

    /// A plain-language description of a star's spectral type, e.g.
    /// "A — hot, blue-white star" from "A0m...". Reads the leading class letter
    /// (the Harvard sequence O B A F G K M) and, when present, the Roman-numeral
    /// luminosity class (I supergiant … V main sequence).
    static func spectralDescription(_ spectralType: String?) -> String? {
        guard let raw = spectralType?.trimmingCharacters(in: .whitespaces),
              let cls = raw.uppercased().first(where: { "OBAFGKMLTYCSWR".contains($0) })
        else { return nil }

        let kind: String? = {
            switch cls {
            case "O": "blue, extremely hot and massive"
            case "B": "blue-white, hot and luminous"
            case "A": "white to blue-white"
            case "F": "yellow-white"
            case "G": "yellow, Sun-like"
            case "K": "orange, cooler than the Sun"
            case "M": "red, cool and often huge or very dim"
            case "L", "T", "Y": "a brown dwarf — too cool to fuse hydrogen"
            case "C", "S": "a cool carbon-rich giant"
            case "W": "a Wolf–Rayet star, shedding its outer layers"
            case "R": "a cool carbon star"
            default: nil
            }
        }()
        guard let kind else { return nil }

        var text = "\(cls) — \(kind)"
        if let lum = luminosityClass(in: raw) { text += "; \(lum)" }
        return text
    }

    /// Decode the Yerkes luminosity class (Roman numerals) from a spectral string.
    private static func luminosityClass(in spectral: String) -> String? {
        let upper = spectral.uppercased()
        // Test most specific first so "III" isn't mistaken for "II" or "I".
        let table: [(String, String)] = [
            ("VII", "white dwarf"),
            ("VI", "subdwarf"),
            ("IV", "subgiant"),
            ("III", "giant"),
            ("II", "bright giant"),
            ("IB", "less-luminous supergiant"),
            ("IA", "luminous supergiant"),
            ("V", "main-sequence (dwarf) star"),
            ("I", "supergiant"),
        ]
        for (numeral, label) in table where upper.contains(numeral) { return label }
        return nil
    }

    // MARK: Derived radius (Stefan–Boltzmann)

    /// A star's radius in solar radii, derived from its catalog luminosity and its
    /// colour-derived temperature via the Stefan–Boltzmann law. `nil` if either
    /// input is missing. A rough, intuition-grade figure (see `Astrophysics`).
    static func radiusSolar(for star: Star) -> Double? {
        guard let l = star.luminosity, let t = temperatureKelvin(colorIndex: star.colorIndex) else { return nil }
        return Astrophysics.stellarRadiusSolar(luminositySolar: l, temperatureKelvin: t)
    }

    // MARK: Relatable comparisons

    /// Plain-language, human-anchored one-liners that turn a star's raw numbers into
    /// intuition — how long its light has travelled, how it compares to the Sun in
    /// brightness, heat, and size. Only the comparisons we can actually derive from
    /// this star's data are returned, so callers can show whatever they get.
    static func relatableFacts(for star: Star, now: Date = Date()) -> [String] {
        var facts: [String] = []
        if let pc = star.distanceParsecs, pc > 0 { facts.append(lightTravelSentence(distanceParsecs: pc, now: now)) }
        if let l = star.luminosity { facts.append(luminositySentence(l)) }
        if let t = temperatureKelvin(colorIndex: star.colorIndex) { facts.append(temperatureSentence(t)) }
        if let r = radiusSolar(for: star) { facts.append(radiusSentence(r)) }
        return facts
    }

    /// "Its light has travelled N years to reach you — you're seeing it as it was in YYYY."
    static func lightTravelSentence(distanceParsecs: Double, now: Date = Date()) -> String {
        let years = Astrophysics.lightTravelYears(fromParsecs: distanceParsecs)
        let currentYear = Calendar.current.component(.year, from: now)
        if years < 1 {
            let months = Int((years * 12).rounded())
            return "Its light reaches you in about \(max(1, months)) month\(months == 1 ? "" : "s")."
        }
        let whole = Int(years.rounded())
        // Only attach a calendar year when it lands within recorded history; beyond
        // that "X years ago" stays meaningful where "the year −18000" would not.
        if whole <= 4000 {
            return "Its light took \(compact(years)) years to reach you — you're seeing it as it was around the year \(currentYear - whole)."
        }
        return "Its light took \(compact(years)) years to reach you — it left long before recorded history."
    }

    /// "Pours out ~120,000× the Sun's light." / "About 1⁄400 as bright as the Sun."
    static func luminositySentence(_ luminositySolar: Double) -> String {
        if luminositySolar >= 1.15 {
            return "Pours out about \(compact(luminositySolar))× the Sun's light."
        } else if luminositySolar <= 0.85 {
            return "Shines at roughly \(percent(luminositySolar)) of the Sun's brightness."
        }
        return "About as luminous as the Sun."
    }

    /// "Its surface is ~3× hotter than the Sun's (≈17,000 K)." / "...cooler..."
    static func temperatureSentence(_ kelvin: Double) -> String {
        let ratio = kelvin / Astrophysics.solarEffectiveTemperatureK
        let t = "≈ \(compact(kelvin)) K"
        if ratio >= 1.15 {
            return "Its surface runs about \(compact(ratio))× hotter than the Sun's (\(t))."
        } else if ratio <= 0.85 {
            return "Its surface is cooler than the Sun's (\(t))."
        }
        return "Its surface is about as hot as the Sun's (\(t))."
    }

    /// "Vast — roughly 700× the Sun's diameter." / "Smaller than the Sun..."
    static func radiusSentence(_ radiusSolar: Double) -> String {
        if radiusSolar >= 100 {
            return "Vast — roughly \(compact(radiusSolar))× the Sun's diameter; it would engulf the inner planets."
        } else if radiusSolar >= 10 {
            return "A giant — about \(compact(radiusSolar))× the size of the Sun."
        } else if radiusSolar >= 1.5 {
            return "About \(compact(radiusSolar))× the Sun's size."
        } else if radiusSolar <= 0.5 {
            return "Compact — only about \(percent(radiusSolar)) of the Sun's size."
        }
        return "About the size of the Sun."
    }

    // MARK: Stellar life story (narrative astrophysics)

    /// A one-sentence "biography" of a star from its spectral and luminosity class:
    /// roughly how long it lives and how it ends. Turns the catalog into stories
    /// rather than a spreadsheet. `nil` when the spectral type is missing or is a
    /// kind we don't narrate (e.g. brown dwarfs, carbon stars). General stellar
    /// evolution; see About → Sources.
    static func lifeStory(for star: Star) -> String? {
        guard let raw = star.spectralType?.trimmingCharacters(in: .whitespaces),
              let cls = raw.uppercased().first(where: { "OBAFGKM".contains($0) }) else { return nil }
        let lum = luminosityClass(in: raw) ?? ""

        if lum.contains("white dwarf") {
            return "A white dwarf — the dense, cooling ember left when a Sun-like star cast off its outer layers. No longer fusing, it will fade slowly over billions of years."
        }
        if lum.contains("supergiant") {
            return "A supergiant in the final act of its life — vastly luminous and short-lived, destined to explode as a supernova."
        }
        // "subgiant" before "giant": the former contains the latter as a substring.
        if lum.contains("subgiant") {
            return "A subgiant just leaving the main sequence, beginning to swell as the hydrogen in its core runs low."
        }
        if lum.contains("giant") {   // covers "giant" and "bright giant"
            return "A giant past its main-sequence prime: its core hydrogen spent, it has swelled and cooled, on its way to shedding its outer layers."
        }

        // Main sequence (or unannotated) — lifetime and fate scale with mass, which
        // the spectral class stands in for.
        switch cls {
        case "O", "B":
            return "A hot, massive star burning through its fuel in just a few to a few tens of millions of years — it will end in a supernova, leaving a neutron star or black hole."
        case "A":
            return "A main-sequence star a couple of times the Sun's mass; it will shine for one to two billion years before swelling into a red giant and ending as a white dwarf."
        case "F":
            return "A main-sequence star a little hotter than the Sun, with a few billion years ahead before it becomes a red giant and then a white dwarf."
        case "G":
            return "A Sun-like main-sequence star with a roughly ten-billion-year life; one day it will swell into a red giant and end as a slowly cooling white dwarf."
        case "K":
            return "An orange main-sequence star that burns slowly and steadily — it can shine for many tens of billions of years before fading."
        case "M":
            return "A red dwarf so frugal with its fuel it could keep burning for trillions of years — far longer than the current age of the universe."
        default:
            return nil
        }
    }

    // MARK: Number formatting

    /// Compact human number: "1.5", "120", "17k", "1.2M".
    private static func compact(_ value: Double) -> String {
        switch abs(value) {
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 10_000...: return String(format: "%.0fk", value / 1_000)
        case 100...: return String(format: "%.0f", value)
        case 10...: return String(format: "%.0f", value)
        default: return String(format: "%.1f", value)
        }
    }

    /// A small fraction as a friendly ratio, e.g. 0.0025 → "1⁄400".
    private static func percent(_ value: Double) -> String {
        guard value > 0 else { return "0%" }
        if value >= 0.1 { return "\(Int((value * 100).rounded()))%" }
        return "1⁄\(Int((1 / value).rounded()))"
    }

    // MARK: Constellation full names

    /// Full constellation name from a 3-letter IAU abbreviation (e.g. "CMa" →
    /// "Canis Major"), with the genitive context used in star naming where helpful.
    static func constellationName(_ abbrev: String?) -> String? {
        guard let key = abbrev?.trimmingCharacters(in: .whitespaces), !key.isEmpty else { return nil }
        return constellations[key.capitalized] ?? constellations[key]
    }

    private static let constellations: [String: String] = [
        "And": "Andromeda", "Ant": "Antlia", "Aps": "Apus", "Aqr": "Aquarius",
        "Aql": "Aquila", "Ara": "Ara", "Ari": "Aries", "Aur": "Auriga",
        "Boo": "Boötes", "Cae": "Caelum", "Cam": "Camelopardalis", "Cnc": "Cancer",
        "CVn": "Canes Venatici", "CMa": "Canis Major", "CMi": "Canis Minor",
        "Cap": "Capricornus", "Car": "Carina", "Cas": "Cassiopeia", "Cen": "Centaurus",
        "Cep": "Cepheus", "Cet": "Cetus", "Cha": "Chamaeleon", "Cir": "Circinus",
        "Col": "Columba", "Com": "Coma Berenices", "CrA": "Corona Australis",
        "CrB": "Corona Borealis", "Crv": "Corvus", "Crt": "Crater", "Cru": "Crux",
        "Cyg": "Cygnus", "Del": "Delphinus", "Dor": "Dorado", "Dra": "Draco",
        "Equ": "Equuleus", "Eri": "Eridanus", "For": "Fornax", "Gem": "Gemini",
        "Gru": "Grus", "Her": "Hercules", "Hor": "Horologium", "Hya": "Hydra",
        "Hyi": "Hydrus", "Ind": "Indus", "Lac": "Lacerta", "Leo": "Leo",
        "LMi": "Leo Minor", "Lep": "Lepus", "Lib": "Libra", "Lup": "Lupus",
        "Lyn": "Lynx", "Lyr": "Lyra", "Men": "Mensa", "Mic": "Microscopium",
        "Mon": "Monoceros", "Mus": "Musca", "Nor": "Norma", "Oct": "Octans",
        "Oph": "Ophiuchus", "Ori": "Orion", "Pav": "Pavo", "Peg": "Pegasus",
        "Per": "Perseus", "Phe": "Phoenix", "Pic": "Pictor", "Psc": "Pisces",
        "PsA": "Piscis Austrinus", "Pup": "Puppis", "Pyx": "Pyxis", "Ret": "Reticulum",
        "Sge": "Sagitta", "Sgr": "Sagittarius", "Sco": "Scorpius", "Scl": "Sculptor",
        "Sct": "Scutum", "Ser": "Serpens", "Sex": "Sextans", "Tau": "Taurus",
        "Tel": "Telescopium", "Tri": "Triangulum", "TrA": "Triangulum Australe",
        "Tuc": "Tucana", "UMa": "Ursa Major", "UMi": "Ursa Minor", "Vel": "Vela",
        "Vir": "Virgo", "Vol": "Volans", "Vul": "Vulpecula",
    ]

    // MARK: Display name & search

    /// The best human-facing label for a star: its proper name, else its
    /// Bayer/Flamsteed designation, else a catalog number (HR/HD/HIP/Gliese), else
    /// its database id. Never empty — so every star in the catalog is showable.
    static func displayName(for star: Star) -> String {
        if let n = star.properName, !n.isEmpty { return n }
        if let bf = star.bayerFlamsteed, !bf.isEmpty { return bf }
        if let hr = star.harvardRevised { return "HR \(hr)" }
        if let hd = star.henryDraper { return "HD \(hd)" }
        if let hip = star.hipparcos { return "HIP \(hip)" }
        if let gl = star.gliese, !gl.isEmpty { return gl }
        return "Star \(star.id)"
    }

    /// One lowercase haystack per star for the Catalog's live search — built once
    /// alongside the sorted star list, so a keystroke filters against prebuilt
    /// strings instead of lowercasing four optional fields per star per keystroke.
    /// Fields mirror `matches(_:query:)`; newline-joined so a query can't
    /// accidentally match across field boundaries.
    static func searchKey(for star: Star) -> String {
        var parts: [String] = []
        if let n = star.properName { parts.append(n) }
        if let bf = star.bayerFlamsteed { parts.append(bf) }
        if let c = star.constellation {
            parts.append(c)
            if let full = constellationName(c) { parts.append(full) }
        }
        if let hd = star.henryDraper { parts.append("hd \(hd)") }
        if let hr = star.harvardRevised { parts.append("hr \(hr)") }
        if let hip = star.hipparcos { parts.append("hip \(hip)") }
        if let gl = star.gliese { parts.append(gl) }
        return parts.joined(separator: "\n").lowercased()
    }

    /// Whether a star matches a lowercased search query across its names,
    /// designations (Bayer/Flamsteed, HR/HD/HIP/Gliese), and constellation.
    static func matches(_ star: Star, query q: String) -> Bool {
        if (star.properName ?? "").lowercased().contains(q) { return true }
        if (star.bayerFlamsteed ?? "").lowercased().contains(q) { return true }
        if (star.constellation ?? "").lowercased().contains(q) { return true }
        if (constellationName(star.constellation) ?? "").lowercased().contains(q) { return true }
        if let hd = star.henryDraper, "hd \(hd)".contains(q) || "\(hd)" == q { return true }
        if let hr = star.harvardRevised, "hr \(hr)".contains(q) { return true }
        if let hip = star.hipparcos, "hip \(hip)".contains(q) { return true }
        if let gl = star.gliese, gl.lowercased().contains(q) { return true }
        return false
    }

    // MARK: Curated prose for famous stars

    /// A hand-written summary for a well-known star, keyed by proper name, or `nil`
    /// for stars without one. Facts are drawn from public astrophysical references
    /// (see About → Sources).
    static func summary(for properName: String?) -> String? {
        guard let name = properName else { return nil }
        return descriptions[name]
    }

    // MARK: Generated prose for the rest of the catalog

    /// A synthesized lead sentence for the ~99.6% of catalog stars with no curated
    /// prose, so every detail page opens with words instead of a wall of numbers.
    /// Built only from this star's catalog data — spectral class (colour + giant/
    /// supergiant/dwarf), constellation, and distance — with no invented specifics.
    static func generatedSummary(for star: Star) -> String {
        let name = displayName(for: star)
        var sentence = "\(name) is \(describeKind(star))"
        if let con = constellationName(star.constellation) { sentence += " in \(con)" }
        if let pc = star.distanceParsecs, pc > 0 {
            sentence += ", some \(compact(pc * 3.2616)) light-years away"
        }
        return sentence + "."
    }

    /// "a yellow G-type star", "an orange K-type giant", "a white-dwarf remnant" —
    /// the kind phrase (with article) from the spectral string, falling back to a
    /// colour-from-temperature guess, then a bare "a star".
    private static func describeKind(_ star: Star) -> String {
        if let raw = star.spectralType?.trimmingCharacters(in: .whitespaces),
           let cls = raw.uppercased().first(where: { "OBAFGKM".contains($0) }) {
            let colour = colourWord(forClass: cls)
            if let lc = luminosityClass(in: raw) {
                // Order matters: "subgiant"/"supergiant" both contain "giant", so the
                // more specific labels must be tested before the bare "giant".
                if lc.contains("white dwarf") { return "a white-dwarf remnant" }
                if lc.contains("supergiant") { return "\(colour) \(cls)-type supergiant" }
                if lc.contains("subgiant") { return "\(colour) \(cls)-type subgiant" }
                if lc.contains("giant") { return "\(colour) \(cls)-type giant" }   // covers bright giant
            }
            return "\(colour) \(cls)-type star"
        }
        if let t = temperatureKelvin(colorIndex: star.colorIndex) { return "\(colourWord(forTemp: t)) star" }
        return "a star"
    }

    /// Colour adjective (with article) for a Harvard spectral class letter.
    private static func colourWord(forClass cls: Character) -> String {
        switch cls {
        case "O": return "a blue"
        case "B": return "a blue-white"
        case "A": return "a white"
        case "F": return "a yellow-white"
        case "G": return "a yellow"
        case "K": return "an orange"
        case "M": return "a red"
        default: return "a"
        }
    }

    /// Colour adjective (with article) from an effective temperature, for the rare
    /// star with a colour index but no spectral type. Delegates to the shared
    /// band table so the words always match the displayed colour.
    private static func colourWord(forTemp t: Double) -> String {
        TemperatureColor.adjective(forKelvin: t)
    }

    private static let descriptions: [String: String] = [
        "Sol": "Our Sun — a G-type main-sequence star, the anchor of the Solar System and the closest star to Earth at 8.3 light-minutes.",
        "Sirius": "The brightest star in the night sky, Sirius A is a hot blue-white star just 8.6 light-years away, orbited by the faint white-dwarf companion Sirius B.",
        "Canopus": "The second-brightest star in the sky, a luminous yellow-white supergiant in Carina long used as a navigation beacon by spacecraft.",
        "Rigil Kentaurus": "Alpha Centauri A, the Sun-like primary of the nearest star system, just 4.4 light-years away and host (with Proxima) to known planets.",
        "Toliman": "Alpha Centauri B, the orange companion to Rigil Kentaurus in the nearest star system.",
        "Proxima Centauri": "The closest known star to the Sun at 4.24 light-years — a faint red dwarf that hosts Proxima b, a roughly Earth-mass planet in its habitable zone.",
        "Arcturus": "A bright orange giant in Boötes, 37 light-years away, racing through the galaxy on an unusual orbit out of the galactic halo.",
        "Vega": "A brilliant blue-white star in Lyra, once the northern pole star and the original zero-point for the magnitude scale; girdled by a dusty debris disk.",
        "Capella": "Actually two yellow giant stars in close orbit in Auriga, appearing as one of the brightest points in the northern sky.",
        "Rigel": "A blue supergiant in Orion, tens of thousands of times more luminous than the Sun — one of the most intrinsically bright stars visible to the eye.",
        "Procyon": "A white main-sequence star in Canis Minor, 11.5 light-years away, with a white-dwarf companion (Procyon B).",
        "Betelgeuse": "A vast red supergiant marking Orion's shoulder; so large it would engulf the inner planets, and destined to explode as a supernova.",
        "Achernar": "The blue-white star ending the river Eridanus — spinning so fast it is flattened into a marked oblate spheroid.",
        "Hadar": "Beta Centauri, a hot blue-white giant trio that, with Alpha Centauri, forms the Southern Pointers toward the Southern Cross.",
        "Altair": "A nearby white star in Aquila, 16.7 light-years away, rotating so rapidly that a day there lasts only about nine hours.",
        "Acrux": "Alpha Crucis, the brightest star of the Southern Cross — a pair of hot blue stars 320 light-years away.",
        "Aldebaran": "The orange giant eye of Taurus, appearing among (but in front of) the Hyades cluster, 65 light-years away.",
        "Antares": "A red supergiant rivalling Mars in colour at the heart of Scorpius — its name means 'rival of Ares'.",
        "Spica": "A hot blue binary in Virgo whose two stars orbit every four days, distorting each other into egg shapes.",
        "Pollux": "An orange giant in Gemini, the nearest giant star to the Sun, with a confirmed Jupiter-mass planet.",
        "Castor": "A remarkable six-star system in Gemini that appears as a single bright point to the unaided eye.",
        "Fomalhaut": "A young white star in Piscis Austrinus encircled by a sharp-edged debris ring — one of the first stars imaged with a candidate planet.",
        "Deneb": "A blue-white supergiant marking the tail of Cygnus; extraordinarily luminous and one of the most distant first-magnitude stars.",
        "Mimosa": "Beta Crucis, a hot blue-white giant in the Southern Cross and one of the hottest first-magnitude stars.",
        "Regulus": "The blue-white 'little king' at the heart of Leo, a fast-spinning star flattened by its rotation, with faint companions.",
        "Adhara": "A blue-white giant in Canis Major — one of the strongest sources of ultraviolet light near the Sun.",
        "Bellatrix": "A hot blue-white giant marking Orion's other shoulder, sometimes called the 'Amazon Star'.",
        "Polaris": "The current North Star, a Cepheid variable supergiant in Ursa Minor that sits almost exactly above Earth's north pole.",
        "Alnilam": "The central, brightest star of Orion's Belt — a blue supergiant losing mass through powerful stellar winds.",
        "Alnitak": "The eastern star of Orion's Belt, a hot blue triple system near the Flame and Horsehead nebulae.",
        "Mintaka": "The western star of Orion's Belt, a complex multiple system lying almost exactly on the celestial equator.",
        "Wezen": "A yellow-white supergiant in Canis Major, intrinsically among the most luminous stars known.",
        "Vindemiatrix": "A yellow giant in Virgo, its name meaning 'the grape-gatherer' for its dawn rising at harvest time.",
        "Algol": "The 'Demon Star' in Perseus — an eclipsing binary whose brightness dips every 2.9 days as a companion passes in front.",
        "Mira": "A pulsating red giant in Cetus whose brightness swings over hundreds of days; the prototype of the Mira variables.",
        "Alpha Centauri": "The nearest star system to the Sun at 4.4 light-years — a Sun-like pair (A and B) accompanied by the red dwarf Proxima.",
    ]
}
