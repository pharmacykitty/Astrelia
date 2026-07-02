import CelestialCore
import Foundation

/// User-chosen chart options.
public struct ChartSettings: Sendable, Hashable {
    public var houseSystem: HouseSystem
    public var zodiac: Zodiac
    public var orbs: OrbPolicy
    /// Bodies to include. Defaults to the ten planets plus the lunar nodes.
    public var bodies: [AstroBody]

    public init(
        houseSystem: HouseSystem = .placidus,
        zodiac: Zodiac = .tropical,
        orbs: OrbPolicy = .default,
        bodies: [AstroBody] = AstroBody.standard
    ) {
        self.houseSystem = houseSystem
        self.zodiac = zodiac
        self.orbs = orbs
        self.bodies = bodies
    }

    public static let `default` = ChartSettings()
}

/// A computed chart for one instant and place: body positions, houses, aspects.
///
/// Built from raw inputs (time + location + settings) so persistence can store
/// the inputs and recompute — never store derived longitudes as source of truth
/// (see `docs/astrology-spec.md`).
public struct NatalChart: Sendable, Hashable {
    public let julianDay: JulianDay
    public let location: GeographicLocation
    public let settings: ChartSettings

    public let angles: ChartAngles
    public let houses: HouseCusps
    public let positions: [BodyPosition]
    public let aspects: [Aspect]
    /// Part of Fortune longitude (in the chart's zodiac frame), if Sun & Moon
    /// were both available. Derived: day charts ASC + Moon − Sun; night flips.
    public let partOfFortune: Angle?

    /// Bodies the provider could not supply (empty with the default ephemeris;
    /// non-empty only if a custom provider omits something).
    public let missingBodies: [AstroBody]

    public init(
        at jd: JulianDay,
        location: GeographicLocation,
        settings: ChartSettings = .default,
        ephemeris: any EphemerisProvider = CelestialCoreEphemeris()
    ) {
        self.julianDay = jd
        self.location = location
        self.settings = settings

        let angles = ChartAngles(at: jd, location: location)
        self.angles = angles
        self.houses = Houses.cusps(settings.houseSystem, angles: angles)

        var positions: [BodyPosition] = []
        var missing: [AstroBody] = []
        for body in settings.bodies {
            if let p = ephemeris.position(of: body, at: jd, zodiac: settings.zodiac) {
                positions.append(p)
            } else {
                missing.append(body)
            }
        }
        self.positions = positions
        self.missingBodies = missing
        self.aspects = AspectFinder.aspects(among: positions, policy: settings.orbs)

        // Part of Fortune (needs Sun, Moon, Ascendant). The Ascendant is in the
        // tropical frame; convert it to the chart frame to stay consistent.
        let sun = positions.first { $0.body == .sun }
        let moon = positions.first { $0.body == .moon }
        if let sun, let moon {
            let ascFrame = settings.zodiac.longitude(fromTropical: angles.ascendant, at: jd)
            let isDay = NatalChart.isDayChart(sunLongitude: sun.longitude, ascendant: ascFrame)
            let lon = isDay
                ? ascFrame + moon.longitude - sun.longitude
                : ascFrame + sun.longitude - moon.longitude
            self.partOfFortune = lon.normalized
        } else {
            self.partOfFortune = nil
        }
    }

    /// The position record for a body, if present.
    public func position(of body: AstroBody) -> BodyPosition? {
        positions.first { $0.body == body }
    }

    /// The house a body occupies (1...12), if present.
    public func house(of body: AstroBody) -> Int? {
        guard let p = position(of: body) else { return nil }
        return houses.house(of: p.longitude)
    }

    /// Day vs night chart: day when the Sun is above the horizon, i.e. in houses
    /// 7–12, which (for this purpose) means the Sun is within 180° *above* the
    /// Ascendant→Descendant axis. Standard sect rule.
    static func isDayChart(sunLongitude: Angle, ascendant: Angle) -> Bool {
        // Sun above horizon when it lies between the Descendant and Ascendant
        // going through the MC — i.e. 0..180 measured from the Descendant.
        let descendant = (ascendant + .degrees(180)).normalized
        var fromDesc = (sunLongitude.normalized.degrees - descendant.degrees)
            .truncatingRemainder(dividingBy: 360.0)
        if fromDesc < 0 { fromDesc += 360 }
        return fromDesc < 180
    }
}
