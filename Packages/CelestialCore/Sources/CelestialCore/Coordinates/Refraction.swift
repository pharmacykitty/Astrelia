import Foundation

/// Atmospheric refraction — the apparent lifting of a body toward the zenith as
/// its light bends through the atmosphere. Largest near the horizon (~34′) and
/// negligible overhead. See Meeus, *Astronomical Algorithms*, ch. 16.
///
/// Two independent fits are used (they are *not* exact inverses of one another):
/// - `apparentAltitude(fromTrue:)` uses **Bennett's** formula (Meeus 16.3).
/// - `trueAltitude(fromApparent:)` uses Meeus 16.4.
///
/// Both assume standard atmosphere (1010 mb, 10 °C). The altitude argument is
/// clamped to a small floor so the formulae stay finite for bodies a little below
/// the horizon (the Sun at sunset, the Moon rising); below that the model is not
/// physical and refraction is held at its near-horizon value.
public enum Refraction {

    /// Lowest altitude (degrees) at which the refraction fits are evaluated.
    /// Below this the geometry stops being meaningful; we clamp to avoid the
    /// singularities at h = −4.4° (16.3) and h = −5.11° (16.4).
    private static let altitudeFloorDegrees = -2.0

    /// True (airless) altitude → apparent altitude, via Bennett's formula
    /// (Meeus eq. 16.3): R = 1 / tan(h + 7.31 / (h + 4.4)), R in arcminutes,
    /// h in degrees. The body always appears *higher* than it truly is.
    public static func apparentAltitude(fromTrue trueAltitude: Angle) -> Angle {
        let h = max(trueAltitude.degrees, altitudeFloorDegrees)
        let argumentDegrees = h + 7.31 / (h + 4.4)
        let rArcminutes = 1.0 / tan(argumentDegrees * .pi / 180.0)
        return trueAltitude + .degrees(rArcminutes / 60.0)
    }

    /// Apparent (observed) altitude → true airless altitude (Meeus eq. 16.4):
    /// R = 1.02 / tan(h + 10.3 / (h + 5.11)), R in arcminutes, h in degrees.
    /// Subtracts the refraction the atmosphere added.
    public static func trueAltitude(fromApparent apparentAltitude: Angle) -> Angle {
        let h = max(apparentAltitude.degrees, altitudeFloorDegrees)
        let argumentDegrees = h + 10.3 / (h + 5.11)
        let rArcminutes = 1.02 / tan(argumentDegrees * .pi / 180.0)
        return apparentAltitude - .degrees(rArcminutes / 60.0)
    }
}
