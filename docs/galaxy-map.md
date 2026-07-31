# Galaxy Map — how it's built

> A 3D fly-through of the real local star field, the stylized Milky Way, curated
> deep-sky landmarks, and exoplanet systems — all rendered through one Metal sprite
> pipeline. This document explains how every layer is made and how the on-screen
> controls hang together.

The guiding principle is **real data in the near field, art in the far field** (the
Phase 7 plan in `CLAUDE.md`):

- **Real:** every catalogued star has a true 3D position (HYG parallax → XYZ parsecs);
  every landmark's *position, distance, physical size and type* are real; exoplanet
  systems come from the NASA Exoplanet Archive.
- **Art:** the Milky Way's spiral structure, and the *morphology* of procedural
  landmarks, are stylized archetypes. Image-baked nebulae get their true shape and
  colour from a real photo (without shipping the photo).

Nothing here is the Sky/AR pipeline — the Galaxy Map is a second, self-contained
renderer that shares only the catalogue data and `CelestialCore` math.

---

## File map

```
App/Screens/GalaxyMapView.swift        # the SwiftUI screen: state, camera, gestures,
                                        #   scene-building, overlay/menu, picking, dive
App/Screens/Galaxy/
  GalaxyMetalRenderer.swift            # MTKView host + render passes + GPU buffers
  GalaxyShaders.metal                  # sprite vertex/fragments (additive, occluder, overlay)
  NebulaModel.swift                    # .nbl loader (NebulaLibrary / NebulaParticleSet)
App/Catalog/
  Landmarks.swift                      # curated deep-sky landmark dataset (+ types/groups)
  Exoplanets.swift                     # ExoplanetStore, PlanetarySystem, hand-authored Sol
  CatalogView.swift                    # searchable catalog → opens the map focused
  SystemView.swift                     # top-down orbital view of a planetary system
App/Resources/
  stars.bin                            # packed HYG catalog (mmap'd; ~109k stars)
  exoplanets.csv                       # NASA Exoplanet Archive snapshot
  Nebulae/*.nbl                        # baked nebula particle datasets (27)
tools/nebula_bake.py                   # photo → .nbl baker (offline; see tools/README.md)
Packages/CelestialCore/.../PointOctree.swift   # spatial index (cull + picking)
```

---

## Coordinate system

One world frame, shared by stars and landmarks: **equatorial XYZ in parsecs, Sun at the
origin.** RA/Dec + distance → XYZ via

```
x = d·cos(dec)·cos(ra)   y = d·cos(dec)·sin(ra)   z = d·sin(dec)
```

(`Landmark.positionParsecs`, and `buildStars` for catalog stars). The galactic centre
sits ~8.2 kpc out at `Galactic.centerPosition`, which is why our real stars are only a
small local bubble against the Milky Way disc. Distances are stored in light-years in
the curated data and converted with `/ 3.2616`.

---

## The star field

`buildStars()` (in `GalaxyMapView`) turns the bundled HYG catalog into `[GalaxyStar]`:

- Keeps stars with a known distance `0 < pc < 100,000`.
- Uses the real HYG `position` (XYZ parsecs) when present, else reconstructs it from
  RA/Dec + distance.
- Computes **absolute magnitude** `M = m − 5·(log₁₀ pc − 1)` and derives a `baseSize`
  from it (brighter → bigger). Colour comes from the B−V index bucketed into a palette
  (`starBucket` / `starPalette`).
- Sorts **brightest-first**, so an array index doubles as a brightness rank (used by the
  level-of-detail cap) and builds the `PointOctree` over the positions.

Stars render as **mode-1 (screen-sized) hard-disc additive sprites**, with a soft white
glow added on the brightest (`magnitude < 1.5`). Crucially, each star's **alpha is
driven by apparent magnitude** (`0.85 − 0.12·(mag−1)`, clamped). With 100k+ additive
sprites a constant alpha blows out to white wherever the cloud is dense; fading the many
faint stars keeps dense regions a soft glow while bright stars stay distinct points.

---

## The Metal renderer

Everything visible is an **instanced, billboarded soft sprite**. `GalaxySprite` is a flat
run of 12 `Float`s (so Swift and Metal layouts match byte-for-byte):

```
position(px,py,pz) · radius · colour(r,g,b,a) · minPixel · maxPixel · softness · mode
```

- **`mode`** — `0` = world-sized (radius scales with `focal/depth`), `1` = screen-sized
  (a screen coefficient ÷ depth, clamped to `[minPixel, maxPixel]`).
- **`softness`** — `0` = hard disc (stars), `1` = soft glow (gas, bloom). The fragment
  shader shapes the falloff with `pow(1−r, mix(0.25, 2.2, softness))`.

Key techniques (`GalaxyShaders.metal` + `GalaxyMetalRenderer.swift`):

- **Camera-relative coordinates.** The view matrix is built with the eye at the origin
  and the GPU subtracts the true camera position per vertex (`u.ex/ey/ez`), so positions
  fed to floats stay small across the galaxy's enormous scale range.
- **Logarithmic depth.** `z = log2(c·w + 1) / log2(c·200000 + 1) · w` — high precision
  near the camera, monotonic out to the galaxy edge.
- **Two blend modes.** Additive `sprite_additive` (ONE, ONE — light accumulates) for
  stars/Milky Way/gas/glows; normal-blend `sprite_overlay` (srcAlpha, 1−srcAlpha) for
  dark **dust** and **event horizons**, which *subtract* light from the additive result
  beneath.

Instances are built once in world space by `buildScene()` from the same catalogue/art
math; the GPU does all projection, so it scales to 100k+ points. The scene is rebuilt
(and `sceneVersion` bumped) only when the data/art actually changes (catalog load,
toggles, exoplanet load).

### Depth occlusion (so clouds hide what's behind them)

Additive light has no natural occlusion — without help, stars *behind* a nebula shine
through it. The fix splits the scene into **four sprite groups** with distinct depth
behavior (`GalaxyScene` + `encodeSprites`):

| Group | Depth state | Contents |
|---|---|---|
| **occluder** | write, `.less` | invisible caps (`sprite_occluder`, colour 0) marking dense, opaque cores |
| **occludee** | test `.lessEqual`, **no write** | catalog stars + Milky Way |
| **landmarkLight** | none | all nebula/landmark light |
| **overlay** | none | dust / event horizons |

- Stars/Milky-Way **test** depth (culled behind a cap) but **never write** it, so they
  still never occlude each other — the loved accumulation-glow is intact.
- Nebula light is drawn **depth-test-free**, so a cloud never self-occludes or dims.
- The depth-writers are **invisible caps** that trace each landmark's *bright* shape
  (subsampled), so genuinely dark gaps — e.g. Pacman's mouth — get no cap and stars
  correctly show through them. Foreground stars (M42 is only 412 pc) stay visible
  because they're nearer than the caps.

Every render pass carries a `.depth32Float` attachment and every pipeline declares the
format, so both the normal map path and the offscreen lensing/dive passes validate.
Caps are emitted in `appendBakedNebula` (bright baked particles where `lum > 0.3`,
subsampled) and `appendLandmarkSprites` (procedural emission lobes, globular cores,
galaxy bulges).

---

## The Milky Way backdrop

`buildBackdrop()` generates a **true-scale four-arm barred spiral** centred on the
galactic centre — pure art, seeded so it's identical run to run. It places spiral-arm
stars, a diffuse inter-arm disc, and a bright bulge (in the galactic plane basis
`Galactic.center`/`inPlane`/`north`), plus a separate **dust** point set carved over the
glow. In `buildScene` each backdrop point becomes a crisp sprite **plus a larger bloom
sprite** (two-pass additive haze + crisp cores), and dust points become normal-blend
overlay sprites. A modest warm nucleus glow sits at the centre. The "Milky Way" toggle in
Options drops the whole backdrop so you can see only real objects.

---

## Landmarks

### The dataset (`Landmarks.swift`)

`Landmarks.all` is a **curated** list (not a full catalog) of ~70 famous deep-sky
objects: emission/planetary nebulae, supernova remnants, open/globular clusters, black
holes, and galaxies (incl. satellites and far galaxies like M31/M51). Each `Landmark`
carries `id`, `name`, `designation`, `type`, real `raDegrees`/`decDegrees`,
`distanceLightYears`, a physical `radiusLightYears` (half-extent for true-scale
rendering), and a one-line `summary`. `LandmarkType` provides the SF Symbol, tint, and a
`LandmarkGroup` rollup (Nebulae / Clusters / Black Holes / Galaxies) for the catalog
dropdowns. `suggestedViewDistance` frames the object when you fly to it.

### Procedural landmarks (`appendLandmarkSprites`)

For landmarks without a baked photo, sprites are generated procedurally — seeded by the
landmark id so each looks identical every run and parallaxes correctly in 3D. A small set
of helpers builds them: `gas()` (soft additive puff), `star()` (point + optional glow),
`embedded()` (young stars in a cloud), `dustPuff()`/`dustLane()` (normal-blend dark), and
`cap()` (invisible depth occluder). An anisotropic `shape()` transform gives each object a
randomized 3D orientation/aspect. Per `LandmarkType`:

- **planetaryNebula** — two-colour shell (hot OIII teal inside, Hα rose at the rim) +
  bipolar lobes + faint halo + a central white-dwarf star.
- **supernovaRemnant** — filamentary Hα/blue rim, brighter knots, faint interior glow,
  and a pulsar for the famous youngsters (Crab, Vela).
- **emissionNebula** — a layered Hα cloud with OIII-energised cores, blue reflection, an
  embedded young cluster, and curated dust lanes (e.g. Trifid's three lanes, Eagle).
  Horsehead is a special case: a **dark pillar** (dust) silhouetted on emission.
- **open/globularCluster** — stars distributed by an age-appropriate population
  (`popColor`), a warm layered core glow + occluder for globulars, bright glowing members,
  and blue reflection nebulosity for the Pleiades.
- **galaxy** — logarithmic spiral arms (young blue stars + pink HII knots + dust), a warm
  bulge + bar, a smooth disc field, and disc-plane dust (reads as the dark lane edge-on,
  e.g. Sombrero).
- **blackHole** — a Doppler-beamed accretion disc (hot-white inner → orange outer), a
  photon ring, a hot halo, relativistic jets for the microquasars, and a dark event
  horizon (overlay). Sgr A* is dimmed.

### Image-baked nebulae (true shape + true colour)

The standout nebulae are **baked from real visible-light photos** so they show their
actual shape and colour. `tools/nebula_bake.py` (run offline) blurs a public-domain /
CC BY 4.0 image, then does density/colour-weighted rejection sampling (brightness^γ,
sub-pixel jitter) to produce a `.nbl` particle dataset — **the photo is never bundled,
only the derived points** (copyright-clean for the App Store). Format:

```
magic 'NBL2' | uint32 gasCount | uint32 dustCount
gas:  gasCount  × float32 x, y, r, g, b   (x,y in [-1,1], y up; colour 0..1)
dust: dustCount × float32 x, y
```

`NebulaLibrary` (`NebulaModel.swift`) maps `landmark.id → .nbl` and loads it.
`appendBakedNebula` orients the normalised sheet **facing Earth** at the landmark's real
position/scale, and synthesises per-particle depth (front-on = the photo's shape; orbit =
volumetric). There is deliberately **no dust overlay** — dark lanes come for free from
gas-density absence. 27 nebulae are baked (`NebulaLibrary.baked`): Orion,
Eagle/Pillars, Lagoon, Trifid, Carina, Tarantula, Crab, Veil, Ring, Helix, Cone, North
America, Bubble, Omega, Lobster, Horsehead, Dumbbell, Little Dumbbell, Southern Ring,
Butterfly, Saturn, Eskimo, Vela, Jellyfish, Pacman, Rosette, California.

**Sprite emission (reworked 2026-07-31 — "sharper, denser, gassy"):** each gas particle
becomes a small soft bloom sprite plus a **wisp** — a detail sprite stretched ~2.6:1 and
oriented along the local filament tangent, computed per nebula from the bake's own
density field (96² luminance histogram → blurred → gradient perpendicular). Wisps and
blooms use a **windowed-gaussian falloff** in `sprite_additive` (softness ≥ 0.7); the
old power falloff's rim made overlaps read as stacked discs. Opacity follows
**lum^1.35, gamma-compressed** with a cap that eases down for physically huge faces
(Carina), and small nebulae **subsample particles + dim alphas by size** so planetaries
(Ring) keep dark interiors instead of saturating. Depth caps are denser (~1500,
`lum > 0.15`) so background stars stop bleeding through mid-brightness gas. Anisotropy
rides in 4 extra floats on `SpriteInstance` (16 total) — **update `SpriteInstanceB` in
`GalaxyLensing.metal` in lockstep** or the lens's offscreen pass scrambles.

**Baking lessons (baked into the workflow):** source *visible-light, not infrared* (IR
gives "off" false colours); no dust overlay on bakes (an overlay punches black holes);
dense bakes stay (~55–60k particles, γ≈1.4) — the *renderer* now subsamples per size.

---

## Sgr A* — gravitational lensing + the dive easter egg

Sagittarius A\* is the one object **not** drawn with sprites: `GalaxyLensing.metal` is a
full-screen post-pass over the sprite scene (rendered to an offscreen target) that marches
Schwarzschild null geodesics near the hole and applies the closed-form weak-field
deflection everywhere else — a real black shadow, photon ring, Doppler-beamed procedural
disc, and Einstein-lensed images of the actual rendered galaxy (screen-space samples, with
a baked 2048×1024 equirect panorama as the out-of-frame fallback). Near the hole the
whole frame is ray-marched, so scene+lens render at reduced internal resolution and a blit
upscales (never via `contentScaleFactor` — that wedges SwiftUI's update graph). Sprite-side
only a warm beacon remains (`.blackHole` case); microquasars keep the sprite model.

**The easter egg:** free-flying across ~6 rs (the point of no return) hands your actual position and velocity to a gravitational free-fall the renderer integrates — renderer-
owned (`DiveChannel` → `applyDiveCamera`, pure functions of wall-clock time), with inverse
relativistic aberration, the universe collapsing at the crossing, tidal stretch, a white
flash, and an eject-with-epilogue. Full design + build notes: **`docs/black-hole-dive.md`**.
Debug: `-galaxyBH` (map at the hole), `-galaxyBH -dive` (auto-plunge), `-dumpDive`
(write lens frames to Documents).

---

## Spatial index (culling + picking)

`CelestialCore.PointOctree` (pure, `Sendable`, unit-tested vs. brute force) is built once
over the star positions in `buildStars`. Each frame the tap-picker queries it with the
camera's **view-frustum planes** (`frustumPlanes`, Gribb–Hartmann) so it only tests
in-view stars instead of all ~109k. The query is conservative — whole in-view subtrees are
added without per-point tests, straddling leaves are over-included, then the existing
screen-bounds cull refines.

---

## Camera & flight

Two cameras share the same data, both with `near 0.05, far 200000` and a ~51° FOV:

- **Orbit** (default) — `yaw`/`pitch`/`distance` around a `target`. Drag to orbit, pinch
  to zoom (`zoomGesture`, clamped 2…60000 pc).
- **Free-fly** (`flyButton`) — a free `eye` + look direction. One finger **steers** around
  a centre reticle; a window-level **two-finger vertical pan** (`TwoFingerVerticalPan`)
  sets a *persistent* `throttle` (−1…1) so you cruise hands-free. Speed is the throttle
  **squared** × `flySpeed` (1540 pc/s), giving fine control near a star and galaxy-crossing
  speed at full tilt. A `flyTask` integrates motion each frame.

`makeViewProjection` (CPU, for picking/annotations) and `makeCamera` (camera-relative,
for the GPU) build the same view two ways. `animateCamera` eases the camera to a new
target/distance/orientation over a duration (smoothstep) rather than teleporting; `flyTo`,
`flyToGalaxy`, and the Catalog focus (`applyInitialFocusIfNeeded`) all route through it.

---

## The on-screen menu

The overlay (`overlay`, drawn over the Metal layer; gestures live on the render layer
below so button taps win) provides:

- **Back / Catalog** buttons, a star-count readout, and a faint **distance-from-Earth**
  readout (`cameraDistanceParsecs` = length of the eye position).
- **Options panel** (`optionsPanel`) — toggles for *Milky Way* and *Planet hosts only*
  (`hostsOnly` filters the star field to known exoplanet hosts + Sun + landmarks), plus
  one-shot *Centre on the Sun* and *Galaxy overview* actions.
- **Free-flight** toggle, with a centre reticle and a speed readout while throttling.
- **Selection card** (`selectionCard`) — tapping the Sun, a star, or a landmark shows its
  facts, a **Fly here** button, and (for the Sun or a known host star) a **View planetary
  system** button. Picking order is landmarks → Sun → stars (octree-culled), nearest
  within a pixel radius wins (`tapGesture`).
- **Annotations** (`metalAnnotations`) — labels, the "Sol" caption, and the selection ring
  stay vector (crisp text) in a lightweight Canvas, projected on the CPU with the same
  view-projection the picker uses. Landmark labels are de-collided.

---

## Exoplanet layer & SystemView

`ExoplanetStore` loads the bundled NASA Exoplanet Archive snapshot
(`exoplanets.csv`, ~6.3k planets / ~4.7k systems) and cross-matches host stars to catalog
stars by HIP. Hosts get cyan badges, and the selection card offers **View planetary
system** → `SystemView`: a top-down orbital view with the host star(s) at centre, planets
on log-AU orbits with always-on labels and Keplerian relative speeds, a habitable zone,
and tap-to-inspect. A hand-authored **Sol** (`SolarSystem` in `Exoplanets.swift`) adds the
planets' major moons (the archive has no exomoons). Full design in
[`docs/exoplanet-spec.md`](exoplanet-spec.md).

---

## Accuracy & licensing

- Landmark **positions, distances, physical sizes and types are real**; procedural
  *morphology* is a stylized archetype, and baked nebulae use a real photo's shape/colour.
- The Milky Way backdrop is art, not catalogued — real stars render in front of it.
- Baked nebulae ship **only derived points**, never the source image. Bake **only** from
  shippable sources: NASA/JPL/STScI (public domain) or ESA/Hubble & ESO & NOIRLab
  (CC BY 4.0, with attribution). Every image credit lives in `SourceCatalog`
  (`App/Screens/AboutView.swift` → About → Sources). See `tools/README.md`.

---

## Practical: adding to the map

**Add a landmark:** append a `Landmark` to `Landmarks.all` with real RA/Dec, distance, and
radius. It immediately renders procedurally (by `type`), is tappable, and appears in the
Catalog. Done.

**Bake a nebula for true shape:**
1. Fetch a shippable visible-light photo (see `tools/README.md`).
2. `python3 tools/nebula_bake.py src.jpg App/Resources/Nebulae/<id>.nbl --preview p.png`
   and eyeball the preview.
3. Add `"<id>": "<id>"` to `NebulaLibrary.baked` (the id must match the `Landmark.id`).
4. `xcodegen generate` so the new `.nbl` is bundled, then build.
5. Add the image credit to `SourceCatalog`.

The renderer needs no changes — `appendBakedNebula` takes over for any landmark with a
baked dataset, and the depth-occlusion caps are generated automatically.
