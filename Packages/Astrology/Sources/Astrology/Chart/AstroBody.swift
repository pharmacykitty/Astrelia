import CelestialCore

/// The celestial points a chart can carry. v1 wires the luminaries (Sun, Moon)
/// from `CelestialCore`; the planets and nodes are modelled here but their
/// ephemeris arrives in spec Phase B (SwiftAA, MIT) — see `EphemerisProvider`.
public enum AstroBody: Int, Sendable, Hashable, CaseIterable {
    case sun, moon
    case mercury, venus, mars, jupiter, saturn, uranus, neptune, pluto
    case northNode, southNode
    // Additional points & asteroids (off by default — opt-in via `points`).
    case chiron, ceres, pallas, juno, vesta, blackMoonLilith

    public var name: String {
        ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn",
         "Uranus", "Neptune", "Pluto", "North Node", "South Node",
         "Chiron", "Ceres", "Pallas", "Juno", "Vesta", "Lilith"][rawValue]
    }

    public var glyph: String {
        // U+FE0E forces line-art (text) presentation — ♀/♂ and some asteroid
        // glyphs default to colour emoji on iOS otherwise (see CLAUDE.md).
        ["☉", "☽", "☿", "♀", "♂", "♃", "♄", "♅", "♆", "♇", "☊", "☋",
         "⚷", "⚳", "⚴", "⚵", "⚶", "⚸"][rawValue] + "\u{FE0E}"
    }

    /// The Sun and Moon — given extra orb in many aspect conventions.
    public var isLuminary: Bool { self == .sun || self == .moon }

    /// The seven classical (visible) bodies of traditional astrology.
    public static let classical: [AstroBody] =
        [.sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn]

    /// The default chart set: ten planets plus the lunar nodes.
    public static let standard: [AstroBody] =
        [.sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn,
         .uranus, .neptune, .pluto, .northNode, .southNode]

    /// Opt-in points & asteroids (Chiron, the four asteroids, Black Moon Lilith).
    public static let points: [AstroBody] =
        [.chiron, .ceres, .pallas, .juno, .vesta, .blackMoonLilith]

    /// True for the opt-in extra points (not part of the standard chart).
    public var isExtraPoint: Bool { AstroBody.points.contains(self) }
}

/// A body's computed position in a chart.
public struct BodyPosition: Sendable, Hashable {
    public let body: AstroBody
    /// Ecliptic longitude in the chart's zodiac frame (tropical or sidereal).
    public let longitude: Angle
    /// Longitude velocity in degrees/day, when known. Negative ⇒ retrograde.
    public let speed: Double?
    /// Zodiac-sign breakdown of `longitude`, for display.
    public var position: ZodiacPosition { ZodiacPosition(longitude: longitude) }
    /// True when the body is moving retrograde (speed < 0). Nodes are treated
    /// as always retrograde by convention when no speed is supplied.
    public var isRetrograde: Bool {
        if let speed { return speed < 0 }
        return body == .northNode || body == .southNode
    }

    public init(body: AstroBody, longitude: Angle, speed: Double? = nil) {
        self.body = body
        self.longitude = longitude.normalized
        self.speed = speed
    }
}
