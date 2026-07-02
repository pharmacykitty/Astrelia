import CelestialCore

/// A small, **owned** interpretation layer. Rather than ship a licensed corpus or
/// generate text at runtime, we compose readable sentences from authored keyword
/// tables — deterministic, on-brand, full-coverage, and free of licensing risk
/// (see `docs/astrology-features.md`). Tone is plain and modern; this is the
/// symbolic layer, kept separate from the astrophysics.
public enum Interpretation {

    // MARK: Public API

    /// A characterisation of a sign.
    public static func sign(_ s: ZodiacSign) -> String {
        "\(s.name) is \(signTone[s]!) — \(element(s.element)), \(modality(s.modality)). At heart, \(signGift[s]!)."
    }

    /// What a planet placed in a sign means.
    public static func planetInSign(_ b: AstroBody, _ s: ZodiacSign) -> String {
        let tone = signTone[s]!
        return "Your \(b.name) is in \(s.name): \(theme[b] ?? "this energy") expressed in \(article(tone)) \(tone) way. "
            + "\(s.name) is \(element(s.element)), \(modality(s.modality)) — so \(signGift[s]!); the growth edge is \(signEdge[s]!)."
    }

    /// What a planet placed in a house means.
    public static func planetInHouse(_ b: AstroBody, _ house: Int) -> String {
        let h = max(1, min(12, house))
        return "With \(b.name) in the \(ordinal(h)) house, \(theme[b] ?? "this energy") plays out through \(houseDomain[h]!). "
            + "This is the area of life where you \(houseFocus[h]!)."
    }

    /// What an aspect between two bodies means.
    public static func aspect(_ kind: AspectKind, _ a: AstroBody, _ b: AstroBody) -> String {
        "\(a.name) \(kind.name.lowercased()) \(b.name) links \(theme[a] ?? "this energy") with \(theme[b] ?? "that energy") — they \(aspectDynamic[kind] ?? "interact"). "
            + aspectFeel(kind)
    }

    /// A transit's meaning (transiting body acting on a natal body).
    public static func transit(_ kind: AspectKind, transiting: AstroBody, natal: AstroBody) -> String {
        "Transiting \(transiting.name) \(kind.name.lowercased()) your natal \(natal.name): \(theme[transiting] ?? "this influence") meets \(theme[natal] ?? "that part of you"). "
            + transitFeel(kind)
    }

    // MARK: Keyword tables

    static let theme: [AstroBody: String] = [
        .sun: "your core identity and vitality",
        .moon: "your emotions and inner needs",
        .mercury: "how you think and communicate",
        .venus: "how you love and what you value",
        .mars: "your drive and how you assert yourself",
        .jupiter: "where you grow and seek meaning",
        .saturn: "your discipline and where you mature",
        .uranus: "where you innovate and break free",
        .neptune: "your imagination, dreams, and ideals",
        .pluto: "where you face power and deep change",
        .northNode: "your growth edge and direction forward",
        .southNode: "your comfort zone and past patterns",
        .chiron: "your deepest wound, and where you can heal others",
        .ceres: "how you nurture and what truly nourishes you",
        .pallas: "your creative intelligence and pattern-making",
        .juno: "commitment and what you need in a partnership",
        .vesta: "your focus, devotion, and inner flame",
        .blackMoonLilith: "your untamed instincts and where you refuse to compromise",
    ]

    static let signTone: [ZodiacSign: String] = [
        .aries: "bold, direct, and pioneering",
        .taurus: "steady, sensual, and grounded",
        .gemini: "curious, quick, and communicative",
        .cancer: "caring, intuitive, and protective",
        .leo: "warm, expressive, and proud",
        .virgo: "precise, practical, and improving",
        .libra: "balanced, relational, and fair",
        .scorpio: "intense, perceptive, and transformative",
        .sagittarius: "adventurous, candid, and seeking",
        .capricorn: "disciplined, ambitious, and enduring",
        .aquarius: "original, independent, and forward-looking",
        .pisces: "imaginative, compassionate, and dreamy",
    ]

    static let houseDomain: [Int: String] = [
        1: "your self-image and how you meet the world",
        2: "money, values, and what makes you feel secure",
        3: "communication, learning, and your immediate surroundings",
        4: "home, family, and your roots",
        5: "creativity, romance, and play",
        6: "work, health, and daily routines",
        7: "partnership and one-to-one relationships",
        8: "intimacy, shared resources, and transformation",
        9: "beliefs, travel, and higher learning",
        10: "career, reputation, and your public role",
        11: "friends, groups, and your hopes for the future",
        12: "the unconscious, solitude, and what's hidden",
    ]

    static let aspectDynamic: [AspectKind: String] = [
        .conjunction: "fuse and amplify each other",
        .sextile: "support each other with easy opportunity",
        .square: "create productive friction that pushes growth",
        .trine: "flow together with natural ease",
        .opposition: "pull in opposite directions, seeking balance",
        .semisextile: "nudge each other in subtle ways",
        .semisquare: "create minor irritation that prompts action",
        .quintile: "spark a creative, gifted connection",
        .sesquiquadrate: "build tension that demands release",
        .biquintile: "weave a subtle creative talent",
        .quincunx: "require ongoing adjustment to reconcile",
    ]

    /// What each sign does at its best (reads after "so …").
    static let signGift: [ZodiacSign: String] = [
        .aries: "it acts decisively and meets challenges head-on",
        .taurus: "it builds something solid and savours the result",
        .gemini: "it learns fast and links ideas and people",
        .cancer: "it protects and nurtures what it loves",
        .leo: "it creates warmly and lights up a room",
        .virgo: "it refines, helps, and gets the details right",
        .libra: "it seeks fairness and brings people together",
        .scorpio: "it sees beneath the surface and commits all the way",
        .sagittarius: "it reaches for the big picture and tells the truth",
        .capricorn: "it builds for the long term and earns respect",
        .aquarius: "it thinks for itself and works for the whole",
        .pisces: "it imagines deeply and meets others with compassion",
    ]

    /// Each sign's growth edge (reads after "the growth edge is …").
    static let signEdge: [ZodiacSign: String] = [
        .aries: "tempering impulse with a little patience",
        .taurus: "loosening its grip and welcoming change",
        .gemini: "going deep instead of darting away",
        .cancer: "letting people in past its shell",
        .leo: "sharing the spotlight generously",
        .virgo: "easing up on the inner critic",
        .libra: "honouring its own needs, not only keeping the peace",
        .scorpio: "trusting, and letting go of control",
        .sagittarius: "following through on the details it would rather skip",
        .capricorn: "softening, and letting achievement rest",
        .aquarius: "staying warm and personally connected",
        .pisces: "staying grounded and guarding its energy",
    ]

    /// Each house's lived focus (reads after "the area of life where you …").
    static let houseFocus: [Int: String] = [
        1: "shape your identity and step into the world",
        2: "build security and discover what you truly value",
        3: "learn, talk, and connect with your everyday world",
        4: "put down roots and build a sense of belonging",
        5: "create, play, and let yourself be seen",
        6: "do the daily work of staying well and useful",
        7: "meet others as equals and grow through partnership",
        8: "share deeply and move through transformation",
        9: "seek meaning and widen your horizons",
        10: "build a reputation and contribute in public",
        11: "find your people and work toward a shared future",
        12: "retreat, reflect, and meet what lies beneath",
    ]

    // MARK: Helpers

    /// How an aspect *feels*, by harmony family — added after the mechanism.
    private enum Feel { case flowing, challenging, fusing, subtle }
    private static func feel(_ k: AspectKind) -> Feel {
        switch k {
        case .trine, .sextile: .flowing
        case .square, .opposition, .semisquare, .sesquiquadrate: .challenging
        case .conjunction: .fusing
        case .semisextile, .quincunx, .quintile, .biquintile: .subtle
        }
    }

    static func aspectFeel(_ k: AspectKind) -> String {
        switch feel(k) {
        case .flowing: "This comes naturally — a strength you can lean on, though it's easy to take for granted."
        case .challenging: "Expect some friction here; that tension is exactly what builds strength and depth over time."
        case .fusing: "Fused together, these act as one force — concentrated and hard to separate, for better and worse."
        case .subtle: "A quieter thread that asks for small, ongoing adjustments rather than big moves."
        }
    }

    static func transitFeel(_ k: AspectKind) -> String {
        switch feel(k) {
        case .flowing: "A supportive window — things in this area tend to open up more easily than usual."
        case .challenging: "A demanding stretch that asks you to grow; better to move through it than around it."
        case .fusing: "A strong new beginning in this area — hard to ignore, and worth working with consciously."
        case .subtle: "A lighter background influence — noticeable mainly if you're paying attention."
        }
    }

    private static func element(_ e: ZodiacSign.Element) -> String {
        switch e { case .fire: "a fire sign"; case .earth: "an earth sign"
        case .air: "an air sign"; case .water: "a water sign" }
    }
    private static func modality(_ m: ZodiacSign.Modality) -> String {
        switch m { case .cardinal: "cardinal (initiating)"
        case .fixed: "fixed (stabilising)"; case .mutable: "mutable (adapting)" }
    }
    /// "a"/"an" for the following word (vowel-sound heuristic).
    private static func article(_ word: String) -> String {
        "aeiou".contains(word.lowercased().first ?? "x") ? "an" : "a"
    }
    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: "1st"; case 2: "2nd"; case 3: "3rd"; case 21: "21st"; case 22: "22nd"; case 23: "23rd"
        default: "\(n)th"
        }
    }
}

/// One titled block of a multi-section reading.
public struct ReadingSection: Sendable, Hashable {
    public let title: String
    public let body: String
    public init(title: String, body: String) { self.title = title; self.body = body }
}

extension Interpretation {

    /// A note on a planet's essential dignity, or nil when it has none.
    public static func dignityNote(_ b: AstroBody, _ d: Dignity) -> String? {
        switch d {
        case .domicile: "\(b.name) is in its home sign — it works with natural strength and ease here."
        case .exaltation: "\(b.name) is exalted — honoured and amplified in this sign."
        case .detriment: "\(b.name) is in detriment, opposite its home — it works against the grain and must adapt."
        case .fall: "\(b.name) is in fall — its expression is muted and is learned through effort."
        case .none: nil
        }
    }

    /// A full, sectioned reading for a placement: sign, house, dignity, and the
    /// body's tightest aspects. Powers the expandable reading sheet (F4).
    public static func planetReading(
        _ b: AstroBody, sign: ZodiacSign, house: Int,
        dignity: Dignity = .none,
        retrograde: Bool = false,
        aspects: [(kind: AspectKind, other: AstroBody)] = []
    ) -> [ReadingSection] {
        var out: [ReadingSection] = []
        out.append(.init(title: "In the sign", body: planetInSign(b, sign)))
        out.append(.init(title: "In the \(ordinal(house)) house", body: planetInHouse(b, house)))
        if let note = dignityNote(b, dignity) {
            out.append(.init(title: "Dignity", body: note))
        }
        if retrograde, let r = retrogradeNote(b) {
            out.append(.init(title: "Retrograde", body: r))
        }
        if !aspects.isEmpty {
            let lines = aspects.prefix(4).map {
                "\(aspectGlyphless(b, $0.kind, $0.other)) — \(aspectDynamic[$0.kind] ?? "interact")."
            }
            out.append(.init(title: "Key aspects", body: lines.joined(separator: "\n")))
        }
        return out
    }

    private static func aspectGlyphless(_ a: AstroBody, _ k: AspectKind, _ b: AstroBody) -> String {
        "\(a.name) \(k.name.lowercased()) \(b.name)"
    }
}

// MARK: - Predictive (progressions & returns)

extension Interpretation {

    /// What secondary progressions are, framed for the user's current age.
    public static func progressionsOverview(age: Double) -> String {
        let years = Int(age.rounded())
        return "Secondary progressions move the chart forward 'a day for a year' — this is your inner chart at about age \(years). "
            + "It unfolds slowly: the progressed Moon sets the emotional season (a new sign roughly every two and a half years) and the progressed Sun marks longer chapters of who you're becoming. "
            + "Read the progressed planets against your birth houses, and through the aspects they now make back to your natal chart."
    }

    /// A progressed body's current placement — the slow inner shift it marks.
    public static func progressedPlacement(_ b: AstroBody, sign s: ZodiacSign, house: Int) -> String {
        let h = max(1, min(12, house))
        let tone = signTone[s]!
        let lead: String
        switch b {
        case .moon:
            lead = "Your progressed Moon has moved into \(s.name): for roughly two and a half years your emotional weather turns \(tone). What nourishes you, and how you settle, shifts to match."
        case .sun:
            lead = "Your progressed Sun is in \(s.name): a years-long chapter in which your sense of self grows more \(tone), quietly reorienting what you're here to express."
        default:
            lead = "Your progressed \(b.name) is in \(s.name): \(theme[b] ?? "this energy") is maturing in \(article(tone)) \(tone) direction."
        }
        return lead + " It's developing through your natal \(ordinal(h)) house — \(houseDomain[h]!)."
    }

    /// A progressed→natal aspect (a slow inner contact perfecting over months).
    public static func progressedAspect(_ kind: AspectKind, progressed: AstroBody, natal: AstroBody) -> String {
        "Your progressed \(progressed.name) is \(kind.name.lowercased()) your natal \(natal.name): \(theme[progressed] ?? "this energy") slowly comes into contact with \(theme[natal] ?? "that part of you"). "
            + transitFeel(kind)
    }

    // MARK: Retrograde, house rulers, elemental balance

    /// What a natal retrograde planet means (only the planets that can retrograde).
    public static func retrogradeNote(_ b: AstroBody) -> String? {
        let canRetro: Set<AstroBody> = [.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto]
        guard canRetro.contains(b) else { return nil }
        return "\(b.name) was retrograde at your birth, so \(theme[b] ?? "this energy") turns inward. "
            + "You tend to express it on your own timing — more reflectively, and often you revisit or rework this area before it fully clicks."
    }

    /// Short label for a house's life-area (for compact phrasing).
    static let houseShort: [Int: String] = [
        1: "your sense of self", 2: "money and values", 3: "communication and learning",
        4: "home and roots", 5: "creativity and romance", 6: "work and health",
        7: "partnership", 8: "intimacy and transformation", 9: "beliefs and horizons",
        10: "career and reputation", 11: "friends and hopes", 12: "the inner and hidden life",
    ]

    /// How a house's ruler ties two areas of life together.
    public static func houseRuler(house: Int, sign: ZodiacSign,
                                  ruler: AstroBody, rulerSign: ZodiacSign, rulerHouse: Int) -> String {
        let h = max(1, min(12, house)); let rh = max(1, min(12, rulerHouse))
        let base = "\(sign.name) sits on the cusp of your \(ordinal(h)) house, so \(ruler.name) rules \(houseShort[h]!). "
        if rh == h {
            return base + "It sits in that same house, in \(rulerSign.name) — so this area is self-contained and strongly themed."
        }
        return base + "\(ruler.name) lives in your \(ordinal(rh)) house, in \(rulerSign.name) — so \(houseShort[h]!) is woven together with \(houseShort[rh]!)."
    }

    /// A holistic read of the chart's elemental and modal weighting.
    public static func elementalBalance(_ positions: [BodyPosition]) -> [ReadingSection] {
        // Weigh the ten planets (skip nodes, points, asteroids).
        let core: Set<AstroBody> = [.sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto]
        let signs = positions.filter { core.contains($0.body) }.map { $0.position.sign }
        guard !signs.isEmpty else { return [] }

        var elem: [ZodiacSign.Element: Int] = [:]
        var modal: [ZodiacSign.Modality: Int] = [:]
        for s in signs { elem[s.element, default: 0] += 1; modal[s.modality, default: 0] += 1 }

        let eLabel: [ZodiacSign.Element: String] = [.fire: "Fire", .earth: "Earth", .air: "Air", .water: "Water"]
        let counts = "Fire \(elem[.fire] ?? 0) · Earth \(elem[.earth] ?? 0) · Air \(elem[.air] ?? 0) · Water \(elem[.water] ?? 0)"
        let top = elem.max { $0.value < $1.value }?.key ?? .fire
        let low = [ZodiacSign.Element.fire, .earth, .air, .water].min { (elem[$0] ?? 0) < (elem[$1] ?? 0) } ?? .water

        var body = "Across your ten planets: \(counts). Your chart leans \(eLabel[top]!) — \(elementGift[top]!). "
        if (elem[low] ?? 0) <= 1 {
            body += "With little \(eLabel[low]!), \(elementLack[low]!) "
        }
        let topMod = modal.max { $0.value < $1.value }?.key ?? .cardinal
        body += "By rhythm it's mostly \(modality(topMod)) — \(modalityGift[topMod]!)."
        return [ReadingSection(title: "Elements & balance", body: body)]
    }

    static let elementGift: [ZodiacSign.Element: String] = [
        .fire: "you move with warmth, drive, and instinct",
        .earth: "you're grounded, practical, and build things that last",
        .air: "you live in ideas, words, and connection",
        .water: "you feel deeply and navigate by emotion and intuition",
    ]
    static let elementLack: [ZodiacSign.Element: String] = [
        .fire: "spark and self-assertion may be something you grow into deliberately.",
        .earth: "grounding and follow-through may take conscious effort.",
        .air: "stepping back for perspective and words may be a learned skill.",
        .water: "tuning into feeling — yours and others' — may be a growth area.",
    ]
    static let modalityGift: [ZodiacSign.Modality: String] = [
        .cardinal: "you initiate, lead, and get things moving",
        .fixed: "you sustain, commit, and see things through",
        .mutable: "you adapt, flex, and move with change",
    ]

    /// What a return chart is and how to read it.
    public static func returnOverview(_ kind: ReturnKind) -> String {
        switch kind {
        case .solar:
            "Your solar return is cast for the exact moment the Sun comes back to its birth position — once a year, near your birthday. It's a chart for your personal year ahead: its rising sign, its angles, and the house the year's Sun falls in colour the next twelve months."
        case .lunar:
            "A lunar return is cast for the moment the Moon regains its natal position — about once every twenty-seven days. It's a snapshot of the month ahead: the emotional tone, the rhythm, and where your attention will naturally gather."
        }
    }
}
