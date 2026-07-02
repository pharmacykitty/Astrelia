# Accessibility — Spec (deferred implementation)

> Status: **spec only — to be implemented later** (per owner). Drafted 2026-06-28.
> Goal: make Astrolabe usable with VoiceOver, Dynamic Type, Reduce Motion, and high
> contrast, without diluting the "luminous instrument" look. The hard part is that the
> app's signature content is drawn in `Canvas`/Metal, which is invisible to assistive
> tech by default.

---

## Current state (audit, 2026-06-28)

- Only **14 of ~60** view files reference `accessibility*` at all.
- **No Dynamic Type:** 62 hardcoded `.font(.system(size:))` calls; **zero**
  `ScaledMetric` / `dynamicTypeSize` / `.font(... relativeTo:)`.
- **Canvas/Metal content has no representation:** the chart wheel (`ChartWheel`), the 3D
  sphere (`CelestialSphereView`), the Galaxy Map (`GalaxyMetalView` + `metalAnnotations`),
  and the Sky view (`ContentView.skyCanvas`) expose nothing to VoiceOver.
- **Reduce Motion** is honored in exactly one file (`App/Catalog/SystemView.swift`). The
  auto-spinning sphere, the ~8 s idle guided-tour auto-start, and the galaxy fly-throughs
  all animate unconditionally.
- Tap targets are mostly fine (the codebase uses `Theme.controlSize = 44` and 44×44 hit areas
  on close buttons), but several `Canvas`-tap affordances have no a11y equivalent.

---

## Principles

1. **Represent, don't redraw.** For each Canvas/Metal surface, supply an
   `.accessibilityRepresentation { … }` (or an `accessibilityElement(children:)` overlay) built
   from data we already compute. We frequently already have the textual form — e.g.
   `SphereGuideSheet` lists every placement; the chart's `positions`/`aspects` are structured.
2. **Respect the system.** Gate motion on `@Environment(\.accessibilityReduceMotion)` (OR'd with
   the `motion.respectReduceMotion` preference from `docs/preferences-spec.md`).
3. **Scale text.** Move to relative fonts; reserve absolute sizes for *glyph rendering inside
   Canvas* only (where layout math needs a fixed metric — there, use `ScaledMetric`).
4. **Keep it beautiful.** Accessibility additions are overlays / traits / representations; they
   must not change the default visual output.

---

## Work items

### A. Dynamic Type
- Replace chrome/text `.font(.system(size: N, weight:))` with semantic styles
  (`.headline`, `.caption`, …) or `.system(size: N, relativeTo: .body)` where a size is needed.
- For **Canvas-internal** label sizes (sphere glyphs, galaxy labels, sky star labels), introduce
  `@ScaledMetric` anchors so they grow with the user's setting; cap growth to avoid collision
  blowups (the de-collision code in `CelestialSphereView.freeLabelPosition` and
  `ContentView`'s label placer will need the scaled sizes fed in).
- Test at `accessibilityExtraExtraExtraLarge`; verify reading sheets, Tonight, chart detail,
  catalog, and Settings reflow without truncation.

### B. VoiceOver representations
- **`ChartWheel`** → `.accessibilityRepresentation` that's a list: "Sun in Leo, 14 degrees, 10th
  house" per body, then aspects. Reuse `chart.positions` / `chart.aspects`.
- **`CelestialSphereView`** → represent as the `SphereGuideSheet` placements list; expose the
  guided-tour captions as an accessibility announcement sequence. Each planet tap-target should
  have an `accessibilityLabel`/`accessibilityValue` ("Mars, 3 degrees Capricorn, house 4,
  retrograde") with an action to open its reading.
- **Galaxy Map** → represent the **selection** and the visible **landmarks** as a list ("Orion
  Nebula, emission nebula, 1344 light-years; double-tap to fly here"). The free-fly/orbit gestures
  need an alternative: VoiceOver users get a list of "Fly to…" actions instead of drag.
- **Sky view** → expose the bottom-panel readout (already text) and make "Pointing N 12°, alt
  +30°" an accessibility value; tapped star identification should post an announcement.

### C. Reduce Motion
- `CelestialSphereView`: when reduced, **don't auto-spin** and **don't auto-start the tour**;
  hold a static, legible pose (front-on). Time-travel "play" becomes step buttons.
- `GalaxyMapView`: shorten/disable eased fly-tos to instant cuts.
- `MenuBackground` twinkle and any pulsing (the tightest-aspect pulse) freeze.

### D. Contrast & color
- Provide `@Environment(\.colorSchemeContrast)`-aware variants: the many `.white.opacity(0.4–0.6)`
  secondary texts fail WCAG on the dark gradient at the low end — bump to ≥0.7 under increased
  contrast.
- Don't rely on color alone for aspect harmony (blue/red) — VoiceOver already gets the name;
  for low-vision sighted users, the existing glyphs + labels suffice, but verify the dignity
  badges (green/red) carry text too (they do: `dignity.label`).

### E. Labels & traits sweep
- Audit every `Image(systemName:)`-only button for `.accessibilityLabel` (many `CircleIconButton`
  already pass a `label:` — confirm it maps to the a11y label).
- Decorative Canvas backgrounds → `.accessibilityHidden(true)` (the reticle already is).

---

## Testing
- Manual: full VoiceOver pass of each top-level screen; Accessibility Inspector audit (run it in
  the simulator) for contrast + missing labels.
- Add the **Accessibility Audit** XCTest (`app.performAccessibilityAudit()`) once a UI test target
  exists (see backlog: no UI test target today).
- Snapshot at the largest Dynamic Type size via a harness arg.

## Out of scope (for the first a11y pass)
- Full Switch Control optimization, Voice Control custom labels, and braille-specific tuning.
- Audio Graphs / sonification of the sky (a nice future idea, not v1).
