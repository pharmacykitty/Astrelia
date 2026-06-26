import Foundation

/// Ingestion for the HYG database (HYG = Hipparcos + Yale Bright Star + Gliese),
/// astronexus' public-domain merged star catalog.
///
/// Columns are resolved by header *name* (not fixed position), so this tolerates
/// the small column-order differences between HYG versions (v3 / v4.x).
/// Right ascension is given in hours and declination in degrees; distances are in
/// parsecs, with `100000` used as a sentinel for "distance unknown".
public enum HYGCatalog {
    public enum ParseError: Error, Equatable {
        case missingHeader
        case missingColumn(String)
    }

    /// HYG's sentinel value (parsecs) meaning "no reliable distance".
    static let unknownDistanceSentinel = 100_000.0

    public static func parse(csv string: String) throws -> [Star] {
        try parse(csv: Data(string.utf8))
    }

    public static func parse(csv data: Data) throws -> [Star] {
        var columns: [String: Int]?
        var stars: [Star] = []
        stars.reserveCapacity(120_000)

        try CSV.parseRecords(data) { record in
            guard let map = columns else {
                var built: [String: Int] = [:]
                for (i, name) in record.enumerated() {
                    built[name.trimmingCharacters(in: .whitespaces).lowercased()] = i
                }
                for required in ["id", "ra", "dec", "mag"] where built[required] == nil {
                    throw ParseError.missingColumn(required)
                }
                columns = built
                return
            }
            if let star = Star(hygRecord: record, columns: map) {
                stars.append(star)
            }
        }

        guard columns != nil else { throw ParseError.missingHeader }
        return stars
    }
}

extension Star {
    /// Builds a `Star` from a single HYG record using a header→index map.
    /// Returns `nil` for rows without a usable `id` (e.g. blank lines).
    init?(hygRecord record: [String], columns: [String: Int]) {
        func raw(_ name: String) -> String? {
            guard let i = columns[name], i < record.count else { return nil }
            let value = record[i]
            return value.isEmpty ? nil : value
        }
        func number(_ name: String) -> Double? { raw(name).flatMap(Double.init) }
        func integer(_ name: String) -> Int? { raw(name).flatMap { Int($0) } }

        guard let id = integer("id") else { return nil }

        let rightAscensionHours = number("ra") ?? 0
        let declinationDegrees = number("dec") ?? 0
        let magnitude = number("mag") ?? .greatestFiniteMagnitude

        let rawDistance = number("dist")
        let distance: Double? = {
            guard let d = rawDistance, d < HYGCatalog.unknownDistanceSentinel else { return nil }
            return d
        }()

        var position: Vector3?
        if distance != nil, let x = number("x"), let y = number("y"), let z = number("z") {
            position = Vector3(x: x, y: y, z: z)
        }

        self.init(
            id: id,
            hipparcos: integer("hip"),
            henryDraper: integer("hd"),
            harvardRevised: integer("hr"),
            gliese: raw("gl"),
            properName: raw("proper"),
            bayerFlamsteed: raw("bf"),
            constellation: raw("con"),
            equatorial: EquatorialCoordinates(
                rightAscension: .hours(rightAscensionHours),
                declination: .degrees(declinationDegrees)
            ),
            distanceParsecs: distance,
            position: position,
            apparentMagnitude: magnitude,
            absoluteMagnitude: number("absmag"),
            spectralType: raw("spect"),
            colorIndex: number("ci"),
            luminosity: number("lum")
        )
    }
}
