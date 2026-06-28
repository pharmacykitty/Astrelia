import CelestialCore

/// An angular relationship between two ecliptic points.
public enum AspectKind: Int, Sendable, Hashable, CaseIterable {
    // Major (Ptolemaic)
    case conjunction   // 0°
    case sextile       // 60°
    case square        // 90°
    case trine         // 120°
    case opposition    // 180°
    // Minor
    case semisextile   // 30°
    case semisquare    // 45°
    case quintile      // 72°
    case sesquiquadrate // 135°
    case biquintile    // 144°
    case quincunx      // 150°

    /// Exact separation in degrees.
    public var angle: Double {
        switch self {
        case .conjunction: return 0
        case .semisextile: return 30
        case .semisquare: return 45
        case .sextile: return 60
        case .quintile: return 72
        case .square: return 90
        case .trine: return 120
        case .sesquiquadrate: return 135
        case .biquintile: return 144
        case .quincunx: return 150
        case .opposition: return 180
        }
    }

    public var isMajor: Bool {
        switch self {
        case .conjunction, .sextile, .square, .trine, .opposition: return true
        default: return false
        }
    }

    public var name: String {
        switch self {
        case .conjunction: return "Conjunction"
        case .sextile: return "Sextile"
        case .square: return "Square"
        case .trine: return "Trine"
        case .opposition: return "Opposition"
        case .semisextile: return "Semisextile"
        case .semisquare: return "Semisquare"
        case .quintile: return "Quintile"
        case .sesquiquadrate: return "Sesquiquadrate"
        case .biquintile: return "Biquintile"
        case .quincunx: return "Quincunx"
        }
    }

    public var glyph: String {
        switch self {
        case .conjunction: return "☌"
        case .sextile: return "﹡"
        case .square: return "□"
        case .trine: return "△"
        case .opposition: return "☍"
        case .semisextile: return "⚺"
        case .semisquare: return "∠"
        case .quintile: return "Q"
        case .sesquiquadrate: return "⚼"
        case .biquintile: return "bQ"
        case .quincunx: return "⚻"
        }
    }
}

/// Orb policy: how far from exact an aspect may be and still count, by aspect
/// class, with an extra allowance when a luminary (Sun/Moon) is involved.
/// Defaults follow common natal-chart practice; all values are configurable.
public struct OrbPolicy: Sendable, Hashable {
    public var majorOrb: Double
    public var minorOrb: Double
    public var luminaryBonus: Double
    /// When false, only the five Ptolemaic aspects are detected.
    public var includeMinor: Bool

    public init(
        majorOrb: Double = 7.0,
        minorOrb: Double = 2.0,
        luminaryBonus: Double = 2.0,
        includeMinor: Bool = true
    ) {
        self.majorOrb = majorOrb
        self.minorOrb = minorOrb
        self.luminaryBonus = luminaryBonus
        self.includeMinor = includeMinor
    }

    public static let `default` = OrbPolicy()

    /// Allowed orb for a given aspect between two bodies.
    public func orb(for kind: AspectKind, between a: AstroBody, and b: AstroBody) -> Double {
        // Conjunction & opposition traditionally get the widest orb.
        let base: Double
        switch kind {
        case .conjunction, .opposition: base = majorOrb + 1.0
        default: base = kind.isMajor ? majorOrb : minorOrb
        }
        let bonus = (a.isLuminary || b.isLuminary) ? luminaryBonus : 0.0
        return base + bonus
    }
}

/// A detected aspect between two bodies.
public struct Aspect: Sendable, Hashable {
    public let bodyA: AstroBody
    public let bodyB: AstroBody
    public let kind: AspectKind
    /// Deviation from exact, in degrees (0 = partile).
    public let orb: Double
    /// True when the aspect is tightening (the bodies are moving toward exact).
    /// Nil when velocities were unavailable.
    public let isApplying: Bool?

    public init(bodyA: AstroBody, bodyB: AstroBody, kind: AspectKind, orb: Double, isApplying: Bool?) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.kind = kind
        self.orb = orb
        self.isApplying = isApplying
    }
}
