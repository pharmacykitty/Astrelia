import SwiftUI
import Foundation

/// A natural satellite. The NASA archive has no exomoons, so these only appear on
/// the hand-authored Solar System — enough to show moons orbiting their planet.
struct PlanetMoon: Identifiable, Hashable {
    let id: String
    let name: String
    let semiMajorAxisKm: Double   // orbit radius around the host planet
    let radiusKm: Double
    let periodDays: Double
}

/// A confirmed planet (one row of the NASA Exoplanet Archive's default parameter set).
struct Exoplanet: Identifiable, Hashable {
    let id: String              // pl_name
    let name: String
    let semiMajorAxisAU: Double?
    let periodDays: Double?
    let eccentricity: Double?
    let radiusEarth: Double?
    let massEarth: Double?
    let equilibriumTempK: Double?
    let method: String?
    let year: Int?
    var moons: [PlanetMoon] = []

    /// Rough size class for colour/representation.
    enum Kind { case rocky, neptunian, giant, unknown }
    var kind: Kind {
        guard let r = radiusEarth else {
            if let m = massEarth { return m < 2 ? .rocky : (m < 50 ? .neptunian : .giant) }
            return .unknown
        }
        if r < 1.6 { return .rocky }
        if r < 4 { return .neptunian }
        return .giant
    }

    /// A short, human-readable class — "Hot Jupiter", "Super-Earth", etc. — derived
    /// from size and (where known) temperature/orbit. Heuristics drawn from common
    /// exoplanet taxonomy (see About → Sources).
    var classification: String {
        let hot = (equilibriumTempK ?? 0) > 1000
        switch kind {
        case .giant:
            return hot ? "Hot Jupiter — a scorched gas giant" : "Gas giant"
        case .neptunian:
            return hot ? "Hot Neptune" : "Neptune-like world"
        case .rocky:
            if let r = radiusEarth {
                if r < 0.8 { return "Sub-Earth — smaller than our world" }
                if r > 1.25 { return "Super-Earth — a large rocky planet" }
            } else if let m = massEarth, m > 1.5 {
                return "Super-Earth — a large rocky planet"
            }
            return "Terrestrial — a rocky, Earth-size world"
        case .unknown:
            return "Unclassified world"
        }
    }

    /// One-line descriptive summary combining class, orbit and temperature, used on
    /// the planet inspection card.
    func summary(in system: PlanetarySystem) -> String {
        var bits = [classification]
        if let a = system.semiMajorAxis(of: self) {
            bits.append(a < 0.1 ? "hugging its star" : (a > 5 ? "in the far reaches of its system" : "on a \(String(format: "%.2f", a)) AU orbit"))
        }
        if let t = equilibriumTempK {
            bits.append(t > 1000 ? "blisteringly hot (\(Int(t)) K)"
                      : t < 200 ? "frigid (\(Int(t)) K)"
                      : "temperate (\(Int(t)) K)")
        }
        if let y = year { bits.append("discovered \(y)") }
        return bits.joined(separator: ", ") + "."
    }
}

/// A host star and its known planets.
struct PlanetarySystem: Identifiable, Hashable {
    let id: String              // hostname
    let hostName: String
    let hip: Int?
    let hd: Int?
    let distanceParsecs: Double?
    let raDegrees: Double
    let decDegrees: Double
    let spectralType: String?
    let stellarTempK: Double?
    let stellarRadiusSun: Double?
    let stellarMassSun: Double?
    let logLuminositySun: Double?     // NASA `st_lum` is log10(L/Lsun)
    var starCount: Int = 1            // NASA `sy_snum` — binaries/multiples
    let planets: [Exoplanet]

    var luminositySun: Double? { logLuminositySun.map { pow(10, $0) } }
    var distanceLightYears: Double? { distanceParsecs.map { $0 * 3.2616 } }

    /// Semi-major axis for a planet, derived from its period + stellar mass via
    /// Kepler's third law when the archive doesn't give one directly.
    func semiMajorAxis(of planet: Exoplanet) -> Double? {
        if let a = planet.semiMajorAxisAU { return a }
        guard let p = planet.periodDays else { return nil }
        let m = stellarMassSun ?? 1.0
        return cbrt(m * pow(p / 365.25, 2))
    }
}

/// Loads the bundled NASA Exoplanet Archive snapshot once, off the main thread.
@MainActor
@Observable
final class ExoplanetStore {
    private(set) var systems: [PlanetarySystem] = []
    private(set) var byHost: [String: PlanetarySystem] = [:]
    private(set) var byHIP: [Int: PlanetarySystem] = [:]
    private(set) var hostHIPs: Set<Int> = []
    private(set) var isLoading = false

    func loadIfNeeded() {
        guard systems.isEmpty, !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let systems = Self.loadBundled()
            await MainActor.run {
                self.systems = systems
                self.byHost = Dictionary(systems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                var byHIP: [Int: PlanetarySystem] = [:]
                var hips: Set<Int> = []
                for s in systems where s.hip != nil {
                    byHIP[s.hip!] = s
                    hips.insert(s.hip!)
                }
                self.byHIP = byHIP
                self.hostHIPs = hips
                self.isLoading = false
            }
        }
    }

    private nonisolated static func loadBundled() -> [PlanetarySystem] {
        var result: [PlanetarySystem] = [SolarSystem.system]
        guard let url = Bundle.main.url(forResource: "exoplanets", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return result }

        // Split on any newline. NB: `split(separator: "\n")` fails on CRLF files
        // because Swift treats "\r\n" as a single Character, so it finds no "\n".
        var rows = text.split(whereSeparator: \.isNewline).makeIterator()
        guard let header = rows.next() else { return result }
        let columns = parseCSVLine(String(header))
        // Keep the first column of each name; NASA's CSV exports can carry blank
        // trailing headers, and `uniqueKeysWithValues` traps on the duplicate "".
        let index = Dictionary(columns.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func col(_ fields: [String], _ name: String) -> String? {
            guard let i = index[name], i < fields.count, !fields[i].isEmpty else { return nil }
            return fields[i]
        }

        // Group planet rows by host, preserving first-seen order.
        var order: [String] = []
        var grouped: [String: [[String]]] = [:]
        while let line = rows.next() {
            let fields = parseCSVLine(String(line))
            guard let host = col(fields, "hostname") else { continue }
            if grouped[host] == nil { order.append(host) }
            grouped[host, default: []].append(fields)
        }

        result += order.compactMap { host -> PlanetarySystem? in
            guard let group = grouped[host], let first = group.first else { return nil }
            func d(_ f: [String], _ n: String) -> Double? { col(f, n).flatMap(Double.init) }
            func i(_ f: [String], _ n: String) -> Int? { col(f, n).flatMap { Int($0) } }

            let planets = group.map { f in
                Exoplanet(
                    id: col(f, "pl_name") ?? UUID().uuidString,
                    name: col(f, "pl_name") ?? "Planet",
                    semiMajorAxisAU: d(f, "pl_orbsmax"),
                    periodDays: d(f, "pl_orbper"),
                    eccentricity: d(f, "pl_orbeccen"),
                    radiusEarth: d(f, "pl_rade"),
                    massEarth: d(f, "pl_bmasse"),
                    equilibriumTempK: d(f, "pl_eqt"),
                    method: col(f, "method"),
                    year: i(f, "year"))
            }
            .sorted { ($0.semiMajorAxisAU ?? $0.periodDays ?? .greatestFiniteMagnitude)
                    < ($1.semiMajorAxisAU ?? $1.periodDays ?? .greatestFiniteMagnitude) }

            return PlanetarySystem(
                id: host, hostName: host,
                hip: i(first, "hip"), hd: i(first, "hd"),
                distanceParsecs: d(first, "sy_dist"),
                raDegrees: d(first, "ra") ?? 0, decDegrees: d(first, "dec") ?? 0,
                spectralType: col(first, "st_spectype"),
                stellarTempK: d(first, "st_teff"),
                stellarRadiusSun: d(first, "st_rad"),
                stellarMassSun: d(first, "st_mass"),
                logLuminositySun: d(first, "st_lum"),
                starCount: i(first, "snum") ?? 1,
                planets: planets)
        }
        return result
    }
}

/// A hand-authored Sol — the one system where we can show real planets *and* their
/// major moons. Distances/radii are physical (AU, Earth radii, km); the renderer
/// maps them onto its log scales like any other system.
enum SolarSystem {
    static let system = PlanetarySystem(
        id: "Sol", hostName: "Sol",
        hip: nil, hd: nil,
        distanceParsecs: 0, raDegrees: 0, decDegrees: 0,
        spectralType: "G2 V",
        stellarTempK: 5772, stellarRadiusSun: 1, stellarMassSun: 1,
        logLuminositySun: 0,
        starCount: 1,
        planets: planets)

    private static func p(_ name: String, _ a: Double, _ period: Double, _ rEarth: Double,
                          _ mEarth: Double, _ temp: Double, _ moons: [PlanetMoon] = []) -> Exoplanet {
        Exoplanet(id: "Sol \(name)", name: name, semiMajorAxisAU: a, periodDays: period,
                  eccentricity: nil, radiusEarth: rEarth, massEarth: mEarth,
                  equilibriumTempK: temp, method: "Direct observation", year: nil, moons: moons)
    }
    private static func m(_ name: String, _ aKm: Double, _ rKm: Double, _ period: Double) -> PlanetMoon {
        PlanetMoon(id: name, name: name, semiMajorAxisKm: aKm, radiusKm: rKm, periodDays: period)
    }

    private static let planets: [Exoplanet] = [
        p("Mercury", 0.387, 88.0, 0.383, 0.055, 440),
        p("Venus", 0.723, 224.7, 0.949, 0.815, 737),
        p("Earth", 1.0, 365.25, 1.0, 1.0, 288, [
            m("Moon", 384_400, 1737, 27.32)]),
        p("Mars", 1.524, 687.0, 0.532, 0.107, 210, [
            m("Phobos", 9_376, 11, 0.319),
            m("Deimos", 23_463, 6, 1.263)]),
        p("Jupiter", 5.203, 4332.6, 11.21, 317.8, 165, [
            m("Io", 421_700, 1822, 1.769),
            m("Europa", 671_034, 1561, 3.551),
            m("Ganymede", 1_070_412, 2634, 7.155),
            m("Callisto", 1_882_709, 2410, 16.69)]),
        p("Saturn", 9.537, 10759.0, 9.45, 95.16, 134, [
            m("Titan", 1_221_870, 2575, 15.95),
            m("Rhea", 527_108, 764, 4.518),
            m("Enceladus", 238_040, 252, 1.370)]),
        p("Uranus", 19.19, 30688.0, 4.01, 14.54, 76, [
            m("Titania", 435_910, 789, 8.706),
            m("Oberon", 583_520, 761, 13.46)]),
        p("Neptune", 30.07, 60182.0, 3.88, 17.15, 72, [
            m("Triton", 354_759, 1353, 5.877)]),
    ]
}

/// Minimal RFC-4180 line parser (handles quoted fields with embedded commas).
private func parseCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var inQuotes = false
    var iterator = line.makeIterator()
    var pending: Character? = nil
    while let c = pending ?? iterator.next() {
        pending = nil
        if inQuotes {
            if c == "\"" {
                if let next = iterator.next() {
                    if next == "\"" { current.append("\"") } else { inQuotes = false; pending = next }
                } else { inQuotes = false }
            } else { current.append(c) }
        } else if c == "\"" {
            inQuotes = true
        } else if c == "," {
            fields.append(current); current = ""
        } else if c == "\r" {
            // ignore CR
        } else {
            current.append(c)
        }
    }
    fields.append(current)
    return fields
}
