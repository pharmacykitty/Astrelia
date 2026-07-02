import CelestialCore

/// Essential dignity of a planet by sign — the classical condition scheme:
/// **domicile** (a planet in the sign it rules), **exaltation** (its sign of
/// honour), **detriment** (opposite its domicile), and **fall** (opposite its
/// exaltation). Points, nodes, and asteroids carry no dignity.
public enum Dignity: String, Sendable, Hashable {
    case domicile, exaltation, detriment, fall, none

    public var label: String {
        switch self {
        case .domicile: "domicile"
        case .exaltation: "exalted"
        case .detriment: "detriment"
        case .fall: "fall"
        case .none: ""
        }
    }

    /// A planet is strengthened in domicile/exaltation, weakened in detriment/fall.
    public var isStrong: Bool { self == .domicile || self == .exaltation }
    public var isWeak: Bool { self == .detriment || self == .fall }
}

/// Rulership / exaltation tables and the chart ruler. Uses traditional
/// rulerships for the seven classical bodies and modern rulerships for the three
/// outer planets, which is the common convention in software charts.
public enum Dignities {

    /// The sign(s) a body has as its domicile (sign it rules).
    public static func domicile(_ body: AstroBody) -> [ZodiacSign] {
        switch body {
        case .sun: [.leo]
        case .moon: [.cancer]
        case .mercury: [.gemini, .virgo]
        case .venus: [.taurus, .libra]
        case .mars: [.aries, .scorpio]
        case .jupiter: [.sagittarius, .pisces]
        case .saturn: [.capricorn, .aquarius]
        case .uranus: [.aquarius]
        case .neptune: [.pisces]
        case .pluto: [.scorpio]
        default: []
        }
    }

    /// The sign of a body's exaltation, if any.
    public static func exaltation(_ body: AstroBody) -> ZodiacSign? {
        switch body {
        case .sun: .aries
        case .moon: .taurus
        case .mercury: .virgo
        case .venus: .pisces
        case .mars: .capricorn
        case .jupiter: .cancer
        case .saturn: .libra
        default: nil
        }
    }

    /// The dignity of `body` when placed in `sign`.
    public static func dignity(of body: AstroBody, in sign: ZodiacSign) -> Dignity {
        let homes = domicile(body)
        if homes.contains(sign) { return .domicile }
        if exaltation(body) == sign { return .exaltation }
        let opp = opposite(sign)
        if homes.contains(opp) { return .detriment }
        if exaltation(body) == opp { return .fall }
        return .none
    }

    /// The chart ruler: the (traditional) ruler of the rising sign.
    public static func chartRuler(ascendantSign: ZodiacSign) -> AstroBody {
        ascendantSign.traditionalRuler
    }

    static func opposite(_ s: ZodiacSign) -> ZodiacSign {
        ZodiacSign(rawValue: (s.rawValue + 6) % 12)!
    }
}
