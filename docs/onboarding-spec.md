# First-Launch Onboarding — Spec

> Status: **planned.** Drafted 2026-06-28. Goal: replace the current cold start (a black
> sky gated on a bare location-permission prompt) with a short, beautiful first-run that
> sets context, earns the permissions it needs *with reasons*, and lands the user in the
> right place.

---

## Current cold start (the problem)

On first launch `ContentView` appears and immediately needs location + motion. Until those
resolve, `skyStatusOverlay` shows a glyph + "Allow location access…" over an empty sky. There's:
- no explanation of **what the app is** or **why** it wants location/motion/camera,
- no graceful path for a user who **denies** location (the sky just stays empty),
- no first taste of the app's range (Tonight, Galaxy, Astrology) — the menu is undiscovered.

System permission dialogs fire with no pre-context, which hurts grant rates and feels abrupt.

---

## Design

A **3–4 screen** full-screen flow shown **once** (gated by an `AppPreferences` flag
`onboarding.completedVersion`; re-show only on major redesigns by bumping the version). Visual
language = the existing menu (`MenuBackground` starfield, serif wordmark, `LuminousGlyph`,
per-feature tints). No emoji; SF Symbols + glyphs.

### Flow

1. **Welcome.** Wordmark "Astrolabe" + "Chart the heavens." One line on the dual nature:
   *"A real planetarium and a full astrology layer — the same sky, two ways of seeing it."*
   Primary button **Continue**, subtle **Skip** (top-trailing) that jumps straight to the app
   (still triggers permission *as needed*, just without pre-context).

2. **What you can do.** Three compact cards mirroring the menu tints:
   *Point at the sky* (Sky/AR), *Fly the galaxy* (Galaxy Map), *Read your chart* (Astrology).
   Sets expectations and surfaces breadth before the user lands on one screen.

3. **Location (pre-permission priming).** Explain *before* the system sheet: *"Astrolabe uses
   your location to place the real Sun, Moon, planets and stars in your sky. It never leaves your
   device."* Button **Enable location** → triggers the real `CoreLocation` request. A **Not now**
   secondary path that:
   - sets up the **home-location fallback** (reuse `PlaceSearch` to let them pick a city), or
   - proceeds and lets them use Galaxy/Astrology, which don't need live GPS.
   (Motion permission is implicit via CoreMotion the first time Sky mode runs; mention it here in
   one line so it isn't a surprise. Camera is requested **lazily** only when AR mode is first
   chosen — do **not** ask for camera during onboarding.)

4. **(Optional) Make it yours.** Offer to create a first birth chart (deep-link to
   `ChartEditorView`) *or* "Maybe later." Keeps the astrology hook visible without forcing it.
   Could be merged into screen 2 if a 3-screen flow is preferred.

End → set `onboarding.completedVersion`, dismiss into the app. If they enabled location, land in
**Sky**; if they skipped/denied, consider landing on **Tonight** (works with the home fallback)
or the **menu** so the empty-sky dead-end is avoided.

---

## Permission priming rules (important for grant rates)

- **Never** fire a system permission dialog cold. Always show our own context screen first,
  then request on an explicit button tap.
- **Camera** is requested **only** when the user first switches to AR mode (not in onboarding) —
  the `NSCameraUsageDescription` string already exists in `project.yml`.
- If location is **denied**, the app must remain useful: route to Tonight/Galaxy/Astrology and
  let `AppPreferences.location.home` stand in. The existing `skyStatus` "Open Settings" path stays
  as the recovery for Sky mode.

---

## Implementation notes

- New `App/Onboarding/OnboardingView.swift` presented as a `fullScreenCover` from
  `AstrolabeApp`/`ContentView` when `!prefs.onboardingCompleted`. Keep it **out** of the
  `TimelineView` render loop.
- Storage: `onboarding.completedVersion: Int` in `AppPreferences` (see preferences spec).
- Respect Reduce Motion (no auto-animating starfield drift; static is fine) per a11y spec.
- Localizable from day one — all copy via `Text("…")` so the String Catalog picks it up
  (see localization spec).
- A debug launch arg `-forceOnboarding` to re-show it for screenshots/QA, and `-skipOnboarding`
  for the snapshot harnesses (which must not hit it).

## Testing
- First-launch on a clean simulator: flow shows once, doesn't re-show on relaunch.
- Deny-location path stays useful (lands somewhere non-empty).
- `-forceOnboarding` snapshot of each screen.

## Out of scope
- Account creation / sign-in (the app is local-only).
- A guided tour of each feature in situ (the in-app guides — `SphereGuideSheet`, Glossary — cover
  depth already; onboarding stays short).
