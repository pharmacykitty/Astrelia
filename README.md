# Astrolabe

A point-at-the-sky planetarium for iOS with deep astrophysical data and a full
astrology layer — built to be genuinely beautiful.

Raise your phone toward the sky to see the real positions of stars, planets, and
other celestial bodies, accurately computed for your location and the current
instant. Tap anything for as much detail as exists — physical and astrological.

See [`CLAUDE.md`](CLAUDE.md) for the full vision, architecture, and roadmap.

## Layout

- `Packages/CelestialCore` — platform-agnostic astronomy engine (Swift 6, strict
  concurrency, no UI/sensor dependencies). The math/data spine.

## Status

Pre-prototype. Phase 1 (time + coordinate transforms in `CelestialCore`) is next.

## Building

```sh
cd Packages/CelestialCore
swift build
swift test
```
