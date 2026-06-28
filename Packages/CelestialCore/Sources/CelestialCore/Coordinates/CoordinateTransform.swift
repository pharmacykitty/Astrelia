/// Conversions between celestial coordinate systems (Meeus, ch. 13).
///
/// Conventions used throughout:
/// - Azimuth is measured from **North, increasing toward East**.
/// - Longitude is **east-positive**.
/// - Hour angle is measured westward from the meridian (`H = LST − RA`).
public enum CoordinateTransform {

    /// Equatorial → horizontal, given the object's local hour angle and the
    /// observer's latitude.
    public static func horizontal(
        rightAscensionHourAngle hourAngle: Angle,
        declination: Angle,
        latitude: Angle
    ) -> HorizontalCoordinates {
        let h = hourAngle
        let dec = declination
        let lat = latitude

        let sinAltitude = dec.sine * lat.sine + dec.cosine * lat.cosine * h.cosine
        let altitude = Angle.asin(sinAltitude)

        // Azimuth from North, eastward.
        let y = -dec.cosine * h.sine
        let x = dec.sine * lat.cosine - dec.cosine * lat.sine * h.cosine
        let azimuth = Angle.atan2(y: y, x: x).normalized

        return HorizontalCoordinates(azimuth: azimuth, altitude: altitude)
    }

    /// Equatorial → horizontal for an observer at `location`, given a local
    /// sidereal time. The hour angle is computed as `LST − RA`.
    public static func horizontal(
        _ equatorial: EquatorialCoordinates,
        at location: GeographicLocation,
        localSiderealTime: Angle
    ) -> HorizontalCoordinates {
        let hourAngle = localSiderealTime - equatorial.rightAscension
        return horizontal(
            rightAscensionHourAngle: hourAngle,
            declination: equatorial.declination,
            latitude: location.latitude
        )
    }

    /// Convenience: equatorial → horizontal for an instant and observer, using
    /// **mean** sidereal time (nutation not yet modelled — see `SiderealTime`).
    public static func horizontal(
        _ equatorial: EquatorialCoordinates,
        at location: GeographicLocation,
        time jd: JulianDay
    ) -> HorizontalCoordinates {
        let lst = SiderealTime.localMean(at: jd, longitude: location.longitude)
        return horizontal(equatorial, at: location, localSiderealTime: lst)
    }

    /// Horizontal → equatorial (the inverse transform). Returns the declination
    /// and the local hour angle; recover right ascension with `RA = LST − hourAngle`.
    public static func equatorial(
        _ horizontal: HorizontalCoordinates,
        latitude: Angle
    ) -> (declination: Angle, hourAngle: Angle) {
        let alt = horizontal.altitude
        let az = horizontal.azimuth
        let lat = latitude

        let sinDeclination = alt.sine * lat.sine + alt.cosine * lat.cosine * az.cosine
        let declination = Angle.asin(sinDeclination)

        let y = -alt.cosine * az.sine
        let x = alt.sine * lat.cosine - alt.cosine * lat.sine * az.cosine
        let hourAngle = Angle.atan2(y: y, x: x)

        return (declination, hourAngle)
    }

    /// Ecliptic → equatorial, given the obliquity of the ecliptic (Meeus eq. 13.3/13.4).
    public static func equatorial(
        fromEcliptic ecliptic: EclipticCoordinates,
        obliquity: Angle
    ) -> EquatorialCoordinates {
        let lambda = ecliptic.longitude
        let beta = ecliptic.latitude
        let epsilon = obliquity

        let rightAscension = Angle.atan2(
            y: lambda.sine * epsilon.cosine - beta.tangent * epsilon.sine,
            x: lambda.cosine
        ).normalized
        let declination = Angle.asin(
            beta.sine * epsilon.cosine + beta.cosine * epsilon.sine * lambda.sine
        )

        return EquatorialCoordinates(rightAscension: rightAscension, declination: declination)
    }

    /// Equatorial → ecliptic, given the obliquity of the ecliptic (Meeus eq. 13.1/13.2).
    public static func ecliptic(
        fromEquatorial equatorial: EquatorialCoordinates,
        obliquity: Angle
    ) -> EclipticCoordinates {
        let alpha = equatorial.rightAscension
        let delta = equatorial.declination
        let epsilon = obliquity

        let longitude = Angle.atan2(
            y: alpha.sine * epsilon.cosine + delta.tangent * epsilon.sine,
            x: alpha.cosine
        ).normalized
        let latitude = Angle.asin(
            delta.sine * epsilon.cosine - delta.cosine * epsilon.sine * alpha.sine
        )

        return EclipticCoordinates(longitude: longitude, latitude: latitude)
    }
}
