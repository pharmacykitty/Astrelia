# Exoplanet Sublayer — Specification

> Spec for the Galaxy Map's **planetary-system** sublayer ("fly to a star, see its planets").
> Pre-implementation, drafted 2026-06-27. Decisions in §0 are the working plan; revise here.
> Complements `CLAUDE.md` (Phase 7) and the Galaxy Map (`App/Screens/GalaxyMapView.swift`).

The goal: when you reach a star that hosts known planets, you can drop into a **System View**
that shows the host star and its real planets — orbits, sizes, types, the habitable zone — so
the user can *appreciate solar systems* with real data, not just a dot in the galaxy.

---

## 0. Working decisions (v1)

| # | Decision | Choice |
|---|---|---|
| 1 | **Data source** | NASA Exoplanet Archive — *Planetary Systems* (PS) table. Public domain. |
| 2 | **Scope v1** | Confirmed planets only. Default parameter set per planet (the PS "default flag" row). |
| 3 | **Bundled, not live** | Ship a curated snapshot as a bundled resource (like the star catalog). Refresh at build time, not runtime. Note the snapshot date + attribution. |
| 4 | **Self-contained systems** | Each bundled system carries its own host-star data (so faint hosts like TRAPPIST-1, which aren't in `hyg_stars.csv`, still work). Cross-link to a catalog star when one exists. |
| 5 | **Separate scale** | Systems are AU-scale; the galaxy is parsec-scale (1 AU ≈ 4.85×10⁻⁶ pc). We do **not** render planets inline in the 3D galaxy. A star with planets is *badged*; tapping through opens a dedicated **System View** at its own scale. |
| 6 | **Renderer** | Reuse SwiftUI `Canvas` (consistent with the rest), top-down orbital view. Metal later if needed. |

---

## 1. Data source & ingestion

**NASA Exoplanet Archive — Planetary Systems (PS).** TAP/CSV API, e.g.:

```
https://exoplanetarchive.ipac.caltech.edu/TAP/sync?query=
  select pl_name,hostname,hd_name,hip_name,gaia_id,
         sy_dist,ra,dec,
         st_spectype,st_teff,st_rad,st_mass,st_lum,
         pl_orbsmax,pl_orbper,pl_orbeccen,pl_rade,pl_bmasse,pl_eqt,
         disc_year,discoverymethod,default_flag
  from ps where default_flag=1 and pl_controv_flag=0
  &format=csv
```

~5,800 confirmed planets across ~4,300 systems → a few MB CSV; trim to the columns above and
round floats (same approach as `hyg_stars.csv`).

**Key fields**

| Field | Meaning | Use |
|---|---|---|
| `hostname` | host star name | system id + display |
| `hip_name` / `hd_name` / `gaia_id` | host designations | **cross-match** to HYG (`hipparcos`, `henryDraper`) |
| `ra`, `dec`, `sy_dist` | host position (deg, pc) | place the system / fallback match, distance |
| `st_spectype`,`st_teff`,`st_rad`,`st_mass`,`st_lum` | host star physical | render host + habitable zone |
| `pl_orbsmax` | semi-major axis (AU) | orbit radius |
| `pl_orbper` | orbital period (days) | orbital animation |
| `pl_orbeccen` | eccentricity | orbit ellipse |
| `pl_rade` | planet radius (Earth radii) | planet size (log-scaled) |
| `pl_bmasse` | planet mass (Earth masses) | detail / type hint |
| `pl_eqt` | equilibrium temp (K) | colour / "temperate" hint |
| `discoverymethod`,`disc_year` | discovery | detail panel |

**Missing data is normal.** Many planets lack `pl_orbsmax`, `pl_rade`, or `pl_orbeccen`.
Fallbacks: derive `a` from period + host mass (Kepler's third law) when `pl_orbsmax` is absent;
default eccentricity 0; default radius from mass via a mass–radius relation, else a placeholder.

---

## 2. Cross-match to the star catalog

For each system, link the host to a `Star` in `hyg_stars.csv` when possible:

1. By `hip_name` → `Star.hipparcos`.
2. Else by `hd_name` → `Star.henryDraper`.
3. Else by position (RA/Dec within ~2″ and similar distance).

- **Matched** hosts (bright, in our catalog): the Galaxy Map can badge that star's `id`. Build a
  `Set<Int>` of host star ids at load for cheap "has planets?" checks.
- **Unmatched** hosts (faint, e.g. TRAPPIST-1): still fully usable via the bundled self-contained
  system; they appear in the Catalog's "Systems" list and via search, just not as a galaxy badge
  (they're below the magnitude cut anyway).

---

## 3. Data model (App layer, `App/Catalog/`)

```swift
struct PlanetarySystem: Identifiable {
    let id: String                 // hostname
    let hostName: String
    let hostStarID: Int?           // HYG id when cross-matched
    let distanceParsecs: Double?
    let raDegrees, decDegrees: Double
    let spectralType: String?
    let stellarTempK: Double?      // st_teff  → host colour
    let stellarRadiusSun: Double?  // st_rad
    let stellarLuminositySun: Double?  // st_lum (linear) → habitable zone
    let planets: [Exoplanet]
}

struct Exoplanet: Identifiable {
    let id: String                 // pl_name
    let name: String
    let semiMajorAxisAU: Double
    let eccentricity: Double
    let radiusEarth: Double?
    let massEarth: Double?
    let periodDays: Double?
    let equilibriumTempK: Double?
    let discoveryMethod: String?
    let discoveryYear: Int?
}
```

Loader mirrors `StarCatalogStore`: parse the bundled CSV off-main once into `[PlanetarySystem]`
plus a `[String: PlanetarySystem]` (by hostname) and `Set<Int>` of cross-matched host ids.

---

## 4. System View (rendering)

A dedicated screen, opened from a host star or from the Catalog. **Top-down orbital view**, its
own scale (independent of the parsec galaxy).

**Layout & scale**
- Host star at centre; planets on orbital ellipses from `a` (+ `e`).
- Radial scale: **logarithmic in AU** so inner + outer planets both fit (real systems span
  0.01–30+ AU). Show an AU ruler / ring labels.
- Planet glyph size: **log-scaled from `radiusEarth`** (Earth and Jupiter must both be visible),
  with a floor; colour by a simple type bucket:
  - `radius < 1.6 R⊕` → rocky (grey/tan)
  - `1.6–4 R⊕` → ice/Neptune-like (cyan)
  - `> 4 R⊕` → gas giant (banded tan/orange)
  - tint by `pl_eqt` for hot (red) vs temperate vs cold (blue).
- Host star colour from `st_teff` (reuse the star colour ramp).

**Habitable zone**
- Shade the conservative HZ ring from stellar luminosity:
  inner ≈ √(L/1.1) AU, outer ≈ √(L/0.53) AU (L in solar units; Kopparapu-style approximation).
- Planets inside the HZ get a subtle "temperate" marker.

**Interaction**
- Tap a planet → detail panel (radius, mass, period, `a`, eccentricity, temp, discovery
  method/year, "× Earth" comparisons).
- Optional **orbital animation**: advance mean anomaly by `2π·dt/period` (TimelineView, kept off
  the interactive controls like the rest of the app). Toggle on/off; default gentle motion.
- Pinch to zoom the AU scale; the Solar System shown for comparison scale optionally.

---

## 5. Integration points

- **Galaxy Map**: stars whose `id ∈ hostStarIDs` get a small orbit-ring badge. The star's
  selection card gains a **"View System"** button → System View. (Cheap: a `Set<Int>` lookup in
  the existing star draw/tap path.)
- **Catalog**: a new **"Systems"** section / filter listing `PlanetarySystem`s (searchable by host
  or planet name), each → System View. Famous systems surfaced first (TRAPPIST-1, Kepler-90,
  51 Pegasi, Proxima Centauri, TOI-700…).
- **Sky mode** (later): host stars that are naked-eye could badge in the dome too.

---

## 6. Phases

1. **Ingest + bundle** the PS snapshot (`exoplanets.csv`), loader + cross-match, `Set<Int>` badge set.
2. **Galaxy Map badge** + "View System" entry point.
3. **System View v1**: static orbital view (orbits, sized/coloured planets, host, labels, detail).
4. **Habitable zone** shading + temperate markers.
5. **Orbital animation** + AU ruler + Solar-System comparison.
6. **Polish**: missing-data fallbacks (Kepler `a`, mass–radius), multi-planet de-clutter, Catalog
   "Systems" section.

---

## 7. Open questions

- Snapshot size vs. completeness — bundle all confirmed (~few MB) or a curated/representative subset first?
- Refresh cadence (the archive grows weekly) — manual re-snapshot at release is fine for v1.
- Multi-star (circumbinary) systems — show both stars or simplify to the barycentre for v1?
- Whether to also bundle the **Solar System** as a hand-authored `PlanetarySystem` for a familiar anchor.

---

## Sources
- NASA Exoplanet Archive, *Planetary Systems* table & TAP service — https://exoplanetarchive.ipac.caltech.edu/ (public domain; cite in the About screen).
- Habitable-zone approximation: Kopparapu et al. (2013), simplified luminosity form.
