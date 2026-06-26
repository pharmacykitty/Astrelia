/// Observer position on Earth. Longitude is **east-positive** (the modern
/// convention; note Meeus uses west-positive in his worked examples, so his
/// longitudes must be negated to match).
public struct GeographicLocation: Sendable, Hashable {
    public var latitude: Angle
    public var longitude: Angle
    /// Metres above sea level. Unused by the Phase-1 transforms; kept for
    /// atmospheric refraction and parallax in later phases.
    public var altitude: Double

    public init(latitude: Angle, longitude: Angle, altitude: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

/// Equatorial coordinates: right ascension and declination, fixed to the
/// celestial sphere (independent of the observer).
public struct EquatorialCoordinates: Sendable, Hashable {
    public var rightAscension: Angle
    public var declination: Angle

    public init(rightAscension: Angle, declination: Angle) {
        self.rightAscension = rightAscension
        self.declination = declination
    }
}

/// Horizontal (alt-az) coordinates, relative to the observer's local horizon.
///
/// Azimuth is measured **from North, increasing toward East** (N=0°, E=90°,
/// S=180°, W=270°) — the convention a compass / AR camera view expects.
/// (Meeus measures azimuth from the South; convert with ±180°.)
public struct HorizontalCoordinates: Sendable, Hashable {
    public var azimuth: Angle
    public var altitude: Angle

    public init(azimuth: Angle, altitude: Angle) {
        self.azimuth = azimuth
        self.altitude = altitude
    }
}
