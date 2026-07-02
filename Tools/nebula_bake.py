#!/usr/bin/env python3
"""Bake a deep-sky photo into a particle dataset for Astrolabe's Galaxy Map.

The Galaxy Map renders nebulae as clouds of additive billboard sprites. This tool
turns a real (public-domain) telescope image into the *positions and colours* of
those sprites, so a landmark takes on the object's true shape while staying in our
own particle aesthetic. The photo itself is never shipped — only the derived points.

Method:
  1. Blur the image → a density + colour field. Blurring removes foreground point
     stars and keeps the extended nebulosity.
  2. Rejection-sample N "gas" particles weighted by brightness^gamma; each takes its
     colour from the (blurred) pixel.
  3. Sample "dust" particles where the nebula is locally dark (dark veins/lanes),
     for the renderer's light-subtracting overlay pass.
  4. Write a compact little-endian binary (.nbl) and an additive-bloom preview PNG so
     the result can be eyeballed before bundling.

LICENSING: only bake from images you can ship the *derivative* of — NASA imagery is
public domain; ESA/ESO is CC BY 4.0 (attribution required). Record the source +
credit alongside the bundled .nbl and in the in-app Sources screen.

Coordinates: x,y are normalised to [-1, 1] with y up (image centre = origin). The app
places the sheet facing Earth at the landmark's real position and synthesises depth.

.nbl format (little-endian):
  magic 'NBL2' (4 bytes) | uint32 gasCount | uint32 dustCount
  gas:  gasCount  × float32 x, y, r, g, b   (colour 0..1)
  dust: dustCount × float32 x, y

Usage:
  python3 tools/nebula_bake.py SRC.jpg App/Resources/Nebulae/m42.nbl \
      [--gas 17000] [--dust 2600] [--gamma 1.6] [--width 720] [--preview out.png]
"""
import argparse, random, struct, math
from PIL import Image, ImageFilter


def luminance(p):
    return 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]


def bake(src, out, n_gas, n_dust, gamma, width, floor, preview, seed):
    random.seed(seed)
    im = Image.open(src).convert("RGB")
    h = int(im.height * width / im.width)
    im = im.resize((width, h), Image.LANCZOS)

    field = im.filter(ImageFilter.GaussianBlur(radius=3))   # density + colour
    fpx = field.load()
    maxl = max(luminance(fpx[x, y]) for y in range(0, h, 3) for x in range(0, width, 3))

    gas = []
    tries = 0
    while len(gas) < n_gas and tries < n_gas * 80:
        tries += 1
        x = random.randrange(width); y = random.randrange(h)
        p = fpx[x, y]; l = luminance(p)
        if l < floor or random.random() > (l / maxl) ** gamma:
            continue
        # Sub-pixel jitter so particles don't snap to the source pixel grid (smoother).
        nx = ((x + random.random()) / width) * 2 - 1; ny = 1 - ((y + random.random()) / h) * 2
        gas.append((nx, ny, p[0] / 255, p[1] / 255, p[2] / 255))

    # Dust: locally darker than the surrounding glow (dark lanes inside the nebula).
    big = im.filter(ImageFilter.GaussianBlur(radius=14)); bpx = big.load()
    dust = []
    tries = 0
    while len(dust) < n_dust and tries < n_dust * 120:
        tries += 1
        x = random.randrange(width); y = random.randrange(h)
        around = luminance(bpx[x, y]); here = luminance(fpx[x, y])
        if around < 55:
            continue
        deficit = (around - here) / max(around, 1)
        if deficit <= 0 or random.random() > deficit ** 1.3:
            continue
        nx = (x / width) * 2 - 1; ny = 1 - (y / h) * 2
        dust.append((nx, ny))

    with open(out, "wb") as f:
        f.write(b"NBL2")
        f.write(struct.pack("<II", len(gas), len(dust)))
        for nx, ny, r, g, b in gas:
            f.write(struct.pack("<fffff", nx, ny, r, g, b))
        for nx, ny in dust:
            f.write(struct.pack("<ff", nx, ny))
    print(f"wrote {out}: {len(gas)} gas, {len(dust)} dust")

    if preview:
        _preview(gas, dust, width, h, preview)
        print(f"wrote preview {preview}")


def _preview(gas, dust, w, h, path):
    core = [0.0] * (w * h * 3)

    def splat(cx, cy, col, inten, rad):
        s = 2 * (rad * 0.6) ** 2
        for dy in range(-rad, rad + 1):
            yy = cy + dy
            if 0 <= yy < h:
                for dx in range(-rad, rad + 1):
                    xx = cx + dx
                    if 0 <= xx < w:
                        ww = math.exp(-(dx * dx + dy * dy) / s) * inten
                        i = (yy * w + xx) * 3
                        core[i] += col[0] * ww; core[i + 1] += col[1] * ww; core[i + 2] += col[2] * ww

    for nx, ny, r, g, b in gas:
        splat(int((nx + 1) / 2 * w), int((1 - ny) / 2 * h), (r, g, b), 0.45, 3)
    ci = Image.new("RGB", (w, h)); cp = ci.load()
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 3
            cp[x, y] = tuple(min(255, int((1 - math.exp(-core[i + k] * 1.7)) * 255)) for k in range(3))
    bloom = ci.filter(ImageFilter.GaussianBlur(7)); bp = bloom.load(); op = ci.load()
    dmap = [0.0] * (w * h)
    for nx, ny in dust:
        x = int((nx + 1) / 2 * w); y = int((1 - ny) / 2 * h)
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h:
                    dmap[yy * w + xx] = min(1.0, dmap[yy * w + xx] + 0.5 * math.exp(-(dx * dx + dy * dy) / 3.0))
    res = Image.new("RGB", (w, h)); rp = res.load()
    for y in range(h):
        for x in range(w):
            a = op[x, y]; b = bp[x, y]; d = 1 - 0.85 * dmap[y * w + x]
            rp[x, y] = tuple(min(255, int((a[k] + b[k] * 0.7) * d)) for k in range(3))
    res.save(path)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Bake a deep-sky photo into an Astrolabe .nbl particle set.")
    ap.add_argument("src"); ap.add_argument("out")
    ap.add_argument("--gas", type=int, default=17000)
    ap.add_argument("--dust", type=int, default=2600)
    ap.add_argument("--gamma", type=float, default=1.6)
    ap.add_argument("--width", type=int, default=720)
    ap.add_argument("--floor", type=float, default=18.0)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--preview", default=None)
    a = ap.parse_args()
    bake(a.src, a.out, a.gas, a.dust, a.gamma, a.width, a.floor, a.preview, a.seed)
