# tools/

Offline asset tooling. Not part of the app build — run by hand to produce data that
gets bundled under `App/Resources/`.

## nebula_bake.py — image → particle dataset

Turns a real public-domain telescope photo into the particle cloud the Galaxy Map
renders for a deep-sky landmark, so the object takes on its **true shape** while
staying in our additive-sprite aesthetic. The photo is **never shipped** — only the
derived `.nbl` points (positions + sampled colours).

```sh
pip install pillow
# Fetch a public-domain source (NASA images API example: Orion / M42):
python3 - <<'PY'
import urllib.request, json
m = json.loads(urllib.request.urlopen("https://images-api.nasa.gov/asset/PIA01322").read())
url = next(h["href"] for h in m["collection"]["items"] if h["href"].endswith("large.jpg"))
open("m42_src.jpg","wb").write(urllib.request.urlopen(url).read())
PY
# Bake → bundled dataset + a preview PNG to eyeball the shape:
python3 tools/nebula_bake.py m42_src.jpg App/Resources/Nebulae/m42.nbl --preview m42_preview.png
```

Then map the landmark id → `.nbl` in the app (see `NebulaModel`/`appendLandmarkSprites`
in `App/Screens/Galaxy/`) and add the image credit to `SourceCatalog`
(`App/Screens/AboutView.swift`).

### Licensing — read before baking
Only bake from images whose **derivative you can ship**:
- **NASA / NASA-JPL / STScI** imagery — public domain. No obligations (credit anyway).
- **ESA/Hubble, ESO** — CC BY 4.0: fine commercially **with attribution** in the
  Sources screen.
- **DSS** and some survey plates — non-commercial clauses; avoid.

Record the source `nasa_id`/URL + credit next to each bundled `.nbl`.

### `.nbl` format (little-endian)
```
magic 'NBL2' (4 bytes) | uint32 gasCount | uint32 dustCount
gas:  gasCount  × float32 x, y, r, g, b   (x,y in [-1,1], y up; colour 0..1)
dust: dustCount × float32 x, y
```
The app places the sheet facing Earth at the landmark's real position/scale and
synthesises per-particle depth (front-on = the photo's shape; orbit = volumetric).
