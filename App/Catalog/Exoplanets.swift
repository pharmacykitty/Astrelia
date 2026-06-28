import SwiftUI
import Foundation

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
        guard let url = Bundle.main.url(forResource: "exoplanets", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var rows = text.split(separator: "\n", omittingEmptySubsequences: true).makeIterator()
        guard let header = rows.next() else { return [] }
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

        return order.compactMap { host -> PlanetarySystem? in
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
                planets: planets)
        }
    }
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
