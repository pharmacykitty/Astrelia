# Astrology Module — Specification

> Spec for the `Packages/Astrology/` package. Pre-implementation. Derived from research on
> 2026-06-27 (see "Sources" at end). Decisions in §0 are **locked** unless revised here.
> This complements `CLAUDE.md`; it does not replace it.

The astrology layer is a **separate module** from the astrophysics layer (per the project's
core principle: science and symbolism never blend in code). It depends on `CelestialCore`
for ephemeris/coordinate math and nothing depends on it.

---

## 0. Locked decisions (v1)

| # | Decision | Choice |
|---|---|---|
| 1 | **No Swiss Ephemeris.** | Dual AGPL/commercial — incompatible with a closed App Store app. We roll our own astrology math on `CelestialCore`. |
| 2 | **Planet ephemeris source** | Use **SwiftAA (MIT)** for Mercury–Neptune ecliptic longitudes. Astrology math stays ours; we don't hand-port VSOP87 unless SwiftAA proves insufficient. |
| 3 | **House systems v1** | Whole Sign, Placidus, Equal, Porphyry. (Koch / Campanus / Regiomontanus deferred.) |
| 4 | **Zodiac v1** | Tropical default; Sidereal (Lahiri) behind a setting. Architecture supports more ayanamsas. |
| 5 | **Feature scope v1** | Natal chart + current transits. (Progressions / returns / synastry deferred.) |

---

## 1. Dependencies this module needs from `CelestialCore`

Astrology consumes **apparent ecliptic longitudes** (and velocities) of bodies, plus the
Ascendant/MC machinery (LST, obliquity, observer latitude — all already present).

Required, not yet in `CelestialCore`:

- [ ] **Planets Mercury–Neptune** — via SwiftAA (decision §0.2). Expose geocentric apparent
      ecliptic longitude λ and latitude β.
- [ ] **Pluto** — VSOP87 does not cover it. Meeus Ch. 37 polynomial (valid 1885–2099; fine,
      astrology is modern-date only).
- [ ] **Lunar nodes** — Mean Node (polynomial) and True Node (from the Moon's orbit). North
      node = Rahu, South node = Ketu (= North + 180°).
- [ ] **Longitude velocity dλ/dt** — for the retrograde flag and applying/separating aspects.
      Compute by finite difference (λ at t±δ) if no closed form.
- [ ] **Nutation → apparent positions** — already a `CelestialCore` TODO; astrology uses
      *apparent* positions, so prioritise it here. (Mean-equinox is sub-arcmin; acceptable
      for a first cut but note the gap.)

Deferred bodies (post-v1): Chiron, Ceres/Pallas/Juno/Vesta, mean Black Moon Lilith
(lunar apogee), Vertex.

---

## 2. Angles: Ascendant & Midheaven

Foundation of every house system. `RAMC` = Local Apparent Sidereal Time in degrees
(from `CelestialCore`). `ε` = obliquity of date. `φ` = observer geographic latitude.

```
MC  = atan2( sin(RAMC),  cos(RAMC) · cos ε )
ASC = atan2( cos(RAMC),  −( sin(RAMC)·cos ε + tan φ · sin ε ) )
```

Both quadrant-corrected to [0,360). ASC is the rising (eastern) ecliptic point; the
opposite point is the Descendant, and IC = MC + 180°.

---

## 3. House systems

`HouseSystem` is a protocol: given (`ASC`, `MC`, `RAMC`, `ε`, `φ`) → 12 cusp longitudes.

| System | Method | Notes |
|---|---|---|
| **Whole Sign** | House 1 = whole sign containing ASC; each next sign = next house. | MC floats (9th–11th). All latitudes. Hellenistic default. |
| **Equal** | Cusp 1 = ASC°; each cusp +30°. | MC floats. All latitudes. |
| **Porphyry** | Trisect ecliptic arcs ASC→IC and ASC→MC. Pure interpolation. | All latitudes; good fallback. |
| **Placidus** | Trisect diurnal/nocturnal **semi-arcs**; iterative. | Western default. **Undefined above ~66° latitude.** |

### Placidus algorithm (iterative)

Each intermediate cusp (11, 12, 2, 3) sits at a fixed fraction (⅓, ⅔) of the semi-arc of
the ecliptic point on it. The point's semi-arc depends on its declination, which depends on
its own longitude → solve iteratively (converges in a few steps).

```
δ(λ)  = asin( sin ε · sin λ )            // declination of ecliptic point at longitude λ
SA(λ) : cos(SA) = −tan φ · tan δ(λ)      // semi-diurnal arc
```

- Cusp 11 = point whose meridian distance from MC = ⅓·SA; cusp 12 = ⅔·SA.
- Cusps 2, 3 mirror below the horizon, measured from IC.
- Iterate each cusp's longitude until the meridian-distance condition holds.

### High-latitude guard (must-have)

For `|φ| ≳ 66°`, Placidus/Koch are undefined (the ecliptic point never rises). Detect this
and **fall back to Whole Sign or Porphyry** rather than emit garbage/NaN. Users born in
northern Scandinavia, Alaska, etc. must get a valid chart.

---

## 4. Zodiac & ayanamsa

Model longitudes **tropical internally** (what `CelestialCore` produces). Apply a pluggable
transform at the boundary for sidereal:

```
λ_sidereal = λ_tropical − ayanamsa(JD)
```

`Ayanamsa` is a protocol (date-dependent; drifts ~50″/yr — not a constant):

- **Lahiri** (≈24°10′ in 2024) — default sidereal, Indian govt standard. v1.
- Krishnamurti/KP, Raman, Fagan–Bradley — later.

Sign = `floor(λ / 30)` → Aries…Pisces; decan = subdivision within the sign.

---

## 5. Aspects

Angular separation in ecliptic longitude, within a configurable **orb**.

| Class | Aspects (°) |
|---|---|
| Major (Ptolemaic) | Conjunction 0, Sextile 60, Square 90, Trine 120, Opposition 180 |
| Minor | Semisextile 30, Semisquare 45, Quintile 72, Sesquiquadrate 135, Biquintile 144, Quincunx 150 |

Default orbs (configurable; orbs are tradition-dependent):

| Aspect | Orb | Luminary bonus |
|---|---|---|
| Conjunction / Opposition | 8° | +2° if Sun or Moon |
| Trine / Square | 7° | — |
| Sextile | 5° | — |
| Minor | 1–3° | — |

Detection is an O(n²) pass over body pairs (n≈12–15, trivial). Compute **applying vs
separating** from relative longitude velocity — astrologers care about the distinction.

---

## 6. Charts & persistence

- **NatalChart** — pure `Sendable` struct. Store **raw inputs** as source of truth
  (date, time, lat/long, **IANA timezone id**, house system, zodiac/ayanamsa); recompute
  positions. Never persist computed longitudes as truth.
- **Transit** — same machinery with "now" as the moving chart against natal positions.
- **Part of Fortune** — derived, no ephemeris: `ASC + Moon − Sun` (day chart; night chart
  flips Moon/Sun). Inherits the ASC's time-sensitivity.
- Persist via **SwiftData** (app layer), per the project stack. The `Astrology` package
  itself stays pure/UI-free.

### Data gotchas

- **Birth time precision is everything.** ASC moves ~1°/4min; MC, houses, PoF, Vertex all
  depend on exact time.
- **Historical timezones pre-1970 are unreliable.** Use the IANA tz database (Foundation
  `TimeZone`); store birth coordinates + IANA zone, never a raw typed UTC offset.

---

## 7. Proposed package layout

```
Packages/Astrology/                 # depends on CelestialCore only; NO UIKit/SwiftUI
  Zodiac/     Sign, Decan, tropical⇄sidereal, Ayanamsa protocol (Lahiri v1)
  Houses/     HouseSystem protocol → WholeSign, Equal, Porphyry, Placidus
              + Ascendant/MC, high-latitude fallback
  Aspects/    Aspect set, configurable orbs, applying/separating
  Chart/      NatalChart, Transit  (Progressions/Returns/Synastry later)
  Bodies/     node / Lilith / Part of Fortune derivations + retrograde flag
```

---

## 8. Validation

Mirror the `CelestialCore` discipline — every transform tested against a known reference:

- ASC/MC and house cusps → Meeus worked examples + 2–3 reference charts on **astro.com**
  (free, authoritative).
- Aspect detection → hand-checked against a known chart.
- Ayanamsa(JD) → published Lahiri tables.

---

## 9. Phased build

1. **Phase A ✅ — angles & easy houses.** ASC/MC; Whole Sign, Equal, Porphyry. Tropical +
   sidereal. (No new ephemeris — Sun/Moon already exist.) Done.
2. **Phase B ✅ — planets.** `CelestialCore.Planets` (SwiftAA, MIT) for Mercury–Neptune
   (`ApparentGeocentricLongitude`); Pluto via Meeus 37 heliocentric + VSOP87 Earth, reduced
   to geocentric and precessed J2000→date; mean nodes ✅; retrograde ✅ (speed sign).
   Validated: Meeus 33.a (Venus RA/Dec), Mercury/Venus elongation bounds, published Pluto
   ephemeris (1°23′ Aquarius ℞, 2024-07-01). SwiftAA lives in `CelestialCore` (serves the
   Sky view too), not `Astrology`.
3. **Phase C ✅ — Placidus + aspects.** Iterative Placidus with high-latitude fallback;
   aspect engine with configurable orbs (major+minor, luminary bonus, applying/separating).
   Done. (Placidus validated against its own semi-arc definition; revisit with an astro.com
   numeric fixture when convenient.)
4. **Phase D (partial) — charts.** `NatalChart` + Part of Fortune + day/night sect ✅.
   Still: a `Transit` convenience, SwiftData persistence (raw inputs), birth-data entry.
5. **Phase E (first cut ✅) — UI.** `AstrologyView` "Sky Now" + `ChartWheel`. Still: birth
   chart entry, detail sheets, interpretation text.

**Status (2026-06-27):** Phases A, B, C complete; D & E first cut. `swift test` green —
Astrology 22 tests, CelestialCore 32 (incl. planet/Pluto). Charts carry the full body set
(Sun, Moon, Mercury–Pluto, nodes) with retrograde. Remaining: birth-data entry + SwiftData
persistence, transits, interpretation text, sidereal UI toggle, and the ★ AR overlay.

---

## Sources (researched 2026-06-27)

- Swiss Ephemeris licensing — https://www.astro.com/swisseph/swephinfo_e.htm
- SwiftAA (MIT, astronomy only) — https://github.com/onekiloparsec/SwiftAA
- vsmithers1087/SwissEphemeris (GPL, archived Feb 2026) — https://github.com/vsmithers1087/SwissEphemeris
- Astrological aspect — https://en.wikipedia.org/wiki/Astrological_aspect
- House systems explained — https://www.astrochartus.com/blog/house-systems-explained
- House systems implementation guide — https://roxyapi.com/blogs/house-systems-astrology-app-implementation-guide
- Placidus / MC / ASC formulas — https://groups.google.com/g/alt.astrology.moderated/c/FqeqhpUFyH0
- Ayanamsa for developers — https://roxyapi.com/blogs/ayanamsa-lahiri-raman-kp-developers
- Sidereal vs tropical — https://astrosight.ai/learn-astrology/sidereal-vs-tropical-zodiac
- Aspects & orbs — https://www.astrotheme.com/astrology_aspects.php
- VSOP87 accuracy — https://eclipse.gsfc.nasa.gov/help/ve82-predictions.html
- Part of Fortune — https://cafeastrology.com/partoffortune.html
