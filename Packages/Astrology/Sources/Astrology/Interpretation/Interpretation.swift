import CelestialCore

/// A small, **owned** interpretation layer. Rather than ship a licensed corpus or
/// generate text at runtime, we compose readable sentences from authored keyword
/// tables — deterministic, on-brand, full-coverage, and free of licensing risk
/// (see `docs/astrology-features.md`). Tone is plain and modern; this is the
/// symbolic layer, kept separate from the astrophysics.
public enum Interpretation {

    // MARK: Public API

    /// A one-line characterisation of a sign.
    public static func sign(_ s: ZodiacSign) -> String {
        "\(s.name) is \(signTone[s]!) — \(element(s.element)), \(modality(s.modality))."
    }

    /// What a planet placed in a sign means.
    public static func planetInSign(_ b: AstroBody, _ s: ZodiacSign) -> String {
        "Your \(b.name) is in \(s.name): \(theme[b] ?? "this energy") expressed in a \(signTone[s]!) way."
    }

    /// What a planet placed in a house means.
    public static func planetInHouse(_ b: AstroBody, _ house: Int) -> String {
        let h = max(1, min(12, house))
        return "With \(b.name) in the \(ordinal(h)) house, \(theme[b] ?? "this energy") plays out through \(houseDomain[h]!)."
    }

    /// What an aspect between two bodies means.
    public static func aspect(_ kind: AspectKind, _ a: AstroBody, _ b: AstroBody) -> String {
        "\(a.name) \(kind.name.lowercased()) \(b.name): \(theme[a] ?? "this energy") and \(theme[b] ?? "that energy") \(aspectDynamic[kind] ?? "interact")."
    }

    /// A transit's meaning (transiting body acting on a natal body).
    public static func transit(_ kind: AspectKind, transiting: AstroBody, natal: AstroBody) -> String {
        "Transiting \(transiting.name) \(kind.name.lowercased()) your natal \(natal.name): \(theme[transiting] ?? "this influence") currently \(aspectDynamic[kind] ?? "touches") \(theme[natal] ?? "that part of you")."
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

    // MARK: Helpers

    private static func element(_ e: ZodiacSign.Element) -> String {
        switch e { case .fire: "a fire sign"; case .earth: "an earth sign"
        case .air: "an air sign"; case .water: "a water sign" }
    }
    private static func modality(_ m: ZodiacSign.Modality) -> String {
        switch m { case .cardinal: "cardinal (initiating)"
        case .fixed: "fixed (stabilising)"; case .mutable: "mutable (adapting)" }
    }
    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: "1st"; case 2: "2nd"; case 3: "3rd"; case 21: "21st"; case 22: "22nd"; case 23: "23rd"
        default: "\(n)th"
        }
    }
}
