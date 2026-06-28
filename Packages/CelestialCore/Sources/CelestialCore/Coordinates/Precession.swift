import Foundation

/// Precession of the equinoxes — the slow (~25,800-year) conical drift of Earth's
/// rotation axis that carries catalogue coordinates (referred to a fixed mean
/// equinox, e.g. J2000.0) onto the mean equinox of another date.
///
/// Implements the rigorous reduction of Meeus, *Astronomical Algorithms*, 2nd
/// ed., ch. 21, using the IAU 1976 precession angles ζ, z and θ. This is the
/// transform to apply to HYG / Hipparcos star positions (given at J2000) before
/// projecting them for the current instant.
///
/// Note: this models *precession only*. For a full apparent place one would also
/// apply nutation (see `Nutation`) and the star's proper motion; Meeus' worked
/// example 21.b applies proper motion first, then this precession step.
public enum Precession {
    /// Precess equatorial coordinates from the mean equinox of `jd0` to the mean
    /// equinox of `jd` (Meeus eqs. 21.2–21.4). Right ascension is returned in
    /// [0°, 360°).
    public static func precess(
        _ coords: EquatorialCoordinates,
        fromJD jd0: JulianDay,
        toJD jd: JulianDay
    ) -> EquatorialCoordinates {
        // T: centuries from J2000 to the starting epoch. t: centuries spanned.
        let bigT = (jd0.value - JulianDay.j2000.value) / 36525.0
        let t = (jd.value - jd0.value) / 36525.0

        // Precession angles in arcseconds (Meeus eq. 21.2).
        let zeta = (2306.2181 + 1.39656 * bigT - 0.000139 * bigT * bigT) * t
            + (0.30188 - 0.000344 * bigT) * t * t
            + 0.017998 * t * t * t
        let z = (2306.2181 + 1.39656 * bigT - 0.000139 * bigT * bigT) * t
            + (1.09468 + 0.000066 * bigT) * t * t
            + 0.018203 * t * t * t
        let theta = (2004.3109 - 0.85330 * bigT - 0.000217 * bigT * bigT) * t
            - (0.42665 + 0.000217 * bigT) * t * t
            - 0.041833 * t * t * t

        let zetaA = Angle.degrees(zeta / 3600.0)
        let zA = Angle.degrees(z / 3600.0)
        let thetaA = Angle.degrees(theta / 3600.0)

        let alpha0 = coords.rightAscension
        let delta0 = coords.declination
        let alphaPlusZeta = alpha0 + zetaA

        // Meeus eq. 21.4.
        let a = delta0.cosine * alphaPlusZeta.sine
        let b = thetaA.cosine * delta0.cosine * alphaPlusZeta.cosine - thetaA.sine * delta0.sine
        let c = thetaA.sine * delta0.cosine * alphaPlusZeta.cosine + thetaA.cosine * delta0.sine

        let rightAscension = (Angle.atan2(y: a, x: b) + zA).normalized
        let declination = Angle.asin(c)

        return EquatorialCoordinates(rightAscension: rightAscension, declination: declination)
    }

    /// Convenience: precess from the standard J2000.0 epoch to `jd` — the common
    /// case for reducing J2000 catalogue coordinates to the equinox of date.
    public static func fromJ2000(
        _ coords: EquatorialCoordinates,
        toJD jd: JulianDay
    ) -> EquatorialCoordinates {
        precess(coords, fromJD: .j2000, toJD: jd)
    }
}
