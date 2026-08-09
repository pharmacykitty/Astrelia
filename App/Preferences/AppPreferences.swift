import Foundation
import SwiftUI

/// The app's persisted scalar preferences (docs/preferences-spec.md) — one
/// injected `@Observable` store over `UserDefaults`, not scattered
/// `@AppStorage`. Every property writes through on `didSet`; getters fall back
/// to the hardcoded defaults on first launch (no migration needed). Keys are
/// namespaced (`pref.…`) so `reset()` can clear exactly this layer, and a
/// schema-version key lets future migrations branch.
///
/// Deliberately NOT persisted (spec): AR calibration offsets (session-specific),
/// the time-scrubber offset (returns to "now"), any camera state.
@MainActor
@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    @ObservationIgnored private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store

        skyModeAR = store.bool(forKey: K.skyModeAR)
        fieldOfView = store.object(forKey: K.fieldOfView) as? Double ?? 65
        var f = SkyFilters()
        f.showStars = store.object(forKey: K.showStars) as? Bool ?? f.showStars
        f.magnitudeLimit = store.object(forKey: K.magnitudeLimit) as? Double ?? f.magnitudeLimit
        f.showLabels = store.object(forKey: K.showLabels) as? Bool ?? f.showLabels
        f.showConstellations = store.object(forKey: K.showConstellations) as? Bool ?? f.showConstellations
        f.showSunMoon = store.object(forKey: K.showSunMoon) as? Bool ?? f.showSunMoon
        f.showEcliptic = store.object(forKey: K.showEcliptic) as? Bool ?? f.showEcliptic
        f.showBelowHorizon = store.object(forKey: K.showBelowHorizon) as? Bool ?? f.showBelowHorizon
        f.showColourKey = store.object(forKey: K.showColourKey) as? Bool ?? f.showColourKey
        skyFilters = f
        galaxyMilkyWay = store.object(forKey: K.galaxyMilkyWay) as? Bool ?? true
        galaxyHostsOnly = store.bool(forKey: K.galaxyHostsOnly)
        temperatureUnit = TemperatureUnit(rawValue: store.string(forKey: K.temperatureUnit) ?? "") ?? .celsius
        distanceUnit = DistanceUnit(rawValue: store.string(forKey: K.distanceUnit) ?? "") ?? .kilometres
        largeDistanceUnit = LargeDistanceUnit(rawValue: store.string(forKey: K.largeDistanceUnit) ?? "") ?? .lightYears
        useHomeFallback = store.bool(forKey: K.useHomeFallback)
        homeLatitude = store.object(forKey: K.homeLatitude) as? Double
        homeLongitude = store.object(forKey: K.homeLongitude) as? Double
        homeName = store.string(forKey: K.homeName)
        respectReduceMotion = store.object(forKey: K.respectReduceMotion) as? Bool ?? true

        if store.object(forKey: K.schemaVersion) == nil { store.set(1, forKey: K.schemaVersion) }
    }

    // MARK: Sky
    var skyModeAR: Bool { didSet { store.set(skyModeAR, forKey: K.skyModeAR) } }
    var fieldOfView: Double { didSet { store.set(fieldOfView, forKey: K.fieldOfView) } }
    var skyFilters: SkyFilters {
        didSet {
            store.set(skyFilters.showStars, forKey: K.showStars)
            store.set(skyFilters.magnitudeLimit, forKey: K.magnitudeLimit)
            store.set(skyFilters.showLabels, forKey: K.showLabels)
            store.set(skyFilters.showConstellations, forKey: K.showConstellations)
            store.set(skyFilters.showSunMoon, forKey: K.showSunMoon)
            store.set(skyFilters.showEcliptic, forKey: K.showEcliptic)
            store.set(skyFilters.showBelowHorizon, forKey: K.showBelowHorizon)
            store.set(skyFilters.showColourKey, forKey: K.showColourKey)
        }
    }

    // MARK: Galaxy Map
    var galaxyMilkyWay: Bool { didSet { store.set(galaxyMilkyWay, forKey: K.galaxyMilkyWay) } }
    var galaxyHostsOnly: Bool { didSet { store.set(galaxyHostsOnly, forKey: K.galaxyHostsOnly) } }

    // MARK: Units
    var temperatureUnit: TemperatureUnit { didSet { store.set(temperatureUnit.rawValue, forKey: K.temperatureUnit) } }
    var distanceUnit: DistanceUnit { didSet { store.set(distanceUnit.rawValue, forKey: K.distanceUnit) } }
    var largeDistanceUnit: LargeDistanceUnit { didSet { store.set(largeDistanceUnit.rawValue, forKey: K.largeDistanceUnit) } }

    // MARK: Home location (fallback observer when live location is unavailable)
    var useHomeFallback: Bool { didSet { store.set(useHomeFallback, forKey: K.useHomeFallback) } }
    var homeLatitude: Double? { didSet { setOrRemove(homeLatitude, K.homeLatitude) } }
    var homeLongitude: Double? { didSet { setOrRemove(homeLongitude, K.homeLongitude) } }
    var homeName: String? { didSet { setOrRemove(homeName, K.homeName) } }

    // MARK: Motion (storage for the accessibility spec's override)
    var respectReduceMotion: Bool { didSet { store.set(respectReduceMotion, forKey: K.respectReduceMotion) } }

    var hasHome: Bool { homeLatitude != nil && homeLongitude != nil }

    /// Clear the whole `pref.` namespace and reload the built-in defaults.
    func reset() {
        for key in store.dictionaryRepresentation().keys where key.hasPrefix("pref.") {
            store.removeObject(forKey: key)
        }
        let fresh = AppPreferences(store: store)
        skyModeAR = fresh.skyModeAR
        fieldOfView = fresh.fieldOfView
        skyFilters = fresh.skyFilters
        galaxyMilkyWay = fresh.galaxyMilkyWay
        galaxyHostsOnly = fresh.galaxyHostsOnly
        temperatureUnit = fresh.temperatureUnit
        distanceUnit = fresh.distanceUnit
        largeDistanceUnit = fresh.largeDistanceUnit
        useHomeFallback = fresh.useHomeFallback
        homeLatitude = fresh.homeLatitude
        homeLongitude = fresh.homeLongitude
        homeName = fresh.homeName
        respectReduceMotion = fresh.respectReduceMotion
    }

    private func setOrRemove(_ value: Any?, _ key: String) {
        if let value { store.set(value, forKey: key) } else { store.removeObject(forKey: key) }
    }

    /// Namespaced keys — never reuse a key for a changed type (forward-compat).
    private enum K {
        static let schemaVersion = "pref.schemaVersion"
        static let skyModeAR = "pref.sky.modeAR"
        static let fieldOfView = "pref.sky.fieldOfView"
        static let showStars = "pref.sky.filters.showStars"
        static let magnitudeLimit = "pref.sky.filters.magnitudeLimit"
        static let showLabels = "pref.sky.filters.showLabels"
        static let showConstellations = "pref.sky.filters.showConstellations"
        static let showSunMoon = "pref.sky.filters.showSunMoon"
        static let showEcliptic = "pref.sky.filters.showEcliptic"
        static let showBelowHorizon = "pref.sky.filters.showBelowHorizon"
        static let showColourKey = "pref.sky.filters.showColourKey"
        static let galaxyMilkyWay = "pref.galaxy.showMilkyWay"
        static let galaxyHostsOnly = "pref.galaxy.hostsOnly"
        static let temperatureUnit = "pref.units.temperature"
        static let distanceUnit = "pref.units.distance"
        static let largeDistanceUnit = "pref.units.largeDistance"
        static let useHomeFallback = "pref.location.useHomeFallback"
        static let homeLatitude = "pref.location.home.latitude"
        static let homeLongitude = "pref.location.home.longitude"
        static let homeName = "pref.location.home.name"
        static let respectReduceMotion = "pref.motion.respectReduceMotion"
    }
}
