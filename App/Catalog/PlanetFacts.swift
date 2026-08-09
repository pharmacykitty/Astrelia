import Foundation
import CelestialCore

/// Relatable, human-anchored facts for a planet — the "numbers → intuition" layer
/// for worlds, mirroring `StarFacts`. Everything is phrased against things people
/// know: Earth, Jupiter, your own weight, degrees you can feel, the length of a
/// year. Only the facts derivable from the data are returned.
enum PlanetFacts {

    // Reference constants (Earth units).
    private static let jupiterRadiusEarth = 11.21
    private static let jupiterMassEarth = 317.8

    @MainActor
    static func relatableFacts(for planet: Exoplanet, in system: PlanetarySystem,
                               now: Date = Date()) -> [String] {
        var facts: [String] = []
        if let s = sizeSentence(planet) { facts.append(s) }
        if let s = gravitySentence(planet) { facts.append(s) }
        if let s = temperatureSentence(planet) { facts.append(s) }
        if let s = yearSentence(planet, in: system) { facts.append(s) }
        if let s = habitableZoneSentence(planet, in: system) { facts.append(s) }
        if let s = distanceSentence(system, now: now) { facts.append(s) }
        if let s = discoverySentence(planet) { facts.append(s) }
        return facts
    }

    /// "About 1.4× the width of Earth." / "Roughly Jupiter's size (11× Earth's)."
    static func sizeSentence(_ planet: Exoplanet) -> String? {
        guard let r = planet.radiusEarth, r > 0 else {
            guard let m = planet.massEarth, m > 0 else { return nil }
            return "About \(num(m))× the mass of Earth."
        }
        if r >= 6 {
            return "A giant — about \(num(r / jupiterRadiusEarth))× the width of Jupiter (\(num(r))× Earth's)."
        }
        return "About \(num(r))× the width of Earth."
    }

    /// "You'd weigh about 2.2× as much as on Earth." / "...only 38% of your Earth weight."
    static func gravitySentence(_ planet: Exoplanet) -> String? {
        guard let m = planet.massEarth, let r = planet.radiusEarth,
              let g = Astrophysics.surfaceGravityEarths(massEarth: m, radiusEarth: r) else { return nil }
        if g >= 1.1 { return "You'd weigh about \(num(g))× as much as you do on Earth." }
        if g <= 0.9 { return "You'd weigh only about \(Int((g * 100).rounded()))% of your Earth weight." }
        return "Surface gravity is close to Earth's."
    }

    /// "Estimated temperature ≈ 15°C — about as mild as Earth." / "…hot enough to melt lead."
    /// MainActor: the displayed unit follows Settings; the "feel" flavour keys
    /// off °C internally regardless of display unit.
    @MainActor
    static func temperatureSentence(_ planet: Exoplanet) -> String? {
        guard let k = planet.equilibriumTempK, k > 0 else { return nil }
        let c = Astrophysics.celsius(fromKelvin: k)
        let base = "Estimated temperature ≈ \(AppPreferences.shared.temperatureUnit.format(kelvin: k))"
        let flavour: String
        switch c {
        case 600...: flavour = " — hot enough to melt lead."
        case 100..<600: flavour = " — far past the boiling point of water."
        case 0..<100: flavour = " — in the range where water is liquid."
        case (-50)..<0: flavour = " — a deep freeze, colder than Antarctica."
        default: flavour = " — frigid, hundreds of degrees below freezing."
        }
        return base + flavour
    }

    /// "A year here — one orbit — lasts just 18 hours." / "…lasts 88 days." / "…11.9 Earth-years."
    static func yearSentence(_ planet: Exoplanet, in system: PlanetarySystem) -> String? {
        guard let p = planet.periodDays, p > 0 else { return nil }
        if p < 1 { return "A year here — one full orbit — lasts just \(Int((p * 24).rounded())) hours." }
        if p < 600 { return "A year here — one orbit around its star — lasts \(Int(p.rounded())) days." }
        return "A year here lasts \(num(p / 365.25)) Earth-years."
    }

    /// Only stated when the planet actually falls in the conservative habitable zone.
    static func habitableZoneSentence(_ planet: Exoplanet, in system: PlanetarySystem) -> String? {
        guard let lum = system.luminositySun, lum > 0,
              let a = system.semiMajorAxis(of: planet), a > 0 else { return nil }
        let inner = (lum / 1.1).squareRoot(), outer = (lum / 0.53).squareRoot()
        guard a >= inner, a <= outer else { return nil }
        return "Orbits within the star's habitable zone — the band where liquid water could exist."
    }

    /// "Its starlight is 41 light-years old — it left around the year 1985."
    static func distanceSentence(_ system: PlanetarySystem, now: Date = Date()) -> String? {
        guard let pc = system.distanceParsecs, pc > 0 else { return nil }
        let years = Astrophysics.lightTravelYears(fromParsecs: pc)
        let currentYear = Calendar.current.component(.year, from: now)
        let whole = Int(years.rounded())
        if whole < 1 { return nil }
        if whole <= 4000 {
            return "Its starlight is \(num(years)) light-years old — it left around the year \(currentYear - whole)."
        }
        return "Its starlight has travelled \(num(years)) light-years to reach us."
    }

    /// "Discovered in 2017 by watching it transit its star."
    static func discoverySentence(_ planet: Exoplanet) -> String? {
        guard let method = planet.method else { return nil }
        let how: String
        switch method.lowercased() {
        case let m where m.contains("transit"): how = "by watching it cross (transit) its star"
        case let m where m.contains("radial"): how = "by the star's tiny wobble (radial velocity)"
        case let m where m.contains("imaging"): how = "by direct imaging"
        case let m where m.contains("microlens"): how = "by gravitational microlensing"
        case let m where m.contains("direct observation"): how = "by direct observation"
        default: how = "by the \(method.lowercased()) method"
        }
        if let y = planet.year { return "Discovered in \(y) \(how)." }
        return "Found \(how)."
    }

    private static func num(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}
