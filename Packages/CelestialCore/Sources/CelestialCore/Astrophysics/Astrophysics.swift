import Foundation

/// Derived astrophysical quantities and the physical constants behind them.
///
/// Pure functions over published laws — no catalog or UI dependencies — so they
/// stay `Sendable` and unit-testable against textbook values. These turn the raw
/// columns a catalog gives us (luminosity, colour-derived temperature, parallax
/// distance) into the quantities a curious user actually wants: how big is it,
/// how far, how long ago did this light leave.
///
/// Sources (mirrored in the app's About → Sources screen):
/// - Stefan–Boltzmann law (derived stellar radius from luminosity + temperature).
/// - IAU 2015 nominal solar values (effective temperature, used as the comparison
///   anchor).
public enum Astrophysics {

    // MARK: Constants

    /// Light-years per parsec (1 pc = 3.2616 ly).
    public static let lightYearsPerParsec = 3.2616

    /// The Sun's effective surface temperature, in kelvin (IAU 2015 nominal value,
    /// T☉ = 5772 K). The anchor for "hotter/cooler than the Sun" comparisons.
    public static let solarEffectiveTemperatureK = 5772.0

    // MARK: Conversions

    /// Distance in light-years for a distance given in parsecs.
    public static func lightYears(fromParsecs parsecs: Double) -> Double {
        parsecs * lightYearsPerParsec
    }

    /// How long ago, in years, the light now arriving from an object left it —
    /// numerically the distance in light-years.
    public static func lightTravelYears(fromParsecs parsecs: Double) -> Double {
        lightYears(fromParsecs: parsecs)
    }

    // MARK: Planet comparisons

    /// Surface gravity relative to Earth's, from a planet's mass and radius (both in
    /// Earth units): g/g⊕ = (M/M⊕) / (R/R⊕)². The relatable "you'd weigh this much"
    /// figure. `nil` for non-positive inputs.
    public static func surfaceGravityEarths(massEarth: Double, radiusEarth: Double) -> Double? {
        guard massEarth > 0, radiusEarth > 0 else { return nil }
        return massEarth / (radiusEarth * radiusEarth)
    }

    /// Kelvin → degrees Celsius.
    public static func celsius(fromKelvin kelvin: Double) -> Double { kelvin - 273.15 }

    // MARK: Derived radius (Stefan–Boltzmann)

    /// A star's radius in solar radii, derived from its luminosity (in solar
    /// luminosities) and effective temperature (kelvin) via the Stefan–Boltzmann
    /// law:  L/L☉ = (R/R☉)² · (T/T☉)⁴, so  R/R☉ = √(L/L☉) · (T☉/T)².
    ///
    /// Returns `nil` for non-positive inputs. Accuracy is only as good as the
    /// inputs — luminosity and a colour-derived temperature — so treat it as an
    /// order-of-magnitude guide, excellent for "would swallow Mars" intuition,
    /// not a measured radius.
    public static func stellarRadiusSolar(luminositySolar: Double, temperatureKelvin: Double) -> Double? {
        guard luminositySolar > 0, temperatureKelvin > 0 else { return nil }
        let tempRatio = solarEffectiveTemperatureK / temperatureKelvin
        return luminositySolar.squareRoot() * tempRatio * tempRatio
    }
}
