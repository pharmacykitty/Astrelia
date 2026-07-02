# Localization — Spec (deferred implementation)

> Status: **spec only.** Drafted 2026-06-28. Target languages the owner can verify:
> **English (base)** and **Spanish**. Others only if a trusted translator reviews them —
> machine translation of astrology/astronomy copy is risky (the interpretation corpus
> is nuanced and tone-sensitive).

---

## Current state

- **Everything is hardcoded English.** No String Catalog, no `NSLocalizedString`,
  no `LocalizedStringKey` usage beyond SwiftUI's implicit `Text("literal")` (which *is*
  localizable once a catalog exists, but nothing is extracted yet).
- The **interpretation corpus** lives in Swift dictionaries in
  `Packages/Astrology/Sources/Astrology/Interpretation/Interpretation.swift` (keyword tables:
  `theme`, `signTone`, `houseDomain`, `aspectDynamic`, `signGift`, `signEdge`, `houseFocus`,
  plus the sentence-composing functions). This is **not** SwiftUI text — it's library code
  returning `String`, so it won't be picked up by a String Catalog automatically.
- Glyphs (zodiac, planets) are universal and need **no** translation.
- Numbers/dates: mostly use `.formatted()` / `DateFormatter`, which localize, but several
  custom format strings (`String(format: "%.1f ly · …")`) bake in `.` decimal and English unit
  abbreviations.

---

## Strategy

Two distinct localization problems, handled differently:

### 1. UI chrome strings → String Catalog (`.xcstrings`)
- Add a `Localizable.xcstrings` to the app target; enable **"Use Compiler to Extract Swift
  Strings."** SwiftUI `Text("…")`, `Label`, button titles, nav titles, etc. get extracted.
- Audit `String(format:)` and string interpolation used for **display** — convert to
  `String(localized:)` with interpolation, e.g.
  `String(localized: "\(ly, format: .number.precision(.fractionLength(1))) ly")`, so number and
  unit are placed per-locale.
- Add `es` to the catalog; translate. Keep an eye on **string growth** (Spanish runs ~20–30%
  longer) — re-test the de-collision label code and fixed-width readouts.
- Pluralization: use the catalog's plural variants for "1 star / N stars",
  "rises in 1 day / N days", meteor "peaks in N days", etc. (several of these are currently
  hand-built in `TonightView`/`CatalogView`).

### 2. Interpretation corpus → a localized content layer in the `Astrology` package
The interpretation text is **data, not UI**, and is the bulk of the translation effort.

- Move the keyword tables + sentence templates behind a **`InterpretationStrings` provider**
  keyed by `Locale`. Options:
  - **(a) Bundled `.strings`/`.xcstrings` in the package** (`Bundle.module`), one table per
    language; the composing functions look up keys instead of literals. Cleanest; keeps the
    engine deterministic and the package self-contained.
  - **(b) Per-language Swift files** (`InterpretationEN.swift`, `InterpretationES.swift`)
    conforming to a protocol. Simpler tooling, but heavier to maintain.
- **Recommendation: (a).** Refactor `Interpretation` so every authored phrase is a lookup;
  ship `en` + `es` tables in `Packages/Astrology/Sources/Astrology/Resources/`. Add
  `resources: [.process("Resources")]` to `Package.swift` and load via `Bundle.module`.
- **Grammar caveat:** Spanish has gender/agreement that English templates ignore
  (e.g. "an X way" → article + adjective agreement). The composed-sentence approach
  (`planetInSign` glues fragments) may produce awkward Spanish. Plan for **whole-sentence
  templates per (body×sign) family** in `es` where gluing breaks, rather than translating
  fragments. Budget translator time for this, not just string swaps.

---

## Scope / phasing

**Phase L1 — infrastructure (no visible change):**
- Add the String Catalog, extract chrome strings, confirm `en` still builds identically.
- Refactor `Interpretation` to a lookup-backed provider with the `en` table (behavior-preserving;
  the existing unit tests in `AstrologyTests` should still pass).

**Phase L2 — Spanish:**
- Translate chrome `.xcstrings` → `es`.
- Translate the interpretation tables → `es`, with whole-sentence overrides where gluing fails.
- Localize unit abbreviations and number/date formats.

**Phase L3 — QA:**
- Run the app with `-AppleLanguages (es)` launch arg; screenshot every screen.
- Verify label de-collision, fixed-width readouts, and Dynamic Type still hold with longer strings.

---

## Things that must stay un-localized
- Glyphs (`ZodiacSign.glyph`, `AstroBody.glyph`) and the FE0E text-presentation rule.
- Catalog **proper names** (star/landmark designations: "Betelgeuse", "M42", "Sgr A*").
- Source attributions in `AboutView` (credit text is legal/canonical; leave in English unless a
  source provides an official localized credit).
- Math, JD/coordinate internals.

## Testing
- A pseudo-locale pass (`-AppleLocale` with accented/long pseudo-text) to catch truncation early.
- Snapshot `-snapshotAstro detail` and the reading sheet in `es`.
- Keep `en` as the source of truth; `es` strings missing → fall back to `en` (catalog default).
