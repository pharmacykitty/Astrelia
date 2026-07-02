import Foundation
import SwiftData
import CelestialCore
import Astrology

/// A persisted birth chart. We store the **raw inputs** (wall-clock birth time,
/// IANA timezone, coordinates, settings) as the source of truth and recompute
/// the chart on demand — never persist derived longitudes (see
/// `docs/astrology-spec.md`). Historical timezones are handled by resolving the
/// stored IANA identifier through `Calendar`, which uses the tz database.
@Model
final class SavedChart {
    var name: String

    // Wall-clock birth moment at the birth place.
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    /// When false, the birth time is unknown: we cast for local noon and houses
    /// / angles should be treated as unreliable.
    var timeKnown: Bool

    // Birth place.
    var latitude: Double          // degrees, north-positive
    var longitude: Double         // degrees, east-positive
    var timeZoneIdentifier: String
    var placeName: String

    // Chart options.
    var houseSystemRaw: String    // HouseSystem.rawValue
    /// nil ⇒ tropical; otherwise the sidereal `Ayanamsa.rawValue`.
    var siderealAyanamsa: String?

    var createdAt: Date

    init(
        name: String,
        year: Int, month: Int, day: Int, hour: Int, minute: Int,
        timeKnown: Bool,
        latitude: Double, longitude: Double,
        timeZoneIdentifier: String, placeName: String,
        houseSystem: HouseSystem = .placidus,
        zodiac: Zodiac = .tropical
    ) {
        self.name = name
        self.year = year; self.month = month; self.day = day
        self.hour = hour; self.minute = minute
        self.timeKnown = timeKnown
        self.latitude = latitude; self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.placeName = placeName
        self.houseSystemRaw = houseSystem.rawValue
        switch zodiac {
        case .tropical: self.siderealAyanamsa = nil
        case .sidereal(let a): self.siderealAyanamsa = a.rawValue
        }
        self.createdAt = .now
    }
}

// MARK: - Derived chart inputs

extension SavedChart {
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .gmt }

    var houseSystem: HouseSystem { HouseSystem(rawValue: houseSystemRaw) ?? .placidus }

    var zodiac: Zodiac {
        guard let raw = siderealAyanamsa, let a = Ayanamsa(rawValue: raw) else { return .tropical }
        return .sidereal(a)
    }

    var settings: ChartSettings {
        ChartSettings(houseSystem: houseSystem, zodiac: zodiac, bodies: AstroBody.standard)
    }

    var location: GeographicLocation {
        GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
    }

    /// The absolute birth instant, resolving the wall-clock time through the
    /// stored timezone (handles historical DST/offset via the tz database).
    var birthDate: Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = timeKnown ? hour : 12
        comps.minute = timeKnown ? minute : 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    var julianDay: JulianDay { JulianDay(birthDate) }

    /// Recompute the full chart from the stored inputs.
    func makeChart() -> NatalChart {
        NatalChart(at: julianDay, location: location, settings: settings)
    }

    /// "19 Nov 1971, 11:01 · Seattle, WA" — for list rows and chart subtitles.
    var subtitle: String {
        let df = DateFormatter()
        df.dateFormat = timeKnown ? "d MMM yyyy, HH:mm" : "d MMM yyyy"
        df.timeZone = timeZone
        let when = df.string(from: birthDate)
        let place = placeName.isEmpty ? "" : " · \(placeName)"
        return when + place + (timeKnown ? "" : " · time unknown")
    }
}
