# Widgets, App Intents & Live Activities — Spec

> Status: **planned, to build when the time comes.** Drafted 2026-06-28.
> This is the biggest *new-surface* growth lever for the app and reuses engines that
> already exist (`VisibleSky`, `MoonPhase`, `AstroEvent`, `Daily`, `Forecast`,
> `MeteorShowers`). All compute is local and cheap — ideal for a widget timeline.

---

## Why this fits Astrelia

The app already computes, off the main actor, everything a glanceable surface wants:
- `CelestialCore.VisibleSky.status(at:date:)` → planets up/down, sun day/night.
- `VisibleSky.moonPhase(at:)` → phase name, % lit, waxing/waning.
- `CelestialCore.AstroEvent.upcoming(after:within:)` → solstices, Moon phases, oppositions,
  eclipses, etc. (geocentric, location-independent).
- `MeteorShowers.active(on:)` / `nextUpcoming(after:)`.
- `Astrology.Daily.reading(for:)` and `Forecast.retrogrades(of:days:from:)`.

A widget extension can call these directly (the packages have **no UIKit/SwiftUI deps**, so they
link cleanly into a widget target).

---

## New target

`AstreliaWidgets` (WidgetKit extension) added to `project.yml`:
- Depends on `CelestialCore` and `Astrology` (the pure packages).
- Shares the bundled catalogs it needs (Moon/planets need no catalog; star-dependent widgets
  would need the resource — prefer widgets that **don't** need the 560 KB star CSV to keep the
  extension light).
- **App Group** (`group.pink.ely.astrelia`) so the widget can read the user's
  **home location** and **default chart id** written by `AppPreferences`
  (see `docs/preferences-spec.md` — store shared prefs in the group's `UserDefaults`).
  SwiftData `SavedChart` access from the widget: either expose the model container to the app
  group, or have the app write a small "daily reading snapshot" into the group for the widget to
  read (simpler, avoids SwiftData-in-extension friction).

---

## Widgets (v1)

1. **Moon Phase** — small/medium/lock-screen (circular & rectangular). Shows the SF Symbol
   `moonphase.*` (logic already in `TonightView.moonSymbol`), % illuminated, phase name, next
   full/new date (from `AstroEvent`). No location needed → simplest first widget. Timeline:
   refresh every few hours.
2. **Tonight** — medium. Day/night + sunset, count of planets up, the brightest/most-notable
   one with direction ("Jupiter, SE"), next meteor peak. Needs the home location (app group).
3. **Daily Reading** — small/medium. From the default `SavedChart`: `Daily.reading` headline +
   one line, plus a Mercury-retrograde flag. Needs the snapshot bridge.
4. **Upcoming Event** — small. The single next `AstroEvent` ("Full Moon in 3 days").

Lock-screen (`.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline`) variants for
Moon Phase and Tonight are high value.

### Timeline strategy
- Most content changes slowly (Moon phase, events) → coarse timelines (a few entries/day).
- Use `TimelineReloadPolicy.after(nextSignificantInstant)` where a precise change exists
  (sunrise/sunset, exact phase, meteor peak) rather than fixed intervals.
- All compute stays synchronous + fast; no network.

---

## App Intents (Siri / Spotlight / Shortcuts)

Add an `AppIntents` provider (in the app, optionally surfaced to the widget for interactivity):

- **`MoonPhaseIntent`** → "What's the Moon phase?" returns a spoken/string result.
- **`TonightIntent`** → "What planets are up tonight?" lists up-now planets + directions.
- **`OpenChartIntent`** (`OpenIntent`) → "Open my chart" deep-links into `AstrologyHomeView` /
  a specific `SavedChart` (parameterized by chart name via an `AppEntity` over `SavedChart`).
- **`NextEventIntent`** → next astronomical event.
- Donate these as **App Shortcuts** (`AppShortcutsProvider`) so they appear in Spotlight with
  zero setup, and expose **interactive widget buttons** (e.g. a "refresh"/"next" button) via
  `Button(intent:)` on iOS 17+.

Deep-linking: define a small `AstreliaRoute` URL scheme/`onOpenURL` handler in
`AstreliaApp`/`ContentView` so widget taps and intents land on the right screen
(today the app is a single `ContentView` + full-screen menu cover; add a routing `@State` that
the menu/cover can be driven from).

---

## Live Activities (later within this effort)

- **Transit / retrograde window** — when a tracked transit is approaching exact (data from
  `Forecast`), a Live Activity counts down "Saturn square Sun — exact in 2 days." Start/stop from
  the app; update from a background refresh or push (ActivityKit).
- **ISS pass** — *if/when* ISS passes ship (needs TLE; see backlog). A pass is a perfect short
  Live Activity ("ISS overhead in 4 min, rising NW"). Gate on the TLE feature existing.
- Keep Live Activities **opt-in** and few; they're the most intrusive surface.

---

## Design
- Match the app's look: dark, `Theme.accent`/per-feature tints, serif title for the wordmark,
  no emoji (use SF Symbols + the FE0E-safe glyphs).
- Respect the **units** preferences (°C/°F, ly/pc) from `AppPreferences`.
- Provide `.containerBackground` for the iOS 17 widget look; supply removable-background support.

## Testing
- Widget previews (`#Preview(as: .systemMedium)`) for each family/size.
- Verify the packages link into the extension without pulling UIKit.
- Test the app-group prefs/snapshot bridge end-to-end (app writes → widget reads).

## Dependencies / ordering
1. Ship `AppPreferences` + App Group first (`docs/preferences-spec.md`) — widgets need shared prefs.
2. Moon Phase widget (no shared data) — proves the target + package linking.
3. App Intents + App Shortcuts + deep-link routing.
4. Tonight & Daily Reading widgets (need the app-group bridge).
5. Live Activities last.
