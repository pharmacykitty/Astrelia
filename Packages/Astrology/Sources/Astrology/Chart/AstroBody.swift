import CelestialCore

/// The celestial points a chart can carry. v1 wires the luminaries (Sun, Moon)
/// from `CelestialCore`; the planets and nodes are modelled here but their
/// ephemeris arrives in spec Phase B (SwiftAA, MIT) — see `EphemerisProvider`.
public enum AstroBody: Int, Sendable, Hashable, CaseIterable {
    case sun, moon
    case mercury, venus, mars, jupiter, saturn, uranus, neptune, pluto
    case northNode, southNode

    public var name: String {
        ["Sun", "Moon", "Mercury", "Venus", "Mars", "Jupiter", "Saturn",
         "Uranus", "Neptune", "Pluto", "North Node", "South Node"][rawValue]
    }

    public var glyph: String {
        ["☉", "☽", "☿", "♀", "♂", "♃", "♄", "♅", "♆", "♇", "☊", "☋"][rawValue]
    }

    /// The Sun and Moon — given extra orb in many aspect conventions.
    public var isLuminary: Bool { self == .sun || self == .moon }

    /// The seven classical (visible) bodies of traditional astrology.
    public static let classical: [AstroBody] =
        [.sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn]
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
