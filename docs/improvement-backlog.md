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

## Flagship ★ features (updated for the 2026-07-15 Ecliptica split)

The astrology-riding ★ differentiators (precession-gap "signs vs constellations" toggle,
transit-to-sky, void-of-course Moon) **moved to the Ecliptica app's backlog** with the astrology
module. Transit-to-sky in particular now implies a **cross-app deep link** (Ecliptica transit →
this app's AR view centered on the body) if it's ever built — the planet projection on this side
already exists.

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
- **Bolometric correction for luminosity/derived radius** (data-verification pass,
  2026-07-30). HYG's `lum` is V-band — no bolometric correction — so hot and cool
  stars understate their true output, and the Stefan–Boltzmann derived radius
  inherits the error where it's most visible: **Betelgeuse shows ~13k L☉ / ≈268 R☉
  vs literature ~100k L☉(bol) / ~640–950 R☉**. The math itself is unit-tested and
  correct; the input is visual. Fix: apply BC(B−V) (e.g. Flower 1996 polynomials,
  or Ballesteros-consistent) in `CelestialCore.Astrophysics` before deriving, and
  relabel facts back from "visible light" to total. Until then the fact copy says
  "visible light" (accurate), and the radius row stays "(derived) ≈". Affects the
  size silhouette, HR placement is fine (classic HR diagrams are V-based anyway).
- **Catalog-faithful but dated distances**: HYG carries Hipparcos parallaxes —
  e.g. Betelgeuse 498 ly vs the modern ~550 ly (radio ~640 ly). Not a bug; note
  if a Gaia-based refresh is ever considered (Gaia is unreliable for the very
  brightest stars, so this is genuinely open).

### Galaxy Map
- **Rework the nebulae** (Elysia, 2026-07-28 — scope not yet defined). Existing threads to fold
  in when this happens: the `--shape sphere` bake mode for shell objects (Ring/Helix/SNRs read
  flat off-angle), star-suppression pre-pass for Milky-Way SNR bakes (Vela/IC 443 false gas),
  the procedural holdouts with no good visible-light source (Flame, Crescent, Owl…), fade-in
  instead of popping after the async first build (ui-review doc), and the depth-occlusion
  limitation below.
- **Depth-sorted occlusion** — the known limitation: additive glow has no depth test, so stars
  behind a cloud shine through (Phase 7 "Follow-ups"). A true fix needs depth-sorted transparency.
- "Artist's impression" tag on procedural (non-baked) landmarks; host-badge rings; distance-faded
  core; GPU-side cull/LOD (all in Phase 7 "Follow-ups").

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
  place heavy per-star math sits on the main thread (contrast `TonightView`,
  which correctly uses `Task.detached`). Consider offloading the rebuild and handing back the
  `[StarPoint]` array. Re-measure on the oldest supported device before optimizing.
- **God-object views.** `App/Screens/GalaxyMapView.swift` (~1550 lines) and
  `App/ContentView.swift` (~950 lines) each carry rendering + gestures + scene/overlay building +
  calibration/cinematic in one file. Well-commented, but extracting (e.g.) the ecliptic-overlay
  builder + calibration out of `ContentView`, and `buildScene`/`appendLandmarkSprites` out of
  `GalaxyMapView`, would improve maintainability and unlock unit tests on the scene-building math.
- **No UI / snapshot test target.** Elaborate snapshot *harnesses* exist
  (`-snapshotStar/-snapshotPlanet/-snapshotTonight/-snapshotCon3D/-galaxyBH/-galaxyLandmark`)
  but they're driven manually — there's no XCTest target wiring them into CI. Adding one would
  lock in the visuals and enable the `performAccessibilityAudit()` path (see a11y spec).
- **Math package is well tested** (`CelestialCore` `swift test` green in `../AstroPackages`,
  validated against Meeus / Horizons). Gap is purely at the **UI/integration** layer.
- **Reduce Motion** is honored in only one file (`SystemView`) — the galaxy fly-tos ignore
  it (tracked in the a11y spec, but it's also a correctness/polish issue).

---

## Notes on what is already strong (don't regress)
- Clean package boundaries (`CelestialCore` pure/Sendable, shared via `../AstroPackages`).
- The "luminous instrument" design system (`Theme`, `LuminousGlyph`, `luminousSurface`,
  `CircleIconButton`) — reuse it for Settings/onboarding/widgets so new surfaces feel native.
- The image-baked-nebula pipeline's licensing discipline (derived points only, never the photo).
