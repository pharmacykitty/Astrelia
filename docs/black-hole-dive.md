# Black-Hole Dive — falling into Sagittarius A\*

> Research + design for a cinematic "fly into Sgr A\*" sequence in the Galaxy Map.
> Two halves: (1) **what physics says you'd see and experience**, and (2) **how to
> render it in Metal** inside the existing Galaxy Map renderer. Keep in sync with
> `docs/galaxy-map.md` and the renderer in `App/Screens/Galaxy/`.
>
> ✅ **REBUILT & IN THE APP (2026-07-02) — verified on simulator, frame-by-frame.**
> (The 2026-07-01 build was removed, then rebuilt from this doc the next day as the
> **easter egg**: free-fly across ~12 rs of Sgr A\* and the plunge takes over. No button,
> no card action — you have to fly in.) Current architecture:
>
> - **In-map lensing, always on** — `App/Screens/Galaxy/GalaxyLensing.metal` +
>   `GalaxyMetalRenderer`. The sprite scene renders to an offscreen colour+depth target;
>   a full-screen post-pass marches **Schwarzschild null geodesics** (rs-units, adaptive
>   step, 240 cap) for rays near the hole and applies the **closed-form weak-field
>   deflection (α ≈ 2rs/b)** for every other ray, so bending decays smoothly to zero with
>   no seam. Escaped rays sample the offscreen scene where they now point (the real galaxy
>   lenses into Einstein rings), falling back to a **2048×1024 equirect panorama** baked
>   from the hole (`bake_vertex/fragment`, re-baked per scene version) + a procedural warm
>   bulge ambient (which fades with β so the plunge isn't washed out). The procedural disc:
>   temp ramp, per-pixel Keplerian **Doppler beaming**, gravitational redshift, and
>   band-noise that **carves filament gaps** (alpha driven by the texture, so the disc reads
>   as fire-streams, not fog). Shadow = capture; photon ring falls out of the geometry.
>   `GalaxyCamera` carries the hole (Sgr A\* `positionParsecs`, stylised `rs` = the
>   landmark's catalogued ~0.92 pc, disc 3–10 rs in the galactic plane). Sprite-side,
>   Sgr A\* keeps only a warm beacon (`GalaxyMapView` `.blackHole` case); microquasars keep
>   the old sprite model.
> - **Performance** — the expensive pixels are the ones whose rays integrate geodesics
>   (≈ the hole's projected influence disc; the whole frame once the camera is inside
>   it). `lensScale` budgets that count per frame (~380k px sim / ~1.3M px device) and
>   renders scene+lens into **internal reduced-resolution textures**, with a final
>   `blit_fragment` upscale to the native drawable — so frame time stays flat all the
>   way in (without the budget, the approach band just outside the influence radius
>   marched nearly the full native frame and froze the app in `currentDrawable`).
>   Never change the MTKView's `contentScaleFactor` for this (it corrupts SwiftUI's
>   update graph — AttributeGraph cycle — and wedges the window); the internal-texture
>   route has no UIKit side effects. Far from the hole the lens pass is engaged only
>   while its influence region spans ≥ ~a pixel (else the sprite path renders straight
>   to the drawable, zero overhead).
> - **The dive is renderer-owned** — `DiveChannel` (imperative box) hands the fly-loop's
>   trigger to the renderer; `applyDiveCamera()` recomputes pose + `DiveStage` uniforms
>   per display-link frame as **pure functions of wall-clock time** (`DiveTimeline` in
>   `BlackHoleDive.swift`). SwiftUI only narrates (HUD at ~4 Hz). This matters twice: the
>   60 Hz @State camera churn can wedge SwiftUI entirely (observed on simulator), and the
>   dive must not depend on a SwiftUI render to start or advance. Time-anchored progress
>   (stalls can't speed the fall), ~30 s total.
> - **Beats** (`DiveTimeline.stage`): β 0.19→0.992 with **inverse relativistic aberration**
>   (screen ray → rest-frame ray, negative β — the forward map blacks the frame out; the
>   inverse shrinks the shadow while the sky crowds bright around it) + Doppler headlight;
>   equirect `bakeMix` ramps in before heavy aberration; the camera genuinely falls,
>   **11.5 → 7.0 rs** (the shadow grows the whole way; in portrait it spans the screen
>   inside ~8 rs and inverse aberration holds it at bay), with an accelerating roll,
>   a widening FOV, and warped disc-swirl time (the outside universe fast-forwards ~5×);
>   `aperture` collapses the outside universe after the crossing (p = 0.60); `spaghetti`
>   radial stretch + global redshift inside; white flash → **eject**: the camera rewinds to
>   an orbit outside, facing the hole, with an epilogue caption ("Nothing that enters ever
>   leaves — the simulation has been rewound."). A β-gated **soft tone-map knee** keeps the
>   photon ring white-hot while the stacked boosts roll off filmically. Reduce Motion
>   softens aberration + stretch. HUD: speed %c, real-km distance, time-dilation ×, and the
>   12.8 s countdown; Skip button always present.
> - **Debug**: `-galaxyBH` opens the map at Sgr A\* (70 pc); `-close` parks at 24 pc
>   (the heaviest march band); `-galaxyBH -dive` spawns free-fly at 16 rs inbound so the
>   trigger fires; `-fpsLog` prints frame rate + lens scale every ~2 s; `-dumpDive`
>   writes the lens output to Documents every 2.5 s (the GPU's ground truth — sim
>   chrome can wedge mid-dive while the Metal layer plays on). **Always smoke-test new
>   passes with Metal API validation** (`SIMCTL_CHILD_MTL_DEBUG_LAYER=1 simctl launch …`):
>   Xcode runs enable it by default, so an attachment/pixel-format mismatch that sails
>   through a bare `simctl` run traps as a "freeze" the moment the app runs from Xcode
>   (this bit us: the reduced-res lens pass lacked a depth attachment its PSO declared).
>
> **Not yet done:** on-device verification (trigger, perf, HUD liveness), Kerr spin /
> frame-dragging, bake longitude-seam wrap, and the SwiftUI AttributeGraph wedge under
> 60 Hz flight churn (pre-existing; the dive routes around it, manual free-fly on the
> simulator still repros it).

This is the marquee "tap reveals real science" moment: the user free-flies to the
real Sgr A\* marker and chooses to dive. We swap the sprite-billboard black hole
(`drawBlackHole` case in `GalaxyMapView.swift`) for a dedicated full-screen Metal
fragment shader that ray-bends light the way the real spacetime does, staged to match
NASA's 2024 supercomputer visualization.

---

## Part 1 — What is theorized to happen

Target object: **Sagittarius A\***, the Milky Way's central black hole — **~4.3 million
solar masses**, event-horizon diameter **~25 million km (~16 million mi)**, i.e. about
17× the Sun's diameter. This is the exact body NASA modelled, so we can mirror their
numbers. It is a *supermassive* hole, which matters: the bigger the hole, the **gentler
the tidal gradient at the horizon**, so a camera (unlike a small stellar-mass hole)
crosses the horizon intact and is destroyed only well inside.

### Key relativistic effects, in the order they dominate the view

1. **The accretion disk.** A flat, swirling sheet of superheated gas orbiting the hole,
   glowing white-hot on the inner edge grading to orange/red outward. This is the main
   visual anchor on approach.

2. **Gravitational lensing.** The hole bends the paths of passing light. The far side of
   the disk is lifted into view *above and below* the hole (the iconic Interstellar
   "halo over and under the disk"), and the background star field is warped. Light that
   loops the hole produces **multiple images** of the same object.

3. **The black-hole shadow + photon ring.** Dead centre is the **shadow** — a dark disk
   ~2.6× the horizon radius across, where all light paths terminate on the horizon.
   Hugging its edge is the **photon ring**: razor-thin nested images formed by light
   that orbited the hole one or more times before escaping. Brighter on the side where
   the disk rotates **toward** the viewer.

4. **Doppler beaming (relativistic).** The side of the disk rotating toward you is
   blueshifted and **dramatically brightened**; the receding side dims and reddens. As
   the camera itself accelerates inward, light *ahead* of travel brightens and whitens.

5. **Gravitational redshift.** Light climbing out of the well loses energy → reddens and
   dims. Near the horizon a distant clock would see your signals red-shift toward zero.

6. **Relativistic aberration.** As infall speed climbs (NASA's camera hits 99.2% c at the
   horizon), the entire sky — Milky Way arc, Magellanic Clouds, the disk itself — gets
   **squeezed toward a shrinking circle ahead of you**, multiply-imaged at the rim.

7. **Time dilation.** Clocks near the horizon run slow relative to far-away clocks. NASA's
   framing: orbit near the horizon for 6 hours and you return **36 minutes younger** than
   a distant companion. From outside, an infalling object appears to *freeze and fade* at
   the horizon; from the rider's own frame, you sail straight through.

8. **Crossing the horizon.** No local "wall" — nothing special happens to you at the
   moment of crossing for a hole this big. But it is the point of no return: all futures
   now lead inward. The outside universe's light piles up into a brilliant shrinking spot
   behind you.

9. **Spaghettification → singularity.** Tidal stretching (head pulled harder than feet)
   grows without bound as you approach the centre. For Sgr A\*, NASA's timing: from
   horizon crossing, the singularity is **~12.8 seconds** away, with ~128,000 km left to
   fall — and stretching ends the camera in the final instants.

### NASA's staged approach (our cinematic beats)

NASA's [Beyond the Brink](https://svs.gsfc.nasa.gov/14585/) plunge, computed on the
Discover supercomputer (~10 TB of data), runs these stages — a ready-made storyboard:

| Stage | Speed | What dominates the frame |
|---|---|---|
| Approach (70M mi out) | 19% c | Disk as a flat swirling cloud; thin orange photon rings; lensing starts |
| Midway | 41–62% c | Doppler boosting whitens the center-ahead; aberration pulls sky/disk inward; Magellanic Clouds appear as multiply-imaged copies |
| Critical zone | 69–76% c | Milky Way arc + most of the disk compressed near center; photon rings flare |
| Horizon crossing | 99.2% c | Outside universe collapses to a bright shrinking point behind; point of no return |
| Inside | — | ~12.8 s to the singularity; tidal stretch → spaghettification → end |

---

## Part 2 — Replicating it in the app (Metal)

### Why this needs a new pipeline

The Galaxy Map renders **everything** as instanced billboarded soft-sprites
(`GalaxyShaders.metal`: `sprite_vertex` + additive/overlay fragments). The current
black hole (`GalaxyMapView.swift` `case .blackHole`, ~line 777) is ~370 sprites: an
accretion-disc gas ring with a fake Doppler term, a sprite photon ring, a soft halo,
and one dark overlay disk for the horizon. That's fine as a *distant landmark*, but
sprites can't bend light, so they can't do lensing, the photon ring, aberration, or the
shadow. The dive needs a **full-screen ray-bending fragment shader** — a second, special
pass that takes over only for the dive.

**Design principle:** keep it a self-contained *cutscene mode*, not a change to the
per-frame galaxy renderer. The dive freezes free-fly, runs its own shader + timeline,
and on exit returns the camera to the orbit view. This keeps the 60fps sprite path
untouched and the heavy shader on-screen only while diving.

### The shader: screen-space photon ray-bending

Run a full-screen quad. For each pixel, build a view ray and integrate its bending
through curved spacetime, then shade whatever it hits (disk, horizon, or background).

**Geometry — Schwarzschild is enough.** Frame-dragging (Kerr spin) is a refinement; a
non-rotating (Schwarzschild) approximation already gives the shadow, photon ring,
lensed disk halo, and multiple images. Two viable methods:

- **(A) Geodesic raymarch (accurate, heavier).** March each ray in small steps, at each
  step applying an acceleration toward the hole derived from the photon's conserved
  energy/angular momentum (effective-potential form). Stop when the ray (i) falls inside
  the horizon → black, (ii) crosses the thin disk plane within `[r_in, r_out]` → shade
  disk, or (iii) escapes to large radius → sample background. **Adaptive step size**
  (small near the hole, large far away) is the key perf lever. ~100–300 steps/ray near
  the hole.

- **(B) Analytic deflection (fast, approximate).** Skip integration: deflect the ray by
  the closed-form bending angle as a function of impact parameter `b`
  (α ≈ 2·rs/b in the weak field, with a stronger-field fit near the photon sphere),
  then do a single disk-plane intersection + background lookup of the bent ray. Much
  cheaper; good enough for a phone if the camera path is curated. **Recommended starting
  point for mobile**, upgrade to (A) only if it reads as flat.

**Shading the disk.** Procedural, in the disk's own plane:
- Radial temperature ramp: hot-white inner (`r_in` ≈ ISCO) → orange → dim red outer.
- Orbital velocity for **Doppler**: `boost = (1 + β·cosθ)^3` style brightening on the
  approaching limb, redshift on the receding limb (reuse the real `dop` idea already in
  the sprite code, but per-pixel and physically directional).
- Gravitational redshift factor from the emission radius.
- Turbulent noise (a couple of octaves) scrolling with orbital phase so the gas swirls.
- The **lensed far side** falls out for free: rays that pass over/under the hole and bend
  back down hit the disk's underside → the halo appears automatically. No extra code.

**The shadow + photon ring** also fall out for free from the geometry: rays that end on
the horizon are black (shadow); rays grazing the photon sphere wind multiple times and
sample the disk repeatedly, producing the bright thin ring at the shadow's edge.

**Background.** The bent escaping ray needs something to sample. Options, cheapest first:
1. Procedural star field + a baked Milky-Way band in the shader (self-contained, no I/O).
2. **Bake a cubemap** of the current Galaxy Map view (stars + Milky Way + Magellanic
   Clouds) once when the dive starts, then sample it with the bent ray direction — this
   makes the lensed, multiply-imaged background be *our actual galaxy*, which is the
   magic. Render the existing sprite scene into a cube texture in 6 passes at dive start.

### Mapping the timeline (drive it from Swift, feed the shader uniforms)

A `BlackHoleDive` controller (Swift, `@Observable`) owns a `progress` 0→1 over ~25–40 s
and pushes uniforms each frame. The shader stays "dumb"; Swift sequences the beats:

```
struct DiveUniforms {
    float4x4 invViewProj;   // to build per-pixel rays
    float3   camPos;        // distance to hole drives everything
    float    rs;            // Schwarzschild radius (scene units)
    float    diskInner, diskOuter;
    float    beta;          // infall speed v/c → aberration + Doppler ahead
    float    diskBeta;      // disk orbital speed → limb Doppler
    float    time;          // disk swirl animation
    float    spaghetti;     // 0…1 radial-stretch warp, ramps after horizon
    float    redshift;      // global red/dim as horizon nears
    float    apertureFade;  // outside-universe collapse to a point / fade to white→black
}
```

- **Approach → critical zone:** ramp `camPos` inward and `beta` 0.19→0.99. Aberration =
  warp the ray directions toward the travel axis by `beta` (squeezes the whole frame into
  a shrinking forward circle). Doppler-ahead brightening via `beta`.
- **Horizon crossing:** `apertureFade` collapses the escaping-background contribution to a
  brilliant shrinking spot; flip an internal "inside" flag.
- **Inside:** ramp `spaghetti` — a screen-space **radial stretch** (vertical elongation +
  chromatic smear) standing in for tidal stretching — while `redshift` and vignette close
  down, then a final white-then-black flash → the singularity. Cut back to the map.

Sync the app's time-scrubber / UI clock to *slow* during the near-horizon beats to sell
**time dilation** (and optionally show the "you aged N seconds less" readout NASA cites).

### Triggering & UX

- Add a **"Dive in"** action on the Sgr A\* selection card (next to "Fly here"), shown
  only for `lm.id == "sgr-a"` (and optionally the microquasars, sans the curated SMBH
  numbers).
- Optionally **auto-arm** when free-fly brings the camera within N parsecs of Sgr A\* —
  show a "Cross the horizon?" prompt rather than diving unprompted.
- A persistent **"numbers → intuition" HUD** during the dive (mirrors the app's
  accessibility-first ethos): live speed (% c), distance to horizon, time-dilation factor,
  "12.8 s to singularity" countdown after crossing. Reuses the `PlanetFacts`/`StarFacts`
  relatable-comparison style.
- **Skip / exit** button always present; Reduce Motion → offer a gentler, slower,
  lower-distortion variant (honor the existing motion settings).

### Performance (this runs on an A-series phone GPU)

- **Render the dive pass at reduced resolution** (½ or ⅔) into an offscreen texture, then
  upscale — heavy per-pixel integration doesn't need native retina.
- **Adaptive step count** by distance to the hole; cap steps hard. Use `half` precision in
  the shader where the dynamic range allows.
- Start with **method (B) analytic deflection**; only move to full geodesic march (A) if
  it looks flat, and keep it gated to capable devices.
- The dive is a **bounded cutscene**, so a momentary framerate dip is acceptable in a way a
  steady-state map would not tolerate — but target a smooth 30–60fps at reduced res.
- Files: new `App/Screens/Galaxy/BlackHoleDive.metal` (the lensing fragment shader) +
  `BlackHoleDiveRenderer.swift` (own `MTKView` pass, offscreen target, cubemap bake) +
  `BlackHoleDiveController.swift` (timeline/uniforms) + a SwiftUI overlay for the HUD.
  Mirror the camera-relative-coords + log-depth lessons from `GalaxyMetalRenderer`.

### Accuracy honesty (project convention)

Like the rest of the Galaxy Map: **the object is real** (Sgr A\*'s mass, horizon size,
distance are correct and label-able), and the lensing/disk are a **physically-motivated
but stylized** real-time approximation — not the offline GR ray-trace NASA ran. Tag the
sequence accordingly in copy, and credit NASA SVS "Beyond the Brink" as the inspiration
in `App/Screens/AboutView.swift` (`SourceCatalog`) per the sources-current rule in
`CLAUDE.md`.

---

## Sources

- NASA Science — [New NASA Black Hole Visualization Takes Viewers Beyond the Brink](https://science.nasa.gov/universe/black-holes/supermassive-black-holes/new-nasa-black-hole-visualization-takes-viewers-beyond-the-brink/)
- NASA Scientific Visualization Studio — [Beyond the Brink: Tracking a Simulated Plunge into a Black Hole](https://svs.gsfc.nasa.gov/14585/) and [the 360° plunge](https://svs.gsfc.nasa.gov/14576/)
- Live Science — [Epic NASA video takes you to the heart of a black hole](https://www.livescience.com/space/black-holes/epic-nasa-video-takes-you-to-the-heart-of-a-black-hole-and-destroys-you-in-seconds)
- James et al., [*Gravitational Lensing by Spinning Black Holes* (the Interstellar / DNGR paper)](https://arxiv.org/pdf/1502.03808) — far-side disk halo, lensing maps
- [Black Hole Shadows, Photon Rings, and Lensing Rings](https://arxiv.org/pdf/1906.00873) — shadow + nested photon-ring structure
- Real-time shader references: [Kerr WebGL ray-tracer (frame dragging, Doppler, volumetric disk)](https://github.com/SushantGagneja/Black-Hole-simulation), [Metal ray-traced black hole sim](https://github.com/Selkomark/Blackhole-Sim), [CS184 black-hole raymarcher writeup](https://celticspwn.github.io/CS184FinalProject/final.html)
