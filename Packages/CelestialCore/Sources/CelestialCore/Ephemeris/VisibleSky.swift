import Foundation

/// A body's visibility for an observer at an instant: where it is in the sky now,
/// whether it's up, and when it next rises or sets. The data behind a "what's in the
/// sky tonight" feed. Pure value type; UI maps it to presentation.
public struct SkyBodyStatus: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable { case sun, moon, planet }

    public var id: String { name }
    public let name: String
    public let kind: Kind
    public let altitude: Angle
    public let azimuth: Angle
    public let isUp: Bool
    public let nextRise: Date?
    public let nextSet: Date?
}

/// Computes the current visibility of the Sun, Moon, and naked-eye planets for an
/// observer. Built on the same ephemeris and transforms as the planetarium, so the
/// "tonight" feed and the live sky agree.
public enum VisibleSky {

    /// The planets visible to the unaided eye (Uranus/Neptune excluded).
    public static let nakedEyePlanets: [Planet] = [.mercury, .venus, .mars, .jupiter, .saturn]

    public static func status(at location: GeographicLocation, date: Date = Date()) -> [SkyBodyStatus] {
        var out: [SkyBodyStatus] = [
            bodyStatus(name: "Sun", kind: .sun, at: location, date: date) { Sun.position(at: $0) },
            bodyStatus(name: "Moon", kind: .moon, at: location, date: date) { Moon.position(at: $0) },
        ]
        for planet in nakedEyePlanets {
            out.append(bodyStatus(name: displayName(planet), kind: .planet, at: location, date: date) {
                Planets.position(planet, at: $0)
            })
        }
        return out
    }

    /// The Moon's phase at `date` — convenience so the feed needn't reach for `Moon`.
    public static func moonPhase(at date: Date = Date()) -> MoonPhase {
        Moon.phase(at: JulianDay(date))
    }

    private static func bodyStatus(name: String, kind: SkyBodyStatus.Kind,
                                   at location: GeographicLocation, date: Date,
                                   equatorial: @escaping (JulianDay) -> EquatorialCoordinates) -> SkyBodyStatus {
        func altitude(_ d: Date) -> Angle {
            let jd = JulianDay(d)
            return CoordinateTransform.horizontal(equatorial(jd), at: location, time: jd).altitude
        }
        let jd = JulianDay(date)
        let now = CoordinateTransform.horizontal(equatorial(jd), at: location, time: jd)
        let up = now.altitude.degrees > RiseSet.standardHorizon.degrees
        // 5-minute sampling (interpolated) keeps the whole feed well under a second
        // while staying accurate to a minute or two for display.
        return SkyBodyStatus(
            name: name, kind: kind, altitude: now.altitude, azimuth: now.azimuth, isUp: up,
            nextRise: RiseSet.next(.rise, from: date, step: 300, altitude: altitude),
            nextSet: RiseSet.next(.set, from: date, step: 300, altitude: altitude))
    }

    private static func displayName(_ planet: Planet) -> String {
        switch planet {
        case .mercury: "Mercury"; case .venus: "Venus"; case .mars: "Mars"
        case .jupiter: "Jupiter"; case .saturn: "Saturn"; case .uranus: "Uranus"
        case .neptune: "Neptune"; case .pluto: "Pluto"
        }
    }
}
