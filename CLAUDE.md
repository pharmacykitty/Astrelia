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
App/                       # SwiftUI iOS app target (sensors, rendering)
project.yml                # XcodeGen spec — the .xcodeproj is generated, not committed
Packages/
  CelestialCore/           # local Swift package — NO UIKit/SwiftUI deps
    Math/                  # ✅ Angle, Vector3
    Time/                  # ✅ Julian date, sidereal time   (ΔT/nutation: TODO)
    Coordinates/           # ✅ equatorial ⇄ horizontal       (ecliptic/precession: TODO)
    Catalog/               # ✅ Star, HYG CSV ingestion, StarCatalog queries
    Ephemeris/             # TODO — Sun, Moon, planets (positions over time)
  Astrology/               # TODO — separate package: houses, aspects, natal charts
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
- **Stars:** HYG Database v3 (~119k stars, combines Hipparcos/Yale/Gliese; public domain) is the likely starting catalog. Yale Bright Star Catalog for the brightest.
- **Deep-sky:** Messier / NGC catalogs.
- **Exoplanets:** NASA Exoplanet Archive (~5,700+ confirmed planets with host-star links) — powers "fly to a star, see its planets" in Galaxy Map mode.
- **Planets/Sun/Moon:** VSOP87 / ELP analytical theories, or JPL data. Physical/astrophysical facts from NASA/JPL fact sheets.
- **Candidate library:** `SwiftAA` (Swift port of Meeus' *Astronomical Algorithms*) — could save large effort on Time/Coordinates/Ephemeris. **Check license** and accuracy before depending on it.
- **Astrology:** house systems (Placidus, Whole Sign, etc.), aspect math. Swiss Ephemeris is the gold standard but is **AGPL or paid-commercial** — incompatible with a closed App Store app unless licensed. Decide early; we may implement our own from `CelestialCore` ecliptic longitudes instead.

## Conventions
- Swift 6, strict concurrency. Keep `CelestialCore` `Sendable` and free of global mutable state.
- Astronomy math in SI / standard units with explicit types where it prevents unit bugs (radians vs degrees, JD vs calendar date). No naked `Double` for angles in public APIs where avoidable.
- Unit tests are mandatory for `CelestialCore` — every transform validated against a known reference value.
- Separation of concerns per the existing architecture-review/swiftui-pro skill standards: no sensor or UI code inside the math packages.

## Roadmap
- **Phase 0 — now:** vision + this doc + name. Decide on `SwiftAA` vs. roll-our-own.
- **Phase 1 ✅:** `CelestialCore` Time + Coordinates — `Angle`, `JulianDay`, mean sidereal time, equatorial⇄horizontal transforms. Validated against Meeus worked examples (7.a, 12.a/b, 13.b). Conventions locked: azimuth from **North eastward**, longitude **east-positive**. (Decision: rolled our own; revisit SwiftAA at Phase 2 for ephemeris.) Still to add: nutation → apparent sidereal time; ecliptic coordinates; precession.
- **Phase 2 (in progress):** Star catalog ingestion ✅ — `Star`, robust HYG CSV parser (column-mapped, quote-aware, validated on the full ~120k-row HYG v4.1), `StarCatalog` with name/Hipparcos lookups, magnitude filters, known-distance subset. Also done: iOS app target (XcodeGen) with a live `CelestialCore` proof-of-life screen. **Next:** ephemeris (Sun/Moon/planets) — the SwiftAA-vs-roll-our-own call lands here (VSOP87/ELP are heavy).
- **Phase 3:** Sensor fusion — map device pointing to the celestial sphere; a debug crosshair that names what it's aimed at.
- **Phase 4:** The rendered sky dome + AR "point at the sky" mode (Sky mode).
- **Phase 5:** Tap-to-detail astrophysical data sheets.
- **Phase 6:** Astrology module — zodiac overlay, natal charts, transits, aspects.
- **Phase 7:** **Galaxy Map mode** — free-fly 3D star field (real near-field stars + stylized galaxy backdrop + exoplanets). Its own Metal renderer over the shared data engine.
- **Phase 8:** Beauty + performance pass (Metal), accessibility, iPad.

## Open questions
- Final name (+ App Store availability check).
- `SwiftAA` dependency or implement the math ourselves?
- Astrology accuracy bar — and how to source ephemeris for it without Swiss Ephemeris licensing trouble.
- AR via raw CoreMotion overlay vs. ARKit camera passthrough?
