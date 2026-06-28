import Foundation

/// Nutation — the short-period nodding of Earth's rotation axis, driven mainly by
/// the Moon, superimposed on the long-term precession.
///
/// Computes the nutation in longitude (Δψ) and the nutation in obliquity (Δε)
/// from the principal periodic terms of the IAU 1980 series (Meeus,
/// *Astronomical Algorithms*, 2nd ed., ch. 22, table 22.A). This abbreviated
/// series — the largest ~37 terms — reproduces Meeus' worked example 22.a to
/// better than 0.01″, far finer than a planetarium needs.
///
/// Δψ turns *mean* sidereal time into *apparent* sidereal time (via the equation
/// of the equinoxes); Δε turns *mean* obliquity into *true* obliquity.
public enum Nutation {
    /// One periodic term: the integer multipliers of the five fundamental
    /// arguments (D, M, M′, F, Ω) and the series coefficients. The sine
    /// coefficients feed Δψ and the cosine coefficients feed Δε; each is a
    /// (constant, ·T) pair in units of 0.0001″ (T = Julian centuries from J2000).
    private struct Term {
        let d, m, mp, f, omega: Double
        let psiConst, psiT: Double   // Δψ, sine, units 0.0001″
        let epsConst, epsT: Double   // Δε, cosine, units 0.0001″
    }

    // Meeus table 22.A — the 37 largest terms.
    private static let terms: [Term] = [
        Term(d:  0, m:  0, mp:  0, f:  0, omega:  1, psiConst: -171996, psiT: -174.2, epsConst:  92025, epsT:  8.9),
        Term(d: -2, m:  0, mp:  0, f:  2, omega:  2, psiConst:  -13187, psiT:   -1.6, epsConst:   5736, epsT: -3.1),
        Term(d:  0, m:  0, mp:  0, f:  2, omega:  2, psiConst:   -2274, psiT:   -0.2, epsConst:    977, epsT: -0.5),
        Term(d:  0, m:  0, mp:  0, f:  0, omega:  2, psiConst:    2062, psiT:    0.2, epsConst:   -895, epsT:  0.5),
        Term(d:  0, m:  1, mp:  0, f:  0, omega:  0, psiConst:    1426, psiT:   -3.4, epsConst:     54, epsT: -0.1),
        Term(d:  0, m:  0, mp:  1, f:  0, omega:  0, psiConst:     712, psiT:    0.1, epsConst:     -7, epsT:  0.0),
        Term(d: -2, m:  1, mp:  0, f:  2, omega:  2, psiConst:    -517, psiT:    1.2, epsConst:    224, epsT: -0.6),
        Term(d:  0, m:  0, mp:  0, f:  2, omega:  1, psiConst:    -386, psiT:   -0.4, epsConst:    200, epsT:  0.0),
        Term(d:  0, m:  0, mp:  1, f:  2, omega:  2, psiConst:    -301, psiT:    0.0, epsConst:    129, epsT: -0.1),
        Term(d: -2, m: -1, mp:  0, f:  2, omega:  2, psiConst:     217, psiT:   -0.5, epsConst:    -95, epsT:  0.3),
        Term(d: -2, m:  0, mp:  1, f:  0, omega:  0, psiConst:    -158, psiT:    0.0, epsConst:      0, epsT:  0.0),
        Term(d: -2, m:  0, mp:  0, f:  2, omega:  1, psiConst:     129, psiT:    0.1, epsConst:    -70, epsT:  0.0),
        Term(d:  0, m:  0, mp: -1, f:  2, omega:  2, psiConst:     123, psiT:    0.0, epsConst:    -53, epsT:  0.0),
        Term(d:  2, m:  0, mp:  0, f:  0, omega:  0, psiConst:      63, psiT:    0.0, epsConst:      0, epsT:  0.0),
        Term(d:  0, m:  0, mp:  1, f:  0, omega:  1, psiConst:      63, psiT:    0.1, epsConst:    -33, epsT:  0.0),
        Term(d:  2, m:  0, mp: -1, f:  2, omega:  2, psiConst:     -59, psiT:    0.0, epsConst:     26, epsT:  0.0),
        Term(d:  0, m:  0, mp: -1, f:  0, omega:  1, psiConst:     -58, psiT:   -0.1, epsConst:     32, epsT:  0.0),
        Term(d:  0, m:  0, mp:  1, f:  2, omega:  1, psiConst:     -51, psiT:    0.0, epsConst:     27, epsT:  0.0),
        Term(d: -2, m:  0, mp:  2, f:  0, omega:  0, psiConst:      48, psiT:    0.0, epsConst:      0, epsT:  0.0),
        Term(d:  0, m:  0, mp: -2, f:  2, omega:  1, psiConst:      46, psiT:    0.0, epsConst:    -24, epsT:  0.0),
        Term(d:  2, m:  0, mp:  0, f:  2, omega:  2, psiConst:     -38, psiT:    0.0, epsConst:     16, epsT:  0.0),
        Term(d:  0, m:  0, mp:  2, f:  2, omega:  2, psiConst:     -31, psiT:    0.0, epsConst:     13, epsT:  0.0),
        Term(d:  0, m:  0, mp:  2, f:  0, omega:  0, psiConst:      29, psiT:    0.0, epsConst:      0, epsT:  0.0),
        Term(d: -2, m:  0, mp:  1, f:  2, omega:  2, psiConst:      29, psiT:    0.0, epsConst:    -12, epsT:  0.0),
        Term(d:  0, m:  0, mp:  0, f:  2, omega:  0, psiConst:      26, psiT:    0.0, epsConst:      0, epsT:  0.0),
        Term(d: -2, m:  0, mp:  0, f:  2, omega:  0, psiConst:     -22, psiT:    0.0, epsConst:      0, epsT:  0.0),
        Term(d:  0, m:  0, mp: -1, f:  2, omega:  1, psiConst:      21, psiT:    0.0, epsConst:    -10, epsT:  0.0),
        Term(d:  0, m:  2, mp:  0, f:  0, omega:  0, psiConst:      17, psiT:   -0.1, epsConst:      0, epsT:  0.0),
        Term(d:  2, m:  0, mp: -1, f:  0, omega:  1, psiConst:      16, psiT:    0.0, epsConst:     -8, epsT:  0.0),
        Term(d: -2, m:  2, mp:  0, f:  2, omega:  2, psiConst:     -16, psiT:    0.1, epsConst:      7, epsT:  0.0),
        Term(d:  0, m:  1, mp:  0, f:  0, omega:  1, psiConst:     -15, psiT:    0.0, epsConst:      9, epsT:  0.0),
        Term(d: -2, m:  0, mp:  1, f:  0, omega:  1, psiConst:     -13, psiT:    0.0, epsConst:      7, epsT:  0.0),
        Term(d:  0, m: -1, mp:  0, f:  0, omega:  1, psiConst:     -12, psiT:    0.0, epsConst:      6, epsT:  0.0),
        Term(d:  0, m:  0, mp:  2, f: -2, omega:  0, psiConst:      11, psiT:    0.0, epsConst:      0, epsT:  0.0),
        Term(d:  2, m:  0, mp: -1, f:  2, omega:  1, psiConst:     -10, psiT:    0.0, epsConst:      5, epsT:  0.0),
        Term(d:  2, m:  0, mp:  1, f:  2, omega:  2, psiConst:      -8, psiT:    0.0, epsConst:      3, epsT:  0.0),
        Term(d:  0, m:  1, mp:  0, f:  2, omega:  2, psiConst:       7, psiT:    0.0, epsConst:     -3, epsT:  0.0),
    ]

    /// Nutation in longitude (Δψ) and in obliquity (Δε) at the given instant.
    ///
    /// Meeus evaluates the fundamental arguments in dynamical time; the difference
    /// from UT (a few tens of seconds) is utterly negligible for nutation, so any
    /// reasonable `JulianDay` may be passed.
    public static func nutation(at jd: JulianDay) -> (longitude: Angle, obliquity: Angle) {
        let t = jd.julianCenturiesSinceJ2000

        // Fundamental arguments, in degrees (Meeus eqs. 22.2–22.6):
        // D  — mean elongation of the Moon from the Sun
        // M  — mean anomaly of the Sun (Earth)
        // M′ — mean anomaly of the Moon
        // F  — Moon's argument of latitude
        // Ω  — longitude of the ascending node of the Moon's mean orbit
        let d  = 297.85036 + 445267.111480 * t - 0.0019142 * t * t + t * t * t / 189474.0
        let m  = 357.52772 + 35999.050340 * t - 0.0001603 * t * t - t * t * t / 300000.0
        let mp = 134.96298 + 477198.867398 * t + 0.0086972 * t * t + t * t * t / 56250.0
        let f  = 93.27191 + 483202.017538 * t - 0.0036825 * t * t + t * t * t / 327270.0
        let om = 125.04452 - 1934.136261 * t + 0.0020708 * t * t + t * t * t / 450000.0

        var dPsi = 0.0   // accumulated in units of 0.0001″
        var dEps = 0.0
        for term in terms {
            let arg = Angle.degrees(
                term.d * d + term.m * m + term.mp * mp + term.f * f + term.omega * om
            )
            dPsi += (term.psiConst + term.psiT * t) * arg.sine
            dEps += (term.epsConst + term.epsT * t) * arg.cosine
        }

        // 0.0001″ → degrees → Angle.
        let toAngle: (Double) -> Angle = { .degrees($0 * 0.0001 / 3600.0) }
        return (toAngle(dPsi), toAngle(dEps))
    }

    /// Nutation in longitude, Δψ.
    public static func longitude(at jd: JulianDay) -> Angle { nutation(at: jd).longitude }

    /// Nutation in obliquity, Δε.
    public static func obliquity(at jd: JulianDay) -> Angle { nutation(at: jd).obliquity }
}
