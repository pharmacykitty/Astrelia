# Astrolabe (working title)

> A point-at-the-sky planetarium for iOS with deep astrophysical data and a full astrology layer — built to be genuinely beautiful.

**Status:** Pre-prototype. This file is the source of truth for the vision and architecture until code exists. Name is not final — see "Naming" below; renaming the folder is a one-liner, don't treat `Astrolabe` as locked.

---

## The vision

Raise your phone toward the sky (or the ground, to see what's beneath you) and see the real positions of stars, planets, and other celestial bodies, accurately computed for your location and the current instant. Tap anything to get as much detail as exists — physical (mass, radius, distance, spectral class, temperature, luminosity, orbital elements…) and, in a clearly separate layer, astrological (zodiac, houses, aspects, transits, natal charts).

Three pillars:
1. **Accurate** — real ephemeris math, real catalogs. Positions should match Stellarium/SkySafari within reason.
2. **Deep** — every body carries the richest dataset we can source; tapping should always reward curiosity.
3. **Beautiful** — this is the differentiator. Smooth motion, gorgeous star glow / Milky Way, tasteful typography and transitions.

Astrophysics and astrology coexist but are **separate modules** — different math, different data, different UI surfaces. We don't blend the science and the symbolism in code; the user chooses what they want to see.

### Two viewing modes (same data engine, two cameras)
1. **Sky mode** — you're standing on Earth. Raise the phone; real bodies are projected onto the celestial dome (RA/Dec → alt/az for your location and time). This is the AR "point at the sky" experience.
2. **Galaxy Map mode** — you leave Earth and free-fly through a 3D star field, à la *Elite Dangerous*. Zoom from a stylized whole-galaxy view down to a single system; click to select and inspect.

Both consume the same `CelestialCore` data — Sky mode uses horizontal coordinates; Map mode uses the stars' true 3D positions (RA/Dec + parallax distance → XYZ).

---

## Tech stack (proposed — confirm as we go)

- **Platform:** iOS, latest SDK (Xcode 27 / Swift 6, strict concurrency). iPhone first; iPad later.
- **UI:** SwiftUI for chrome and detail views.
- **Rendering:** prototype the sky dome with SceneKit or SwiftUI `Canvas`; move to **Metal** for the real thing (100k+ stars, glow shaders, Milky Way, 60/120fps). Treat the renderer as swappable behind a protocol.
- **Sensors:** `CoreLocation` (observer lat/long/altitude + true heading) + `CoreMotion` (`CMMotionManager` device attitude, referenced to true north via `.xTrueNorthZVertical`). Sensor fusion answers "where on the celestial sphere is the device pointing right now."
- **Persistence:** SwiftData for user data (saved locations, natal charts, favorites). Bundled read-only catalogs ship as data files, not SwiftData.

## Architecture

Keep the math/data **platform-agnostic and unit-tested**, isolated from UI and sensors.

```
App/                       # SwiftUI iOS app target
  Sky/                     # ✅ sensors, AR, projection (SkyCamera/SkyMotionProvider/ARCameraController)
  Screens/                 # Catalog, Constellations, Galaxy Map, Astrology, About screens
  Catalog/                 # ✅ catalog/constellation data + facts (StarFacts, ConstellationCatalog…)
project.yml                # XcodeGen spec — the .xcodeproj is generated, not committed
Packages/
  CelestialCore/           # local Swift package — NO UIKit/SwiftUI deps
    Math/                  # ✅ Angle, Vector3
    Time/                  # ✅ Julian date, sidereal time   (ΔT/nutation: TODO)
    Coordinates/           # ✅ equatorial ⇄ horizontal       (ecliptic/precession: TODO)
    Catalog/               # ✅ Star, HYG CSV ingestion, StarCatalog queries
    Ephemeris/             # ✅ Sun & Moon (Meeus 25/47) · ✅ Planets Mercury–Pluto (SwiftAA, MIT)
  Astrology/               # ✅ zodiac, ayanamsa, angles, houses, aspects, charts (separate package)
```

- `CelestialCore` is pure computation: feed it a time + observer + body, get back coordinates and physical data. Fully testable against published reference values (Meeus worked examples, JPL Horizons).
- The app layer turns `CelestialCore` output into the rendered dome and detail UI.
- `Astrology` depends on `CelestialCore` (it needs ecliptic longitudes) but nothing depends on it.

### Hard problems to get right
- **Coordinate transforms & time:** Julian date → local sidereal time → equatorial (RA/Dec) → horizontal (alt/az) for the observer. This is the spine; build and test it first.
- **Ephemeris accuracy vs. weight:** analytical models (VSOP87 for planets, ELP for Moon) vs. bundling JPL DE ephemerides. Start analytical; revisit if accuracy demands it.
- **Sensor fusion & smoothing:** magnetometer is noisy; needs filtering/calibration so the sky doesn't jitter. Account for magnetic vs. true north.
- **Rendering performance & beauty:** culling, level-of-detail by magnitude, additive glow, all at 60fps.

### Galaxy Map mode (the *Elite Dangerous*-style free-flight map)
The trick is separating **real data** from **art**:
- **Real (near field):** the ~119k catalogued stars from HYG have true 3D positions (parallax → XYZ in parsecs). Render them as glowing billboards in a free-fly 3D scene; click to select and inspect. Fly to a star and show its **actual known exoplanets**.
- **Art (far field):** we will never have positions for 100B+ stars. Render the Milky Way's spiral arms as a stylized volumetric/particle backdrop, and overlay the real catalog where we have it. Zoom: stylized whole-galaxy → real local stars → single system.
- **Not in scope:** Elite's literal procedural 400-billion-system simulation. We get the visual magic without it.
- **Engineering caveats:** this is a *second* rendering pipeline (free-fly camera, Metal). Huge scale ranges demand floating-point precision care (camera-relative / scaled coordinate space, logarithmic depth). Needs a spatial index (octree/k-d tree) for picking and culling. Shares `CelestialCore` data; separate renderer.

## Data sources (verify licensing before bundling — this matters for App Store)
> The user-facing, canonical attribution list lives in `App/Screens/AboutView.swift` (`SourceCatalog`), surfaced as the **About → Sources** screen. Keep it in sync with this section.
- **Stars:** HYG Database v3 (~119k stars, combines Hipparcos/Yale/Gliese; public domain) is the likely starting catalog. Yale Bright Star Catalog for the brightest.
- **Deep-sky:** Messier / NGC catalogs.
- **Exoplanets:** NASA Exoplanet Archive (~5,700+ confirmed planets with host-star links) — powers "fly to a star, see its planets" in Galaxy Map mode. Full design + decisions in **`docs/exoplanet-spec.md`**.
- **Planets/Sun/Moon:** VSOP87 / ELP analytical theories, or JPL data. Physical/astrophysical facts from NASA/JPL fact sheets.
- **Derived stellar physics:** surface temperature from B−V via Ballesteros (2012); radius from luminosity + temperature via the Stefan–Boltzmann law (IAU 2015 nominal solar values). Lives in `CelestialCore.Astrophysics` (pure + unit-tested); relatable comparisons in `App/Catalog/StarFacts.swift`.
- **Candidate library:** `SwiftAA` (Swift port of Meeus' *Astronomical Algorithms*) — could save large effort on Time/Coordinates/Ephemeris. **Check license** and accuracy before depending on it.
- **Astrology:** house systems (Placidus, Whole Sign, etc.), aspect math. Swiss Ephemeris is the gold standard but is **AGPL or paid-commercial** — incompatible with a closed App Store app unless licensed. **Settled (2026-06-27):** roll our own astrology math on `CelestialCore`; use **SwiftAA (MIT)** for planet ecliptic longitudes. Full spec + decisions in **`docs/astrology-spec.md`**.

## Conventions
- Swift 6, strict concurrency. Keep `CelestialCore` `Sendable` and free of global mutable state.
- Astronomy math in SI / standard units with explicit types where it prevents unit bugs (radians vs degrees, JD vs calendar date). No naked `Double` for angles in public APIs where avoidable.
- Unit tests are mandatory for `CelestialCore` — every transform validated against a known reference value.
- Separation of concerns per the existing architecture-review/swiftui-pro skill standards: no sensor or UI code inside the math packages.
- **Keep sources current.** After adding any dataset, library, algorithm, or doing research that informs the app, update the attributions: add an entry to `SourceCatalog` in `App/Screens/AboutView.swift` (the in-app Sources screen — the source of truth users see) and, where relevant, the "Data sources" section here and the per-feature spec's Sources section in `docs/`. Several datasets require attribution before shipping, so this is not optional.

## Roadmap
- **Phase 0 — now:** vision + this doc + name. Decide on `SwiftAA` vs. roll-our-own.
- **Phase 1 ✅:** `CelestialCore` Time + Coordinates — `Angle`, `JulianDay`, mean sidereal time, equatorial⇄horizontal transforms. Validated against Meeus worked examples (7.a, 12.a/b, 13.b). Conventions locked: azimuth from **North eastward**, longitude **east-positive**. (Decision: rolled our own; revisit SwiftAA at Phase 2 for ephemeris.) Still to add: nutation → apparent sidereal time; ecliptic coordinates; precession.
- **Phase 2 (in progress):** Star catalog ingestion ✅ (HYG parser + `StarCatalog`, validated on full ~120k-row HYG v4.1). Sun & Moon ephemeris ✅ — rolled our own: Sun (Meeus 25, apparent ~0.01°), Moon (Meeus 47, full 60+60-term ELP series, validated to Meeus 47.a), obliquity, ecliptic→equatorial transform, Moon phase/illumination. iOS app shows live Sun/Moon/Sirius alt-az + Moon phase. **Decision recorded: kept rolling our own — SwiftAA not needed so far.** Still TODO: nutation → apparent sidereal/obliquity (currently mean equinox, sub-arcmin); ΔT (UT↔TD); **planets (VSOP87)** — reassess SwiftAA there.
- **Phase 3 (first cut ✅):** Sensor fusion — `SkyMotionProvider` (CoreLocation + CoreMotion `.xTrueNorthZVertical`), `CameraBasis`/`projectToScreen` gnomonic projection mapping device pointing → screen. Center reticle + heading HUD. ⚠️ Rotation-matrix row/column convention is a guess until verified on a real device.
- **Phase 4 (✅ working):** Live AR "point at the sky" view, verified on-device. Full naked-eye star catalog (HYG mag ≤ 6.5, ~8.9k stars, bundled as `App/Resources/hyg_naked_eye.csv`, ~560 KB) drawn via `Canvas` (sized/coloured by magnitude & B−V), brightest stars labelled, Sun & Moon as nodes. Filter sheet (brightness/labels/constellations/Sun-Moon/below-horizon). Bottom panel guides to Sun & Moon only. **Constellation lines** (d3-celestial GeoJSON, BSD, bundled `constellation_lines.json`). **Pinch-to-zoom** FOV reveals more star names; **collision-avoided labels** (proper name → Bayer); **tap-to-identify** any star.
- **Phase 3b/4b — AR camera mode (first cut, needs on-device verification):** `SkyCamera` abstraction unifies projection for two modes: **Sky** (CoreMotion gnomonic) and **AR** (`ARCameraController` = ARKit `.gravityAndHeading` camera passthrough, projected via real `viewMatrix`/`projectionMatrix`). Mode toggle in chrome. **Calibration**: aim reticle at Sun/Moon/bright star → "Align" computes an azimuth offset cancelling compass error (→ sub-degree). Precision ceiling = magnetometer (~5–10° raw, <1° after align); altitude from gravity ~1–2°. Ultimate future precision = camera plate-solving. Next: planets, full-name constellation labels, perf (cache star dirs past mag ~5.5). Attribution before ship: d3-celestial (Frohn, BSD), HYG (astronexus).
- **Phase 5 (largely ✅):** Tap-to-detail astrophysical data sheets, with an accessibility-first "numbers → intuition" layer. Done: `CelestialCore.Astrophysics` (derived stellar radius via Stefan–Boltzmann, light-travel time, parsec↔ly; unit-tested) + `StarFacts` "relatable comparisons" (light left in year Y, ×Sun brightness/heat/size) and `lifeStory` (one-line stellar biography from spectral/luminosity class). Catalog `StarDetailView` now carries a derived-radius row, comparison callouts, the life story, an **HR-diagram "you are here"** widget (`StarComparisonViews.swift`), and a true-scale **Sun-vs-star size silhouette**. Galaxy Map shows a persistent **distance-from-Earth** readout and a light-travel line on the star card. Sky mode: tap-identify surfaces distance + plain-language spectral type, a **colour-key (temperature)** legend toggle, and an opt-in **time scrubber** (±12h, runs the Sun/Moon/stars forward/back on the live ephemeris). **Next:** planet/exoplanet detail sheets, a "tonight's sky" events feed (needs ISS TLE / meteor-shower data), optional jargon glossary popovers.
- **Phase 6 (first cut ✅ — math layer):** `Packages/Astrology/` built and unit-tested (22 tests, `swift test` green). Done: zodiac signs/positions + DMS; `Zodiac` tropical/sidereal with `Ayanamsa` (Lahiri); `ChartAngles` (Ascendant/MC); `HouseSystem` = Whole Sign / Equal / Porphyry / **Placidus** (iterative semi-arc, validated against its own definition) with **high-latitude fallback to Porphyry**; `AspectKind`/`OrbPolicy`/`AspectFinder` (major+minor, luminary bonus, applying/separating); `EphemerisProvider` + `CelestialCoreEphemeris` (Sun, Moon, mean lunar nodes today); `NatalChart` (positions, houses, aspects, Part of Fortune, day/night sect). App: `AstrologyView` ("Sky Now" chart — Big Three, `ChartWheel` Canvas, positions/aspects), wired into the menu. **Planets ✅ (Phase B done):** `CelestialCore.Planets` computes apparent geocentric ecliptic longitudes for Mercury–Pluto via **SwiftAA (MIT)** (Pluto via Meeus 37 + Earth, precessed to date); validated against Meeus 33.a (Venus RA/Dec), inferior-planet elongation bounds, and published Pluto ephemeris. Charts now carry the full body set + retrograde. Full spec/decisions in **`docs/astrology-spec.md`**; features in **`docs/astrology-features.md`**. **Birth charts ✅:** `SavedChart` (SwiftData, stores raw inputs incl. IANA tz) + `ChartEditorView` (date/time, "time unknown", `CLGeocoder` place→coords+timezone, house/zodiac pickers) + `ChartListView` + `SavedChartView`. Astrology menu → `AstrologyHomeView` hub (Sky Now / Saved Charts). Shared `ChartDetailView` (Big Three, `ChartWheel`, positions, aspects). **3D celestial sphere ✅ (first cut):** `CelestialSphereView` — rotating Astrolog-style globe (horizon/equator/ecliptic great circles, zodiac, planets, aspect chords) in the local horizon frame; the ★ astrophysics×astrology bridge. Design notes in **`docs/celestial-sphere.md`**. **Next:** transits, interpretation text, house great-circles + star field on the sphere.
- **Phase 7 (first cut ✅):** **Galaxy Map mode** — `GalaxyMapView` renders the real local star field in 3D: HYG positions computed from RA/Dec/parallax → XYZ parsecs, Sun at origin. SwiftUI `Canvas` + a simd orbit camera (`lookAt`/`perspective` matrices); drag to orbit, pinch to zoom, tap-to-select (projected-nearest hit test), "Fly here" retargets the camera. Stars sized by absolute magnitude, coloured by B−V. Wired into the menu. **Now also:** larger catalog (bundled `hyg_stars.csv`, mag ≤ 7.5, ~25k distance-known stars with real HYG XYZ/absmag/spect); stylized **Milky Way** as a true-scale four-arm barred spiral centred on the galactic centre (~8.2 kpc out) with additive/blurred glow, HII knots and a bar; **Sgr A\*** + a curated **Landmarks** dataset (`App/Catalog/Landmarks.swift`: ~25 nebulae/clusters/black holes/satellite galaxies) rendered as tappable markers; a searchable **Catalog** screen (`App/Catalog/CatalogView.swift`) of landmarks + bright stars with detail pages that launch the map focused on an object (`GalaxyMapFocus`); **free-fly camera** (Fly toggle) alongside orbit — gesture-only controls: one-finger drag steers around a centre reticle, a window-level **two-finger vertical pan** sets a *persistent* throttle (cruise hands-free; squared speed curve for fine→galaxy-crossing range, zero detent), with a non-interactive speed readout; plus a whole-galaxy "Galaxy" overview and eased fly-to. Full-screen (ignores safe area), custom back button. **Now also:** **exoplanet layer** — NASA Exoplanet Archive snapshot (`App/Resources/exoplanets.csv`, ~6.3k planets / ~4.7k systems incl. `sy_snum`) loaded by `ExoplanetStore`, cross-matched to catalog stars by HIP; host stars get cyan badges on the map and a "View planetary system" button (below "Fly here", shown only when the selected star has displayable planets). `SystemView` is a top-down orbital view: host star(s) at centre (companions clustered for multiple-star systems), planets on log-AU orbits with always-on name labels and Keplerian relative speeds, habitable zone, tap-to-inspect; a hand-authored **Sol** (`SolarSystem` in `Exoplanets.swift`) adds the planets' **major moons** (archive has no exomoons), drawn orbiting a selected planet. Galaxy-map **Catalog button** + a **Milky Way toggle**; button taps take priority over star selection (gestures live on the Canvas layer below the overlay). **Next:** nebula/landmark image sprites + dust lanes, octree for picking/culling at scale, LOD for the backdrop, and the eventual Metal renderer + logarithmic depth / camera-relative coords.
- **Phase 8:** Beauty + performance pass (Metal), accessibility, iPad.

## Open questions
- Final name (+ App Store availability check).
- ~~`SwiftAA` dependency or implement the math ourselves?~~ **Resolved:** rolled our own for astronomy; adding SwiftAA (MIT) for astrology planet positions (see `docs/astrology-spec.md`).
- ~~Astrology accuracy bar — and how to source ephemeris without Swiss Ephemeris licensing trouble.~~ **Resolved:** no Swiss Ephemeris (AGPL); own math on `CelestialCore` + SwiftAA. Validate ASC/MC/cusps against astro.com.
- AR via raw CoreMotion overlay vs. ARKit camera passthrough?
