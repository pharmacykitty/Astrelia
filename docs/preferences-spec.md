# User Preferences & Settings — Spec

> Status: **planned, approved for build.** Drafted 2026-06-28 from the full-app review.
> Goal: persist user choices across launches, and add a single app-level **Settings**
> screen. Today the app stores **zero** scalar preferences (a clean sweep finds no
> `UserDefaults`/`AppStorage` anywhere) — every toggle resets on each cold start.

---

## Why

Several surfaces hold state that is *expensive or annoying* to re-set every session:

- **Sky view** (`App/ContentView.swift`): `mode` (Sky/AR), `fieldOfView`, and the whole
  `SkyFilters` struct re-default on launch.
- **Sky filters** (`App/Sky/SkyFilters.swift`): 8 fields — `showStars`, `magnitudeLimit`,
  `showLabels`, `showConstellations`, `showSunMoon`, `showZodiac`, `showBelowHorizon`,
  `showColourKey`.
- **Galaxy Map** (`App/Screens/GalaxyMapView.swift`): `showMilkyWay`, `hostsOnly`.
- **New chart defaults** (`App/Charts/ChartEditorView.swift`): `houseSystem` (.placidus),
  `isSidereal` — the user re-picks their preferred system for every new chart.
- **Astrology hub** (`App/Screens/AstrologyHomeView.swift`): `selectedChartID` — which saved
  chart drives the "Today" reading; resets to "most recent" each launch.
- **Tonight / Observer**: no fallback location when CoreLocation is denied/unavailable.

And there is currently **no place** to express app-wide intent (units, default location,
motion, notifications).

---

## Scope

**In scope (v1):**
1. A persistence layer (`AppPreferences`) for scalar settings.
2. A **Settings** screen reachable from `MoreMenu` (new row under a new `section(nil, [.settings, .about])` or its own group).
3. Wiring the existing ephemeral state above through `AppPreferences` so it round-trips.
4. New **unit** preferences (temperature, distance, large-distance) consumed by `StarFacts` / `PlanetFacts` / detail views.
5. A **default observing location** used by `TonightView` (and Sky status copy) when live location is unavailable.

**Out of scope (tracked elsewhere):**
- Accessibility toggles → `docs/accessibility-spec.md` (a "Reduce Motion override" lives there, but the *storage* is this layer).
- Notification scheduling internals → existing `App/Charts/TransitNotifications.swift`; this layer only owns the on/off + lead-time prefs.
- iCloud sync of preferences (later; design keys so a `NSUbiquitousKeyValueStore` swap is trivial).

---

## Architecture

Use a single injected **`@Observable`** store, not scattered `@AppStorage` (the app already
uses `@Observable` models — `AstrologyModel`, `ObserverLocation`, `PlaceSearch` — so this is
idiomatic, testable, and lets non-View code read prefs).

```swift
// App/Preferences/AppPreferences.swift
@MainActor @Observable
final class AppPreferences {
    static let shared = AppPreferences()              // also injectable for tests
    private let store: UserDefaults
    init(store: UserDefaults = .standard) { self.store = store; load() }

    // Each property reads its default once, writes through on didSet.
    var temperatureUnit: TemperatureUnit { didSet { persist(\.temperatureUnit) } }
    // …
}
```

- Inject once at the scene root: `ContentView().environment(AppPreferences.shared)`, and in
  `AstrolabeApp` so snapshot harnesses get a fresh instance.
- Views read via `@Environment(AppPreferences.self) private var prefs`.
- Keep `SkyFilters` as the in-memory binding type, but **seed it from `prefs` on appear** and
  **write back on change** (one `onChange(of: filters)` already exists in `ContentView` — extend it to persist). Same pattern for the galaxy toggles.

**Keys:** namespaced string constants, e.g. `"pref.sky.magnitudeLimit"`. Centralize in one
`enum PreferenceKey`. Never reuse a key for a changed type (forward-compat).

**Codable enums:** `HouseSystem` / `Zodiac` already exist in `Astrology`; store the new
default-chart prefs as their `rawValue` (add `RawRepresentable`/`Codable` conformance in the
package if missing — verify `HouseSystem: CaseIterable` is already there; it is, per the editor's `ForEach(HouseSystem.allCases)`).

---

## The preference set (v1)

| Preference | Type | Default | Consumed by |
|---|---|---|---|
| `sky.mode` | Sky / AR | Sky | `ContentView.mode` |
| `sky.fieldOfView` | Double (18–95) | 65 | `ContentView.fieldOfView` |
| `sky.filters.*` | the 8 `SkyFilters` fields | current defaults | `SkyFilters` / `FilterSheet` |
| `galaxy.showMilkyWay` | Bool | true | `GalaxyMapView` |
| `galaxy.hostsOnly` | Bool | false | `GalaxyMapView` |
| `chart.defaultHouseSystem` | HouseSystem | .placidus | `ChartEditorView` prefill |
| `chart.defaultSidereal` | Bool | false | `ChartEditorView` prefill |
| `astrology.defaultChartID` | PersistentIdentifier (as String) | nil → most recent | `AstrologyHomeView` |
| `units.temperature` | °C / °F / K | °C | `PlanetFacts`, detail sheets |
| `units.distance` | km / mi | km | facts/detail copy |
| `units.largeDistance` | ly / pc / AU-where-apt | ly | `StarFacts`, galaxy readouts |
| `location.useHomeFallback` | Bool | false | Tonight / Sky status |
| `location.home` | lat/long + name + tz | nil | Tonight / Sky status |
| `notifications.transitsEnabled` | Bool | false | `TransitNotifications` |
| `notifications.leadDays` | Int | 1 | `TransitNotifications` |
| `motion.respectReduceMotion` | Bool | true | sphere/galaxy (see a11y spec) |

> **Do NOT persist:** AR `azimuthOffset` / `manuallyCalibrated` (location- and session-specific),
> the Sky/Sphere **time scrubber** offset (intentionally returns to "now"), and any per-frame
> camera state. These are deliberately ephemeral.

### Units detail
Introduce `enum TemperatureUnit`, `DistanceUnit`, `LargeDistanceUnit` in a small
`App/Preferences/Units.swift`, each with a `format(_:)` helper. Audit current hardcoded
conversions: `GalaxyMapView.starDetail` (`* 3.2616` ly), `StarFacts`, `PlanetFacts` (K→°C),
`PlanetDetailView`. Route them through the chosen unit. Default to metric/ly (the current
behavior) so existing screenshots/specs don't shift unless the user opts in.

---

## Settings screen

New `AppScreen.settings` (gear glyph, neutral gray tint) in `MoreMenu`. A SwiftUI `Form`
matching the existing dark `Theme.spaceGradient` + `.scrollContentBackground(.hidden)` style
(copy `FilterSheet`/`ChartEditorView` chrome). Sections:

- **Units** — temperature, distance, large distance (segmented pickers).
- **Sky** — default magnitude, "remember last Sky/AR mode", default filters shortcut
  (a button that opens the existing `FilterSheet` bound to the persisted defaults).
- **Astrology** — default house system, tropical/sidereal, default chart for "Today".
- **Location** — set a home location (reuse `PlaceSearch` from `ChartEditorView`), toggle
  "use when current location is unavailable".
- **Notifications** — transit alerts on/off, lead time (gated on `UNUserNotificationCenter` auth).
- **Motion & Display** — "Respect Reduce Motion" (see a11y spec), maybe "Auto-spin sphere".
- **About** footer link / version (`MARKETING_VERSION`).

A **"Reset to defaults"** destructive button at the bottom (clears the namespace).

---

## Edge cases & migration

- **First launch:** no keys present → every getter returns its hardcoded default; no migration.
- **Unknown enum rawValue** (e.g. a future house system removed): fall back to default, don't crash.
- **`defaultChartID`** points at a deleted `SavedChart`: `AstrologyHomeView` already falls back
  to `charts.first`; keep that guard.
- **Schema version key** `"pref.schemaVersion" = 1` written on first save, so future migrations
  can branch.

## Testing

- Unit-test `AppPreferences` against an in-memory `UserDefaults(suiteName:)`: round-trip each
  type, unknown-rawValue fallback, reset clears only the namespace.
- A `format(_:)` test per unit enum (°C↔°F↔K, ly↔pc).
- Snapshot the Settings screen via a harness arg (`-snapshotSettings`) for visual review.

## Implementation order

1. `AppPreferences` + `PreferenceKey` + `Units.swift` (+ tests). No UI yet.
2. Inject at the root; wire **Sky filters + mode + FOV** through it (highest daily value).
3. Add the **Settings** screen with Units + Sky + Astrology sections.
4. Route unit-bearing facts/detail copy through the unit prefs.
5. Galaxy toggles, default-chart, home location, notification prefs.
