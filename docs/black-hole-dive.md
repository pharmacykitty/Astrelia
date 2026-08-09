# Black-Hole Dive — falling into Sagittarius A\*

> Research + design for a cinematic "fly into Sgr A\*" sequence in the Galaxy Map.
> Two halves: (1) **what physics says you'd see and experience**, and (2) **how to
> render it in Metal** inside the existing Galaxy Map renderer. Keep in sync with
> `docs/galaxy-map.md` and the renderer in `App/Screens/Galaxy/`.
>
> ✅ **REBUILT & IN THE APP (2026-07-02) — verified on simulator, frame-by-frame.**
> (The 2026-07-01 build was removed, then rebuilt from this doc the next day as the
> **easter egg**: free-fly across ~6 rs of Sgr A\* — the point of no return — and gravity
> takes over. No button, no card action, no cinematic camera: the fall is SIMULATED from
> your actual position and velocity.) Current architecture:
>
> - **In-map lensing, always on** — `App/Screens/Galaxy/GalaxyLensing.metal` +
>   `GalaxyMetalRenderer`. The sprite scene renders to an offscreen colour+depth target;
>   a full-screen post-pass marches **Schwarzschild null geodesics** (rs-units, adaptive
>   step, 240 cap) for rays near the hole and applies the **closed-form weak-field
>   deflection (α ≈ 2rs/b)** for every other ray, so bending decays smoothly to zero with
>   no seam. Escaped rays sample the offscreen scene where they now point (the real galaxy
>   lenses into Einstein rings), falling back to a **2048×1024 equirect panorama baked
>   from the CAMERA** (`bake_vertex/fragment` — re-baked per scene version and when the
>   camera moves ≥5% of its hole distance, rate-limited; camera-centred since 2026-08-08:
>   the old hole-centred bake's parallax mismatch made the lensed region read as a
>   stitched-on object). Soft world-scale **core-glow sprites within 400 pc of the hole
>   are culled from the bake** — lensed, an extended bright glow double-images into two
>   round lobes ("the two bubbles"); the lensed sky keeps stars/grain (structure reads
>   as bending) while the direct view keeps the glow. The base bake sample is
>   **tangentially sheared** (5 taps about the hole axis, arc ∝ bend) so lensed images
>   stretch; a trace un-lensed **foreground veil** (blurred scene at the original screen
>   position) keeps fog continuity, incl. a faint wash on the shadow. Plus a procedural
>   warm bulge ambient (which fades with β so the plunge isn't washed out). The procedural disc:
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
>   When the camera rests ~0.6 s the budget doubles (**idle-resolve**): motion hides
>   the softness, a parked view gets crispness back the moment you stop.
>   Never change the MTKView's `contentScaleFactor` for this (it corrupts SwiftUI's
>   update graph — AttributeGraph cycle — and wedges the window); the internal-texture
>   route has no UIKit side effects. Far from the hole the lens pass is engaged only
>   while its influence region spans ≥ ~a pixel (else the sprite path renders straight
>   to the drawable, zero overhead).
> - **The dive is a SIMULATION the renderer integrates** (`DivePhysics` in
>   `BlackHoleDive.swift`): crossing ~6 rs in free flight hands your actual position and
>   velocity to `DiveChannel`; `applyDiveCamera(dt:)` integrates a Newtonian-styled pull
>   per display-link frame (entry speed clamped so a hot approach can't skip the show; the
>   fall from 6 rs takes ~5–9 s). No repositioning, no aim cut — you fall the way you flew,
>   the view easing toward the velocity direction with a slow β-scaled roll. Every effect
>   is a function of the radius: **β = √(rs/r)** (the real free-fall law) drives inverse
>   relativistic aberration (0.5×β) + the Doppler headlight; the disc-swirl clock
>   fast-forwards with β² (accumulated, no phase pops); the disc flares as a **photon
>   pile-up blaze at the crossing**; inside, redshift/spaghetti run the narrative radius
>   down Sgr A\*'s real **12.8 s** to the singularity, the last light dying to true black
>   before the flash → **rewind**: an orbit just outside the trigger (8 rs), facing the
>   hole, with the epilogue caption. SwiftUI only narrates (HUD at a few Hz from the
>   channel's radius: %c, real km, dilation ×, the countdown; Skip always present) — the
>   dive must not depend on a SwiftUI render (60 Hz @State churn can wedge it, observed on
>   simulator). **Visualization floor:** the camera pose holds at ~4.5 rs
>   (`renderFloorRs`) while the narrative keeps falling — inside that, the whole forward
>   view lies within the shadow (the escape cone points backward): physically true, but a
>   black screen. Reduce Motion softens aberration, stretch, and roll.
> - **Debug**: `-galaxyBH` opens the map at Sgr A\* (70 pc); `-close` parks at 24 pc
>   (the heaviest march band); `-galaxyBH -dive` spawns free-fly at 10 rs inbound so the
>   trigger fires; `-fpsLog` prints frame rate + lens scale every ~2 s; `-dumpDive`
>   writes the lens output to Documents every 2.5 s (the GPU's ground truth — sim
>   chrome can wedge mid-dive while the Metal layer plays on). **Always smoke-test new
>   passes with Metal API validation** (`SIMCTL_CHILD_MTL_DEBUG_LAYER=1 simctl launch …`):
>   Xcode runs enable it by default, so an attachment/pixel-format mismatch that sails
>   through a bare `simctl` run traps as a "freeze" the moment the app runs from Xcode
>   (this bit us: the reduced-res lens pass lacked a depth attachment its PSO declared).
>
> **Interior rebuilt 2026-07-31** (Elysia: the old interior "feels broken" — GPU frame
> dumps confirmed it degraded into posterized olive/red stills). The interior beat is
> now the **tunnel plunge**: the view stays forward (falling), and the `aperture`
> uniform rides the aberration warp **positive** (net `clamp(-0.6β + 1.45·aperture)`,
> to +0.9) — the forward view MAGNIFIES continuously through the 12.8 s, the shadow
> swallowing the frame outward while the disc's fire-streams and the lensed sky race
> past the edges. Then the **hue-preserving** redshift (blend toward an ember of the
> pixel's own luminance, quadratic fade — the old channel-kill posterized) reddens the
> last light to the flash. Tidal stretch capped at ~2.3× (6× magnified the reduced-res
> target into smears); hash dither on output kills the 8-bit banding; surviving
> background dims gently with aperture + a warm chroma wash (magnified equirect texels
> rainbow-band otherwise). **Failed first attempt, kept for the record:** a 180°
> look-back flip + inverse-aberration "collapse dome" — compression of the sky toward
> the view centre is optically identical to receding; it read as zooming AWAY.
> `-dive` harness throttle 0.05 → 0.3 (the trigger took ~a minute to fire;
> screenshots mid-"dive" were actually the stalled approach).
>
> **Palette + interior pass 2026-08-04** (sim-verified frame-by-frame, informed by a
> research sweep over NASA SVS 14585, Hamilton/JILA interior visualizations, ScienceClic,
> Riazuelo, oseiskar and the DNGR paper):
> - **NASA-fire tonemap** (`bh_fireTone`): the disc's accumulated HDR light maps its
>   luminance through a blackbody-style ramp (black → deep red → orange → amber; white
>   only at photon-ring intensities, lum ≳ 23) with ~30% of the pixel's own hue kept
>   (Doppler limb asymmetry survives). Replaces the channel-wise knee, which let stacked
>   lensed crossings clip to cream sheets. **Parked, the raw HDR light is kept** (the
>   approved crisp orange disc + white-hot ring); the tonemap crossfades in with β.
> - **Doppler beam cap in the interior** (`beamCap` 2.2 → ~1.15 with aperture): rays
>   winding near the photon sphere cross the disc dozens of times, each at max beaming —
>   uncapped, the magnified interior accumulates luminance in the hundreds. The disc also
>   takes the headlight boost at half strength (pre-tonemap), and the headlight now
>   applies to disc and background separately.
> - **Mipmapped sky bake** + ANALYTIC mip level (dive state + bend amount — never
>   derivative-based auto-lod, which flips per pixel in the march zone and sprays
>   coloured grain): magnified/minified panorama stars render as soft dots, not blue
>   confetti. Bake dimmed hard as β builds (knee + 0.72 dim; parked untouched) — NASA's
>   sky is near-black with a thin star ribbon.
> - **Interior death is centre-first** (Hamilton: fore/aft redshifts and dies first, the
>   sideways sky survives longest, slightly blueshifted): the redshift ember weights by
>   screen-axial distance, the frame-edge streams cool subtly — the waist-band read
>   within the tunnel composition. Ember is contrast-deepening (pow 1.6 on luminance:
>   dim mush → black, filaments stay saturated) — the flat blend made a copper wall.
> - Disc flare moved to the **photon-sphere crossing** (r = 1.5 rs, was 1.05).
> - **`-dumpDive` writes OPAQUE PNGs now** (alpha flattened): the lens target's low
>   interior alpha composites over the map's black backdrop on screen (the MTKView is
>   non-opaque), but PNG viewers matte it over WHITE — the frames read as a white flood
>   that isn't there, which misled a whole tuning session. The RGB channels are the
>   ground truth; never judge dive dumps with alpha intact.
>
> **Council pass 2026-08-04** (an LLM-council review of the rendered filmstrip —
> verdict + transcript in `council-report-2026-08-04.html` / `-transcript-`): root
> finding was that the dive had **no referent** — the bake dims deleted the stars
> along with the glow, so "falling" read as abstract fire. Implemented (sim-verified):
> - **The universe is back.** The bake is unsharp-split per pixel (fine mip − coarse
>   mip): the coarse **glow** still dies with speed as before, the **point stars**
>   are re-added after the dims — streaming past on approach, and inside surviving
>   longest at the **frame edge** (Hamilton's sideways sky; NDC-radius weighting —
>   `dot(screenDir, fwd)` only spans ~0.82–1 across a phone FOV and crushed
>   everything), reddening as they die and guttering out (`life`) so the last star
>   dies just before the flash. Compact bright bake patches (nebulae/nucleus) would
>   survive the split as pale smears — suppressed by their bright *neighbourhood*
>   (coarse luminance) + a per-pixel cap.
> - **Ember floor:** where a ray carries fire, the interior never drops below ~3%
>   luminance (true black on a phone reads as a frozen app); only the flash
>   extinguishes it.
> - **Council must-fix list completed (same day):** (1) the **horizon crossing has a
>   visible event** — a `crossing` uniform (staged in `DivePhysics.stage`, snappy
>   lead-in / ~1.5 s afterglow) drives a white-hot photon-ring flare at b ≈ 2.6 rs
>   in the lens pass; (2) the **flash is warm-capped** (1.22, 1.02, 0.80 — full-frame
>   pure white out of near-black is a photosensitivity risk) and attenuated ×0.45
>   under Reduce Motion, which also softens the crossing pulse; (3) the dark stretch
>   is carried by **`DiveHaptics`** (renderer-owned CoreHaptics heartbeat from the
>   display link — slows with dilation, silent by r ≈ 0.3 so the flash arrives in
>   stillness; skipped under Reduce Motion / no-haptics hardware) and the **HUD
>   countdown becomes the protagonist** inside the horizon (large numeric
>   "seconds to the singularity" in `DiveHUD`).
> - Council items **deliberately not yet built:** discoverability of the easter egg;
>   interruption (call/backgrounding) handling; epilogue share card; Cyg X-1
>   contrast dive; audio drone (haptics shipped first — sound needs a design pass).
>
> **Parked-lens "two bubbles" fix (2026-08-08):** the parked hole read as a dark ball
> plus a detached hoop. Diagnosis (red-tint diagnostic): the dark ball was NOT the
> bake — it was *scene-sampled* bent rays. The lens treats every scene pixel as
> background behind the hole, but the bulge's warm fog also fills the space in FRONT
> of it — deflecting that light punched a dark hole in the fog. Fixes, all β-faded so
> the dive keeps its NASA-dark sky: (1) **un-lensed foreground veil** — the scene
> target is mipmapped and the lens re-composites a blurred sample of the pixel's
> ORIGINAL screen position over content-replaced rays (faint wash over the shadow
> too; the fog is in front of it); (2) **lensed stars while parked** — the unsharp
> star-split now gates on bend as well as dive state, with a tangential 3-tap
> (rotation about the hole axis, arc length ∝ bend) that smears them into the
> signature Einstein arcs; (3) screen→bake feather widened 0.015 → 0.10 and a smooth
> **magnification brightening** toward the ring replaces the isolated hoop.
>
> **Not yet done:** on-device verification (trigger, perf, HUD liveness), Kerr spin /
> frame-dragging, bake longitude-seam wrap, and the SwiftUI AttributeGraph wedge under
> 60 Hz flight churn (pre-existing; the dive routes around it, manual free-fly on the
> simulator still repros it). Note: the `-dive` harness trigger is flaky on the sim —
> roughly one launch in three parks at the spawn pose without falling; relaunch.

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
