# Astrology Module — Feature Plan

> Product/UX plan for the astrology layer (what the user *does*). Companion to
> `docs/astrology-spec.md` (the math/engineering). Drafted 2026-06-27.
> Tiered MVP → v1 → v2 → later. A feature's tier is gated by the spec build phase it needs.

The guiding principle (from `CLAUDE.md`): astrophysics and astrology are **separate
surfaces** — different math, different data, different UI. The user chooses what to see.
But the app's **unique edge** is that both share one real sky engine, so the standout
features (Tier ★) *bridge* the two without blending the math.

---

## ★ The differentiator — astrology meets the real sky

These are what no other astrology app can do, because they ride on the existing AR / Galaxy
Map engine. Highest-leverage; worth protecting in scoping.

- **Live zodiac band in AR.** Overlay the ecliptic and the 12 tropical sign divisions on the
  point-at-the-sky view. "You're looking at 14° Scorpio."
- **Your planets, in the real sky, right now.** Show where the transiting planets (and your
  natal points) actually sit on the dome. Tap Mars in the sky → its current sign, house,
  and the aspects it's making today.
- **Signs vs constellations, honestly.** Toggle the 30° tropical signs against the real IAU
  constellation boundaries to *show* the precession gap (the "your sign is wrong" debate),
  turned into an educational feature instead of an argument.
- **Transit-to-sky.** When a notable transit is exact, let the user physically find that
  planet in the sky. Connects symbol to object.

These need: ecliptic/zodiac overlay in the renderer + planet positions (spec Phase B) + the
existing `SkyCamera`. No chart wheel required — could ship early as a teaser.

---

## Tier 0 — MVP (foundation)

Needs spec Phase A (ASC/MC + easy houses) and B (planets). No interpretation text yet.

- **Birth data entry** — date, time, place. Geocode place → lat/long + **IANA timezone**.
  Handle **"unknown birth time"** (no houses/ASC; fall back to a solar/whole-sign chart).
- **The Big Three** — Sun, Moon, Rising shown prominently (the shareable hook).
- **Natal chart wheel** — planets placed by sign + house, glyphs, degrees, retrograde ℞.
- **Positions table** — each body: sign, exact degree, house, retrograde, dignity (later).
- **Saved profiles** — multiple charts (self, friends, family) via SwiftData.
- **Settings** — house system (Whole Sign / Placidus / Equal / Porphyry), zodiac
  (tropical / sidereal-Lahiri), aspect set + orbs.

## Tier 1 — v1 (a real natal app)

Needs spec Phase C (Placidus + aspects) and D (charts).

- **Aspect grid** — the aspectarian; tap an aspect for its meaning.
- **Chart-shape patterns** — detect stellium, grand trine, T-square, grand cross, yod.
- **Current transits** — today's sky vs the natal chart; transit hits listed by exactness.
- **Moon now** — current Moon sign + phase, void-of-course windows. (Reuses Sun/Moon engine.)
- **Interpretation text** — planet-in-sign, planet-in-house, aspect meanings.
  ⚠️ **Content sourcing is an open decision** — see below.

## Tier 2 — v2 (depth + engagement)

- **Transit timeline / forecast** — upcoming exact aspects ("Saturn squares your Sun on…"),
  calendar view, push notifications.
- **Retrograde tracker** — Mercury-retrograde et al. alerts (high engagement, low effort).
- **Solar & lunar returns** — return charts and dates.
- **Personalized daily reading** — generated from the day's transits to the natal chart.
- **Synastry** — compare two charts (inter-aspects, compatibility).
- **Composite chart** — the relationship's own chart.

## Later — specialist layers

- **Secondary progressions**, solar arc directions.
- **Vedic depth** — nakshatras (27 lunar mansions), Vimshottari dasha, divisional charts
  (vargas). (Sidereal engine already exists from Tier 0; this is content + extra math.)
- **Dignities & traditional** — rulerships, exaltations, triplicities, sect.
- **Fixed stars, Arabic parts** beyond Part of Fortune, midpoints, harmonics.
- **Asteroids / Chiron / Lilith** as selectable bodies.
- **Electional / horary** helpers (planetary hours, etc.).

---

## Cross-cutting decisions that shape the product

1. **Interpretation content — the biggest non-math question.** Options:
   - *Write it ourselves* — slow, but ownable, on-brand, no license risk.
   - *License a corpus* — fast, costs money, check redistribution rights.
   - *Generate with an LLM* — fast and scalable, but needs guardrails for consistency/quality
     and a clear "this is generative" stance. (Astro math stays deterministic regardless.)
   Recommendation: decide before Tier 1; the chart engine (Tier 0) doesn't depend on it, so
   we can ship the wheel + positions first and layer text in.

2. **Tone & framing.** How "believer" vs "for entertainment / cultural-interest"? Affects
   copy, disclaimers, and App Store positioning. Worth an explicit stance early.

3. **AR-bridge priority.** The ★ features are the moat but cost renderer work. Decide whether
   one of them ships in Tier 0 as the signature teaser, or all are held until the natal app
   is solid.

4. **Push notifications.** Retrograde alerts + transit forecasts are the retention engine but
   add a whole notification/permission/scheduling surface. v2, but design data model for it
   earlier.

---

## Dependency map (feature tier → spec phase)

| Feature cluster | Needs spec phase |
|---|---|
| Big Three, wheel, easy houses, profiles | A |
| Full body set, ★ AR planet overlay | B (planets/nodes/retrograde) |
| Aspects, patterns, Placidus, transits | C |
| Natal/transit charts, returns, synastry | D |
| Any chart-wheel / AR overlay UI | E (+ renderer for ★) |
