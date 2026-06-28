import CelestialCore
import Foundation

/// The four cardinal angles of a chart, in **tropical** ecliptic longitude.
///
/// These are the spine every house system builds on. They depend only on the
/// local sidereal time, the obliquity, and the observer's latitude.
public struct ChartAngles: Sendable, Hashable {
    /// Ascendant — the ecliptic degree rising on the eastern horizon (cusp 1).
    public let ascendant: Angle
    /// Midheaven (Medium Coeli) — the ecliptic degree culminating (cusp 10).
    public let midheaven: Angle
    /// Descendant — opposite the Ascendant (cusp 7).
    public var descendant: Angle { (ascendant + .degrees(180)).normalized }
    /// Imum Coeli — opposite the Midheaven (cusp 4).
    public var imumCoeli: Angle { (midheaven + .degrees(180)).normalized }

    /// Right Ascension of the Midheaven — the local (apparent) sidereal time
    /// expressed as an angle. Retained because the time-based house systems
    /// (Placidus, Koch) need it directly.
    public let ramc: Angle
    /// Obliquity of the ecliptic used in the computation.
    public let obliquity: Angle
    /// Observer geographic latitude used in the computation.
    public let latitude: Angle

    /// Compute the angles from local sidereal time, obliquity and latitude.
    ///
    /// Formulas (β = 0 ecliptic):
    ///   MC  = atan2( sin RAMC, cos RAMC · cos ε )
    ///   ASC = atan2( cos RAMC, −( sin RAMC · cos ε + tan φ · sin ε ) )
    public init(localSiderealTime ramc: Angle, obliquity: Angle, latitude: Angle) {
        let ε = obliquity
        let φ = latitude
        let r = ramc.normalized

        let mc = Angle.atan2(y: r.sine, x: r.cosine * ε.cosine).normalized

        let asc = Angle.atan2(
            y: r.cosine,
            x: -(r.sine * ε.cosine + φ.tangent * ε.sine)
        ).normalized

        self.ramc = r
        self.obliquity = ε
        self.latitude = φ
        self.midheaven = mc
        self.ascendant = asc
    }

    /// Convenience: compute the angles for an instant and observer using
    /// `CelestialCore`'s mean sidereal time and mean obliquity. (Apparent
    /// sidereal/obliquity — nutation — is a `CelestialCore` TODO; sub-arcmin.)
    public init(at jd: JulianDay, location: GeographicLocation) {
        let lst = SiderealTime.localMean(at: jd, longitude: location.longitude)
        let ε = Earth.meanObliquity(at: jd)
        self.init(localSiderealTime: lst, obliquity: ε, latitude: location.latitude)
    }
}
