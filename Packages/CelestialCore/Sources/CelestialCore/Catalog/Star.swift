/// A single star, as modelled from a catalog row (currently HYG).
///
/// Equatorial coordinates are J2000.0. Distances and rectangular positions are in
/// parsecs; `position` uses the equatorial frame with the Sun at the origin and is
/// `nil` when the catalog has no reliable distance (see `distanceParsecs`).
public struct Star: Sendable, Hashable, Identifiable {
    /// HYG database id (stable within a catalog version).
    public let id: Int

    // Cross-catalog identifiers (any may be absent).
    public var hipparcos: Int?
    public var henryDraper: Int?
    public var harvardRevised: Int?
    public var gliese: String?

    // Names.
    public var properName: String?      // e.g. "Sirius"
    public var bayerFlamsteed: String?  // e.g. "9Alp CMa"
    public var constellation: String?   // 3-letter abbreviation, e.g. "CMa"

    /// J2000.0 right ascension / declination.
    public var equatorial: EquatorialCoordinates

    /// Distance from the Sun in parsecs, or `nil` if unknown.
    public var distanceParsecs: Double?
    /// Rectangular position (parsecs, equatorial, Sun at origin); `nil` if distance unknown.
    public var position: Vector3?

    /// Apparent visual magnitude (lower = brighter).
    public var apparentMagnitude: Double
    /// Absolute visual magnitude.
    public var absoluteMagnitude: Double?
    /// Spectral type, e.g. "A0m...".
    public var spectralType: String?
    /// Color index B−V (proxy for temperature/color).
    public var colorIndex: Double?
    /// Luminosity relative to the Sun.
    public var luminosity: Double?

    public init(
        id: Int,
        hipparcos: Int? = nil,
        henryDraper: Int? = nil,
        harvardRevised: Int? = nil,
        gliese: String? = nil,
        properName: String? = nil,
        bayerFlamsteed: String? = nil,
        constellation: String? = nil,
        equatorial: EquatorialCoordinates,
        distanceParsecs: Double? = nil,
        position: Vector3? = nil,
        apparentMagnitude: Double,
        absoluteMagnitude: Double? = nil,
        spectralType: String? = nil,
        colorIndex: Double? = nil,
        luminosity: Double? = nil
    ) {
        self.id = id
        self.hipparcos = hipparcos
        self.henryDraper = henryDraper
        self.harvardRevised = harvardRevised
        self.gliese = gliese
        self.properName = properName
        self.bayerFlamsteed = bayerFlamsteed
        self.constellation = constellation
        self.equatorial = equatorial
        self.distanceParsecs = distanceParsecs
        self.position = position
        self.apparentMagnitude = apparentMagnitude
        self.absoluteMagnitude = absoluteMagnitude
        self.spectralType = spectralType
        self.colorIndex = colorIndex
        self.luminosity = luminosity
    }
}
