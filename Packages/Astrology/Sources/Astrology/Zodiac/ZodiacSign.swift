import CelestialCore

/// The twelve signs of the zodiac, each spanning 30° of ecliptic longitude
/// measured from 0° (the start of Aries). Ordering is the standard astrological
/// sequence; `rawValue` is the 0-based index (Aries = 0 … Pisces = 11).
public enum ZodiacSign: Int, Sendable, Hashable, CaseIterable {
    case aries, taurus, gemini, cancer, leo, virgo
    case libra, scorpio, sagittarius, capricorn, aquarius, pisces

    /// The sign occupied by a given ecliptic longitude. A tiny epsilon absorbs
    /// the round-trip error of `Angle` (stored in radians) so a longitude sitting
    /// exactly on a 30° cusp classifies into the sign it begins, not the one before.
    public init(longitude: Angle) {
        let deg = longitude.normalized.degrees + 1e-9
        let index = Int((deg / 30.0).rounded(.down)) % 12
        self = ZodiacSign(rawValue: index)!
    }

    /// Ecliptic longitude of the sign's 0° cusp.
    public var startLongitude: Angle { .degrees(Double(rawValue) * 30.0) }

    public var name: String {
        ["Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
         "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"][rawValue]
    }

    /// The astrological glyph (Unicode U+2648…U+2653).
    public var glyph: String {
        ["♈︎", "♉︎", "♊︎", "♋︎", "♌︎", "♍︎",
         "♎︎", "♏︎", "♐︎", "♑︎", "♒︎", "♓︎"][rawValue]
    }

    public enum Element: Sendable { case fire, earth, air, water }
    public enum Modality: Sendable { case cardinal, fixed, mutable }
    public enum Polarity: Sendable { case positive, negative } // diurnal/masculine vs nocturnal/feminine

    public var element: Element { [.fire, .earth, .air, .water][rawValue % 4] }
    public var modality: Modality { [.cardinal, .fixed, .mutable][rawValue % 3] }
    public var polarity: Polarity { rawValue % 2 == 0 ? .positive : .negative }

    /// Traditional (pre-modern) planetary ruler. Modern rulerships (Uranus/
    /// Neptune/Pluto) are a separate concern handled at the interpretation layer.
    public var traditionalRuler: AstroBody {
        switch self {
        case .aries, .scorpio: return .mars
        case .taurus, .libra: return .venus
        case .gemini, .virgo: return .mercury
        case .cancer: return .moon
        case .leo: return .sun
        case .sagittarius, .pisces: return .jupiter
        case .capricorn, .aquarius: return .saturn
        }
    }
}

/// A position expressed within its zodiac sign: the sign plus how far into it
/// (0°–30°). The natural way to *display* an ecliptic longitude on a chart.
public struct ZodiacPosition: Sendable, Hashable {
    public let longitude: Angle        // absolute ecliptic longitude [0,360)
    public let sign: ZodiacSign
    public let degreesIntoSign: Double // [0, 30)

    public init(longitude: Angle) {
        let lon = longitude.normalized
        let sign = ZodiacSign(longitude: lon)
        self.longitude = lon
        self.sign = sign
        // Tie the offset to the chosen sign so a cusp longitude reads 0°, not 30°.
        self.degreesIntoSign = max(0, min(30, lon.degrees - sign.startLongitude.degrees))
    }

    /// Degree-minute-second breakdown within the sign.
    public var dms: (degrees: Int, minutes: Int, seconds: Int) {
        let d = Int(degreesIntoSign)
        let mFloat = (degreesIntoSign - Double(d)) * 60.0
        let m = Int(mFloat)
        let s = Int((mFloat - Double(m)) * 60.0)
        return (d, m, s)
    }

    /// e.g. "14°23′ Scorpio".
    public var description: String {
        let (d, m, _) = dms
        return "\(d)°\(String(format: "%02d", m))′ \(sign.name)"
    }
}
