# Data verification pass — 2026-07-30

A correctness audit of what the app *displays*, in three layers: the math core
(unit tests), the datasets and new formatting code (exhaustive local scans), and
the live sky claims (cross-checked against external references — timeanddate.com,
USNO conventions — for New York, 2026-07-30). Two real defects were found and
fixed; two systematic caveats were documented and backlogged.

## Verified clean

- **CelestialCore**: all 79 tests in 20 suites pass (Meeus worked examples,
  topocentric Moon, refraction, AstroEvents geometry) — now 81 with the two new
  almanac tests below.
- **Bayer formatter** (`StarFacts.formattedDesignation`, new): run against every
  designation-shaped string in `stars.bin` — 2,939/2,947 map to Greek
  (`9Alp CMa → α CMa`, `Alp1Cen → α¹ Cen`, `Kap1Scl → κ¹ Scl`); the 8 remainder
  are variable-star / lowercase-Bayer forms (`R CrB`, `EZ Aqr`, `h CrA`…) that
  correctly pass through unchanged. No mangled outputs.
- **Meteor showers**: all nine showers' peak dates, ZHRs, and radiants match the
  IMO working list (Delta Aquariids peaked "tonight" Jul 30 ✓).
- **Landmarks**: all ~29 distances spot-checked against literature — every one
  within accepted ranges (Sgr A* 26.7k ly, M42 1,344 ly, Pleiades 444 ly,
  Cyg X-1 7,200 ly, LMC 163k ly…).
- **Tonight's Moon**: reference says full moon was Jul 29 10:35 EDT; the app's
  "Full Moon · 100% lit · waning" at 99.6% illumination is honest rounding plus
  a ≥96% naming bucket. Position "to the S, 30° high" at 01:16 EDT matches the
  almanac meridian passing (01:32 at 30.6°). `MoonPhaseDisc` limb orientation
  verified: waxing lights the right limb, waning the left (N-hemisphere).
- **Planet rise/set** vs timeanddate (NYC): Mars and Venus within 1 minute;
  Mercury/Jupiter/Saturn within 3–4 (5-minute sampling + convention differences).
- **Sim-screenshot times** are the sim's `-05` clock for an NYC observer — a
  snapshot artifact, not a bug (rise/set format in device-local time).

## Fixed (CelestialCore + tests)

1. **Sunrise/sunset ~2 min late/early** — `VisibleSky` used the refraction-only
   horizon (−0.5667°) for the Sun; sunrise is defined by the *upper limb*, i.e.
   centre at −50′ (Meeus ch. 15). Added `RiseSet.sunHorizon = −0.8333°`.
   Confirmed against almanac: app 05:52 → now 05:50 EDT.
2. **Moonrise/set up to ~10 min off** — the Moon's geocentric scan also used
   −0.5667°, but geocentric moonrise must offset parallax:
   `RiseSet.moonHorizon = +0.125°` (Meeus mean). Both fixes are pinned by new
   reference tests (`testSunriseSunsetMatchAlmanacNYC` ±2 min,
   `testMoonRiseSetMatchAlmanacNYC` ±6 min — the Moon's actual parallax varies).

## Documented caveats (backlogged, not bugs)

- **V-band luminosity → understated radius for extreme stars**: HYG's `lum` has
  no bolometric correction, so Betelgeuse shows ~13k L☉ / ≈268 R☉ vs literature
  ~100k L☉(bol) / ~640–950 R☉. Derivation math is unit-tested and correct; the
  input is visual-band. Fact copy now says "visible light" (accurate); proper fix
  (BC(B−V) in `Astrophysics`) is in `improvement-backlog.md`.
- **Hipparcos-era distances**: catalog-faithful but dated for a few famous stars
  (Betelgeuse 498 ly vs modern ~550). Noted in the backlog with the Gaia caveat.
