import Foundation

/// ΔT — the difference between Terrestrial / Dynamical Time and Universal Time
/// (ΔT = TD − UT), in seconds.
///
/// Ephemerides are computed in a uniform dynamical timescale (TD ≈ TT), but the
/// clock on the wall (and the rotation of the Earth, which drives sidereal time)
/// runs on UT. ΔT bridges the two. Earth's rotation is irregular, so ΔT cannot be
/// predicted exactly; this uses the **Espenak–Meeus (2006)** polynomial fits
/// (the set published with the NASA five-millennium eclipse canon).
///
/// **Valid range:** roughly the years −1999 … +3000. Inside the telescopic era
/// (≈1600 onward) the fits are good to a few seconds; before that, and as an
/// extrapolation beyond the last observed year (~2015), accuracy degrades and the
/// later expressions are forecasts, not measurements.
public enum DeltaT {
    /// ΔT = TD − UT in seconds at the given instant (any reasonable timescale may
    /// be passed — ΔT varies far too slowly for the UT/TD distinction to matter
    /// for its own argument).
    public static func seconds(at jd: JulianDay) -> Double {
        seconds(forDecimalYear: decimalYear(of: jd))
    }

    /// ΔT in seconds for a decimal year (e.g. `2020.5`), via the Espenak–Meeus
    /// piecewise polynomials.
    public static func seconds(forDecimalYear y: Double) -> Double {
        switch y {
        case ..<(-500):
            let u = (y - 1820.0) / 100.0
            return -20.0 + 32.0 * u * u

        case (-500)..<500:
            let u = y / 100.0
            return poly(u, [10583.6, -1014.41, 33.78311, -5.952053,
                            -0.1798452, 0.022174192, 0.0090316521])

        case 500..<1600:
            let u = (y - 1000.0) / 100.0
            return poly(u, [1574.2, -556.01, 71.23472, 0.319781,
                            -0.8503463, -0.005050998, 0.0083572073])

        case 1600..<1700:
            let t = y - 1600.0
            return 120.0 - 0.9808 * t - 0.01532 * t * t + (t * t * t) / 7129.0

        case 1700..<1800:
            let t = y - 1700.0
            return poly(t, [8.83, 0.1603, -0.0059285, 0.00013336, -1.0 / 1_174_000.0])

        case 1800..<1860:
            let t = y - 1800.0
            return poly(t, [13.72, -0.332447, 0.0068612, 0.0041116, -0.00037436,
                            0.0000121272, -0.0000001699, 0.000000000875])

        case 1860..<1900:
            let t = y - 1860.0
            return poly(t, [7.62, 0.5737, -0.251754, 0.01680668,
                            -0.0004473624, 1.0 / 233_174.0])

        case 1900..<1920:
            let t = y - 1900.0
            return poly(t, [-2.79, 1.494119, -0.0598939, 0.0061966, -0.000197])

        case 1920..<1941:
            let t = y - 1920.0
            return poly(t, [21.20, 0.84493, -0.076100, 0.0020936])

        case 1941..<1961:
            let t = y - 1950.0
            return 29.07 + 0.407 * t - (t * t) / 233.0 + (t * t * t) / 2547.0

        case 1961..<1986:
            let t = y - 1975.0
            return 45.45 + 1.067 * t - (t * t) / 260.0 - (t * t * t) / 718.0

        case 1986..<2005:
            let t = y - 2000.0
            return poly(t, [63.86, 0.3345, -0.060374, 0.0017275,
                            0.000651814, 0.00002373599])

        case 2005..<2050:
            let t = y - 2000.0
            return 62.92 + 0.32217 * t + 0.005589 * t * t

        case 2050..<2150:
            let u = (y - 1820.0) / 100.0
            return -20.0 + 32.0 * u * u - 0.5628 * (2150.0 - y)

        default: // y >= 2150
            let u = (y - 1820.0) / 100.0
            return -20.0 + 32.0 * u * u
        }
    }

    // MARK: UT ⇄ TD conversion

    /// Convert a Universal-Time Julian Day to dynamical time: TD = UT + ΔT.
    public static func dynamicalTime(fromUniversalTime ut: JulianDay) -> JulianDay {
        JulianDay(ut.value + seconds(at: ut) / 86400.0)
    }

    /// Convert a dynamical-time Julian Day to Universal Time: UT = TD − ΔT.
    ///
    /// (ΔT is evaluated at the supplied instant; since ΔT changes by far less than
    /// itself over a span of ΔT, this is exact to well under a millisecond.)
    public static func universalTime(fromDynamicalTime td: JulianDay) -> JulianDay {
        JulianDay(td.value - seconds(at: td) / 86400.0)
    }

    // MARK: Helpers

    /// Horner evaluation of `coeffs[0] + coeffs[1]·x + coeffs[2]·x² + …`.
    private static func poly(_ x: Double, _ coeffs: [Double]) -> Double {
        var result = 0.0
        for c in coeffs.reversed() { result = result * x + c }
        return result
    }

    /// Decimal year corresponding to a Julian Day, accurate enough to pick the
    /// right ΔT polynomial range (ΔT itself is smooth on the year scale).
    private static func decimalYear(of jd: JulianDay) -> Double {
        2000.0 + (jd.value - JulianDay.j2000.value) / 365.25
    }
}
