<div align="center">

# Astrelia

**A planetarium for iOS. Point your phone at the sky, then leave Earth and fly through the galaxy.**

[Get it on the App Store](https://apps.apple.com/app/id6804829721) · free · iOS 26+

</div>

---

Astrelia computes where everything in the sky is for your exact location and the current second, using real ephemeris math instead of a lookup service, and draws it over the sky you're pointing at. Tap a star and it tells you what it knows. When the sky gets small, switch to the galaxy map and fly out through 109,000 real stars, past nebulae rebuilt from telescope photos, to the black hole in the middle.

I built it between June and August 2026 and shipped version 1.0 in September. It's feature-complete and I don't plan to do much more with it, so the code is here for anyone who wants to read it, learn from it or build on it.

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/tonight.png" width="240"><br><sub><b>Tonight</b>, what's up right now</sub></td>
    <td align="center"><img src="docs/screenshots/star.png" width="240"><br><sub><b>Star detail</b>, numbers turned into intuition</sub></td>
    <td align="center"><img src="docs/screenshots/planet.png" width="240"><br><sub><b>Planet detail</b></sub></td>
  </tr>
</table>

## What it does

**Sky mode.** Hold your phone up and about 8,900 naked-eye stars, the constellation lines, the Sun, the Moon and the planets sit where they really are, projected from RA/Dec to altitude and azimuth through CoreMotion. There's an AR version over the camera feed with a one-tap alignment that gets heading error under a degree, and a slider that runs the sky twelve hours forward or back.

**Galaxy map.** About 109,000 HYG stars placed at their true 3D positions from parallax, rendered through a custom Metal sprite pipeline with camera-relative coordinates and a logarithmic depth buffer so nothing jitters at galactic distances. A point octree handles culling and tap picking. The Milky Way itself is stylized, but it's true to scale.

**Nebulae from photographs.** 27 nebulae (Orion, the Eagle's pillars, the Horsehead, the Crab and others) aren't textures. `Tools/nebula_bake.py` turns a visible-light telescope image into roughly 60,000 particles, so face-on you see the photo and from any other angle you're flying through a volume. Only the particles ship; the photos never do.

**Sgr A\*.** The black hole at the centre gravitationally lenses the rendered galaxy behind it with a Schwarzschild geodesic march on the GPU.

**Exoplanets.** Around 6,300 confirmed planets from the NASA Exoplanet Archive, matched to their host stars. Fly to one and open a top-down view of its system with the habitable zone drawn in.

**Tonight, the catalog and constellations.** Moon phase, which planets are up and when, active meteor showers and upcoming events, all computed on device. Search stars, planets and deep-sky objects; every constellation can be rotated in 3D, which is the fastest way to see that a constellation is just stars that happen to line up from here.

## How it's put together

```
App/                  the SwiftUI app and the Metal renderer
  Sky/                sensors, AR, sky projection
  Screens/            Tonight, Catalog, Constellations, Galaxy Map, About
  Catalog/            catalog data and the "relatable facts" layer
  Resources/          stars.bin, exoplanets.csv, constellation lines, nebulae
Tools/                build_star_catalog.py, nebula_bake.py
docs/                 design notes and specs written while building it
project.yml           XcodeGen spec
```

The astronomy engine isn't in this repo. It lives in [AstroPackages](https://github.com/pharmacykitty/AstroPackages) (`CelestialCore`), shared with the sister app [Selenia](https://github.com/pharmacykitty/Selenia). It's pure Swift with no UI or sensor code, Swift 6 strict concurrency throughout, and it's tested against the worked examples in Meeus' *Astronomical Algorithms*.

Some docs in `docs/` describe features that were planned but never built (widgets, onboarding, localization). They're kept as design history.

## Building it

You need Xcode 27 with the iOS 26 SDK and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Check out AstroPackages next to this repo, because `project.yml` points at `../AstroPackages`:

```sh
git clone https://github.com/pharmacykitty/Astrelia.git
git clone https://github.com/pharmacykitty/AstroPackages.git
cd Astrelia
brew install xcodegen
xcodegen generate
open Astrelia.xcodeproj
```

Set `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode) to your own team to run on a device. The simulator works without one, but AR mode needs real hardware.

All the data is committed, so there's nothing to download. To rebuild the star catalog with a different magnitude cutoff, run `python3 Tools/build_star_catalog.py 7.5`.

## License

The code is GPL-3.0 (see `LICENSE`). The bundled data keeps its own licenses: the star catalog is CC BY-SA 4.0 from the HYG database, the constellation lines are BSD-3-Clause from d3-celestial, and the nebulae are derived from ESA/Hubble, ESO and NOIRLab images (CC BY 4.0) and NASA images (public domain). Every source is credited in [`NOTICE.md`](NOTICE.md).
