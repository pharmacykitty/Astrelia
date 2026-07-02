# 3D Celestial Sphere — design notes

> A rotating 3D globe of a chart's sky: the horizon, equator, and ecliptic great
> circles, the zodiac belt, the planets, and aspect chords across the interior.
> Inspired by **Astrolog**'s globe display (the reference GIF). First cut lives in
> `App/Charts/CelestialSphereView.swift`. This is the ★ differentiator: the
> astrophysics sphere married to the astrology chart.

## The idea

Every chart already gives us, for one instant + place: the cardinal angles, house
cusps, and each body's ecliptic longitude (`NatalChart`). To draw the sky as a
globe we put all of it into one **local horizon frame** and spin it.

## Frame & projection

Local horizon frame (matches the GIF — zenith up):

```
x = north,  y = east,  z = zenith
unit(alt, az) = (cos alt·cos az,  cos alt·sin az,  sin alt)
```

Each body: **ecliptic longitude → equatorial** (`CoordinateTransform`, obliquity)
**→ horizontal** (`CoordinateTransform.horizontal`, using the chart's RAMC and
latitude) → the unit vector above. The great circles are just parametric sweeps:

- **Horizon** — `alt = 0`, az 0…360.
- **Equator** — `dec = 0`, RA 0…360, run through the same equatorial→horizontal step.
- **Ecliptic** — `β = 0`, λ 0…360, through ecliptic→equatorial→horizontal.
- **Meridian** — the az 0/180 vertical great circle.

Rotation each frame: **yaw** about the vertical (auto-spin + drag) then **pitch**
(drag), then an **orthographic** projection (the sphere reads as a perfect circle,
like the GIF). Depth = the axis toward the viewer; far-side geometry is drawn
fainter (front/back split per circle) for a real 3D read.

## What's drawn

- **Globe volume**: a radial-gradient fill + blurred blue **atmosphere rim**, so it
  reads as a solid sphere, not a wireframe.
- **Real star field** (HYG, brightest ~900): spectral-coloured by B−V, sized/faded by
  magnitude, far side dimmed. The brightest stars get **diffraction-spike sparkle**.
- **Constellation stick-figures** (d3-celestial RA/Dec polylines, BSD) drawn faint.
- Horizon (white) with **graduated degree ticks** + cardinal labels (N/E/S/W),
  celestial equator (blue), **glowing ecliptic** (green) ringed with the zodiac,
  meridian (dashed). House-cusp ticks on the ecliptic.
- Planets as **glowing colour-coded** glyphs (Sun gold, Mars red, …) with ℞, drawn
  back-to-front and faded on the far side.
- Aspect chords: 3D segments between bodies, coloured by harmony.
- Labels: Z (zenith), AC, MC. Footer: date + coordinates.

Interaction: auto-rotates (~60 s/turn); drag to turn; tap to pause. Geometry is
built once per chart and cached (`.task(id:)`); only the cheap projection runs per
frame, so the ~900 stars + constellations stay smooth.

## Also done

- **House great-circles** — each cusp's ecliptic-longitude meridian (through the
  ecliptic poles), segmenting the globe like orange slices; angular cusps brighter.
- **House numerals** — Roman I–XII at each house's mid-longitude on the ecliptic
  (nudged just inside the band so they don't collide with the zodiac glyphs).
- **Label de-collision** — planet glyph labels are spread to avoid overlap in tight
  stelliums, with a thin leader line back to the dot when moved.
- **Planet ecliptic latitude** — bodies are plotted at their real β (ayanamsa-invariant).
- **Milky Way band** — galactic-equator glow behind the stars.

### Comprehension & motion pass (★ "I don't know how to read it" fix)

- **Aspect storytelling** — chords are coloured by harmony (blue flowing / red tense /
  white conjunction / purple minor); the single **tightest aspect gently pulses**;
  tapping a chord opens its reading; selecting a planet **dims every aspect it
  isn't part of**.
- **Guided tour** — an auto-advancing narration (menu → *Guided tour*) that spotlights
  the Sun, Moon, Rising, then the tightest aspect, each with a one-line plain-language
  caption banner and step dots.
- **Time travel** — a scrubber (menu → *Time travel*) shifts the sky ±24 h and a play
  button runs it; the geometry is rebuilt at `chart` + offset, so the stars, Sun,
  Moon, planets **and** houses wheel in true diurnal motion. The camera holds still
  while time plays so the motion you see is the sky turning, not the camera. Live
  time/offset readout + "Now" reset. `effectiveChart` recomputes a `NatalChart` at the
  offset; the rebuild key quantises the offset to ~3-minute steps.

## Still deferred

- **Depth-sorted occlusion** — additive glow has no depth test, so far-side stars
  shine through near-side gas/globe (we dim by hemisphere as an approximation).
- A **Metal** renderer if Canvas costs too much at 120 fps.

## Why this is the moat

No other astrology app renders the chart as the *real* local sky sphere because
they have no sky engine. We already do (`CelestialCore` + the Galaxy Map renderer),
so this is a small, high-impact addition that only we can ship. See
`docs/astrology-features.md` (★ section).
