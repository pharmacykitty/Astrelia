# Design plan — 2026-07-28 (screenshot-based)

A UI-designer pass over every reachable screen, captured in the simulator
(`scratchshots/*.png` — sky, sky-dock, tonight, catalog, figures, about,
star-detail, planet-detail, con3d, galaxy-orion, galaxy-bh). Follows the
2026-07-28 code review + 6 fix sessions (`ui-review-2026-07-28.md`). This doc is
the plan for the *next* rounds; check items off as they land.

## The one-sentence diagnosis

The content screens (Tonight, star/planet detail, About, and above all the
Galaxy Map) already look like a serious instrument; the **sky screen's chrome is
where the "toy" feeling lives**, and its specific cause is **neutral gray
plates** — `ultraThinMaterial`/`quietSurface` over a near-black sky renders as
flat gray slabs (status card, dock plate, bottom message box in `sky.png`) that
sit *on* the night instead of *in* it.

## Principles (settled by the screenshots)

1. **Passive text gets no plate.** The galaxy map's hint line + distance readout
   float bare over a *bright gold* lensed galaxy (`galaxy-bh.png`) and stay
   legible — text + shadow works over far worse backgrounds than the sky HUD
   has. Boxes read as widgets; bare text reads as an instrument.
2. **Glass is for interactive things only** (buttons, dock, sheets) — and over
   this app's near-black content, *neutral* glass is what produces gray soup.
   Interactive surfaces should carry the night's ink, not neutral gray.
3. **The night has one ink.** Where a translucent fill is still needed, derive
   it from the space gradient (deep blue-black, e.g. `Color(red: 0.06,
   green: 0.08, blue: 0.16)` at ~55%) — never `.black.opacity` / bare material.

## Prerequisite decision — Liquid Glass ✅ adopt, scoped

- **Adopt** for interactive chrome: the dock, `CircleIconButton`, the Sky/AR
  control, sheet chrome. iOS 26's `.glassEffect(.regular.tint(...).interactive())`
  inside a `GlassEffectContainer` gives specular/lensing that reads "optical
  instrument," and **glass morphing** (`glassEffectID`) is purpose-built for the
  dock expand/collapse.
- **Not** for passive readouts (principle 1) — and always tinted with the night
  ink (principle 3), because neutral Liquid Glass over black has the same
  gray-soup failure mode as materials.
- **Blocker:** `.glassEffect` is iOS 26+; `project.yml` targets iOS 18.
  Recommendation: **raise deployment target to iOS 26** — the app is
  pre-release with zero users, and this also unlocks the modern APIs deferred in
  the housekeeping session (`ForEach(enumerated())` etc.). Decide before P2/P3.

## P1 — De-gray the sky HUD *(biggest toy→instrument shift, ~1 session)*

Evidence: `sky.png`, `sky-dock.png` — three gray slabs on a blue-black night.

1. **Bottom readout goes bare** (Elysia's instinct, confirmed): kill the
   `quietSurface` box on `bottomPanel`; Sun/Moon rows + pointing line become
   floating text with `.shadow(color: .black.opacity(0.8), radius: 2, y: 1)`.
   Add a bottom **scrim** (black→clear gradient, ~160pt) shown **only in AR
   mode** — the camera feed needs it; the virtual sky doesn't.
2. **Status card shrinks**: "Calibrating motion sensors…" is a huge gray slab
   parked dead-center. Replace with bare floating glyph + one line + spinner
   (shadowed, no card). Same for the bottom "figure-8" message.
3. **Sky/AR segmented picker**: the system control's bright white pill is the
   loudest thing on screen and fights the delicate circle buttons. Replace with
   a custom two-segment capsule in the CircleIconButton language (glass, tinted
   selection ring, not solid white).
4. Where a plate must remain (time scrubber, calibration bar are *interactive*
   → they keep surfaces): switch their fill from neutral material to night ink
   until P3 replaces them with tinted Liquid Glass.

## P2 — Dock v2: persistent, icons-only, no reveal step *(~1 session)*

Evidence: `sky-dock.png`; Elysia: "kinda weird to tap a button to bring out a bar."

The weirdness is **distance**: the trigger (top-left button) and the reveal
(bottom bar) are at opposite corners. Fix by removing the choreography:

- **Persistent icons-only dock** at the bottom (thumb zone) — five tinted
  circles in one slim capsule, **no text labels** (a11y labels stay), **no Menu
  button at all** (frees a control-bar slot).
- **Fades during sky interaction**: while panning/pinching or when the phone is
  raised near-vertical in AR, dock opacity → ~0.25; returns on touch-down near
  it / lowering the phone. Immersion cost ≈ zero, discovery cost ≈ zero.
- With Liquid Glass adopted, the capsule is a `GlassEffectContainer` and the
  five circles morph in/out of it on fade — the "liquid" behavior is exactly
  this pattern.
- Keep `-dockOpen` harness arg meaning "dock at full opacity" for snapshots.

## P3 — Liquid Glass adoption pass *(after the deployment-target decision)*

`CircleIconButton` → `.glassEffect(.regular.tint(tint).interactive())`;
dock capsule + segments per above; sheets/toolbars come free from the system.
Keep the luminous hairline ring as the brand signature *on top of* glass —
that's the identity, glass is just the substrate.

## P4 — Content jewels & bugs *(~1 session, high delight-per-line)*

1. **Tonight's Moon is a flat white disc** (`tonight.png`) — the one dead pixel
   region on the app's best screen. Render the actual phase: shade the disc from
   `illuminatedFraction` + `isWaxing` (Canvas arc — the math is already in
   `MoonPhase`), or minimally the `moonphase.*` SF symbol tinted.
2. **Copy contradiction** (`tonight.png`): header says "Daytime — planets show
   best after sunset" while the card below says "Night · Sunrise at 4:50 AM."
   `isNight` and the day/night card disagree — find and fix (suspect: `isNight`
   derived from device clock vs. statuses computed for the fixed/observer
   location).
3. **`mag -0.0`** (`catalog.png`, Rigil Kentaurus): negative-zero formatting —
   normalize before formatting.
4. **Raw Bayer codes read as database dumps** (`catalog.png`: "9Alp CMa"):
   format to "α CMa" (greek-letter map for the 24 abbreviations — Alp/Bet/Gam…;
   keep Flamsteed number only when there's no Greek letter).
5. **Search capsule overlaps the last row** (`catalog.png`, `figures.png`):
   verify the `safeAreaInset` actually insets the List's content (the last row
   shows through the translucent capsule); if it does, the night-ink fill from
   P1 makes the pass-through read intentional; if not, add bottom padding.

## P5 — Small polish *(fills a spare hour)*

- `figures.png`: thumbnail line color is faint next to row titles — raise the
  figure stroke a step; segmented control restyle comes with P1.3's component.
- `con3d.png` (posed): edge labels clip ("Curca" cut at screen edge) — clamp
  label rects to safe insets like the sky Canvas already does.
- `galaxy-orion.png`: selection card could shorten (summary line-clamp 2) so
  more nebula shows; adopt glass in P3.
- Two yellows on Catalog rows (header star vs row sparkles) — unify.
- Dock label "Figures" vs screen title "Constellations" — decide one name.

## Explicitly good — do not regress (the screenshots prove it)

- The **Galaxy Map** (`galaxy-orion.png`, `galaxy-bh.png`) is the differentiator
  realized: baked nebulae, lensed Sgr A*, floating labels — genuinely
  best-in-class visuals.
- The **detail pages** (`star-detail.png`, `planet-detail.png`): serif titles,
  sparkle facts, HR diagram + size comparison — editorial and beautiful.
- **About/Sources** (`about.png`): the serif + glossary card + licensed-badge
  layout looks like a museum plaque wall; keep.
- The luminous circle buttons and tinted card rims — the brand. P1-P3 quiet the
  *plates*, never the rims.
