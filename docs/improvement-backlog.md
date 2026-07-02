# Improvement Backlog & Review Notes

> Source: full-app review, 2026-06-28 (read of the whole `App/` + `Packages/` tree).
> This is the durable capture of ideas and observations so they aren't forgotten. The
> cross-cutting items have their own specs (see "Spec'd work" below); everything else
> lives here until promoted. Nothing here is committed work — it's a menu.

## Spec'd work (has its own file)
- **Preferences & Settings** → `docs/preferences-spec.md` *(approved to build)*
- **Accessibility** → `docs/accessibility-spec.md` *(deferred)*
- **Localization (EN + ES)** → `docs/localization-spec.md` *(deferred)*
- **Widgets / App Intents / Live Activities** → `docs/widgets-spec.md` *(planned)*
- **First-launch onboarding** → `docs/onboarding-spec.md` *(planned)*
- iPad / landscape: **explicitly deferred** (no iPad to test on). Note: Info.plist pins
  portrait while `ContentView` carries quadrant-rotation chrome that only handles tilt
  *within* portrait; `TARGETED_DEVICE_FAMILY` still ships iPad with no iPad layout. Revisit
  together if/when an iPad is available.

---

## Flagship features listed in the docs but NOT built

These are called out in `docs/astrology-features.md` as the **★ differentiators** (the moat —
things only this app can do because astrology rides the real sky engine), yet they're absent
from the code today. Highest narrative/marketing leverage.

1. **"Signs vs constellations, honestly" — the precession-gap toggle.** Overlay the 30° tropical
   signs against the real IAU constellation boundaries to *show* the gap ("your sign is wrong"
   debate turned into an educational feature). **Not implemented** (grep finds nothing). We
   already have the ecliptic overlay (`ContentView` zodiac path) and constellation geometry —
   this is mostly a new overlay + copy, little new math. *Most shareable idea in the plan.*
2. **Transit-to-sky.** When a transit is exact, let the user physically find that planet in the
   sky (bridge from the transit list → AR view centered on that body). The AR zodiac overlay and
   planet projection already exist; this is a small connective feature.
3. **Void-of-course Moon** (listed under v1 "Moon now"). Not implemented — needs the last
   aspect the Moon makes before changing sign; the aspect + Moon engines exist.

> The other ★ items — live zodiac band in AR, "your planets in the real sky right now" — ARE
> built (the F11 ecliptic/zodiac Sky filter). Keep those; ship the three above to complete the moat.

---

## Feature ideas by surface

### Sky / AR
- Full-sky atmospheric **refraction toggle** (currently only the luminaries get refraction;
  already flagged "next" in Phase 5).
- **Deep-sky objects pointable/identifiable in Sky mode** — `CelestialCore.DeepSky` exists and is
  browsable in the Catalog, but isn't tappable on the dome yet (flagged in Phase 5).
- **ISS / satellite passes** — needs a TLE source + SGP4 propagator (new math in `CelestialCore`).
  Enables a great Live Activity and notification. Licensing: CelesTrak TLEs.
- **Comet tracker** (bright comets), **altitude-tonight graph** for any object, **observing
  checklist**.
- **Two-star calibration** in AR (beats the single-azimuth align); plate-solving is the long-term
  precision ceiling already noted.
- Light-pollution / **Bortle** awareness from location ("naked-eye limit here ≈ mag X").

### Tonight
- Best-viewing-time per planet; "what to look at tonight" highlight.
- Notifications: meteor-peak reminder, Moon-phase, ISS pass (ties to widgets/Live Activities spec).

### Catalog / Detail
- Observation **journal** — log what you saw, notes, date/location (SwiftData).
- Favourites/bookmarks across stars, deep-sky, landmarks.

### Galaxy Map
- **Depth-sorted occlusion** — the known limitation: additive glow has no depth test, so stars
  behind a cloud shine through (Phase 7 "Follow-ups"). A true fix needs depth-sorted transparency.
- "Artist's impression" tag on procedural (non-baked) landmarks; host-badge rings; distance-faded
  core; GPU-side cull/LOD (all in Phase 7 "Follow-ups").

### Astrology
- **Richer interpretation copy.** The engine (`Interpretation.swift`) is deterministic and
  license-clean (good), but combination sections read mechanically — the "Key aspects" block
  just restates `aspectDynamic`. Two paths: (a) richer combinatorial templates
  (sign × planet × house nuance), or (b) an **opt-in on-device LLM "deeper reading"** (Apple
  Foundation Models) layered *on top of* the deterministic placements, keeping all math/structure
  deterministic and birth data on-device. If a server path is ever used, default to the latest
  Claude models per project guidance — but on-device is the privacy-right answer for birth data.
- Planetary hours, fixed stars, midpoints, harmonics, draconic chart.
- Transit → **system Calendar** export ("Saturn squares your Sun on …").
- Relationship "**best days ahead**" from synastry + transits.

### Constellations
- Proper-motion "constellations over time"; a sightline to the user's actual location;
  figure-of-the-night (already listed in Phase 9 "Next").

### Share / growth
- "Sky tonight" and Moon-phase **share cards** (the chart share cards are excellent; extend the
  pattern). Ties into widgets.

---

## Technical & correctness notes

- **`ContentView.refreshSky()` runs on the MainActor and iterates the full naked-eye catalog**
  (~8.9k stars, a `CoordinateTransform.horizontal` each) every ~1.5 s. It's throttled and the
  per-frame motion is handled by the Canvas projection, so it's likely fine — but it's the one
  place heavy per-star math sits on the main thread (contrast `TonightView` / `AstrologyHomeView`,
  which correctly use `Task.detached`). Consider offloading the rebuild and handing back the
  `[StarPoint]` array. Re-measure on the oldest supported device before optimizing.
- **God-object views.** `App/Screens/GalaxyMapView.swift` (~1550 lines) and
  `App/ContentView.swift` (~963 lines) each carry rendering + gestures + scene/zodiac building +
  calibration/cinematic in one file. Well-commented, but extracting (e.g.) the zodiac-overlay
  builder + calibration out of `ContentView`, and `buildScene`/`appendLandmarkSprites` out of
  `GalaxyMapView`, would improve maintainability and unlock unit tests on the scene-building math.
- **No UI / snapshot test target.** Elaborate snapshot *harnesses* exist
  (`-snapshotSphere/-snapshotStar/-snapshotPlanet/-snapshotAstro/-snapshotGalaxy/-exportTest`)
  but they're driven manually — there's no XCTest target wiring them into CI. Adding one would
  lock in the visuals and enable the `performAccessibilityAudit()` path (see a11y spec).
- **Math packages are well tested** (`CelestialCore` + `Astrology` `swift test` green, validated
  against Meeus / Horizons). Gap is purely at the **UI/integration** layer.
- **Reduce Motion** is honored in only one file (`SystemView`) — the auto-spinning sphere, the
  ~8 s idle tour auto-start, the dive cinematic, and galaxy fly-tos ignore it (tracked in the a11y
  spec, but it's also a correctness/polish issue).

---

## Notes on what is already strong (don't regress)
- Clean package boundaries (`CelestialCore` pure/Sendable, `Astrology` depends only on it).
- The deterministic, license-clean interpretation engine — keep it deterministic even if an LLM
  layer is added on top.
- The "luminous instrument" design system (`Theme`, `LuminousGlyph`, `luminousSurface`,
  `CircleIconButton`) — reuse it for Settings/onboarding/widgets so new surfaces feel native.
- The image-baked-nebula pipeline's licensing discipline (derived points only, never the photo).
