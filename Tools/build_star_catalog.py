#!/usr/bin/env python3
"""Regenerate App/Resources/stars.bin from the HYG database.

Downloads HYG v4.1 (public domain), keeps stars with a known distance and
magnitude <= MAG_LIMIT, and writes the packed binary catalog read by
`BinaryStarCatalog` (see that file for the exact layout).

Usage:  python3 Tools/build_star_catalog.py [mag_limit]
"""
import csv, io, math, os, struct, sys, urllib.request

HYG_URL = "https://raw.githubusercontent.com/astronexus/HYG-Database/main/hyg/CURRENT/hygdata_v41.csv"
OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Resources", "stars.bin")
MAG_LIMIT = float(sys.argv[1]) if len(sys.argv) > 1 else 7.5
RECORD_FMT = "<iii10fIIII"   # id,hip,hd | ra,dec,dist,x,y,z,mag,absmag,ci,lum | proper,bf,con,spect offsets


def main():
    print(f"Downloading HYG… (mag <= {MAG_LIMIT})")
    raw = urllib.request.urlopen(HYG_URL, timeout=180).read().decode("utf-8")

    table = bytearray()
    offsets = {}
    NIL = 0xFFFFFFFF

    def intern(s):
        if not s:
            return NIL
        if s in offsets:
            return offsets[s]
        off = len(table)
        b = s.encode("utf-8")
        table.extend(struct.pack("<H", len(b)))
        table.extend(b)
        offsets[s] = off
        return off

    def f(x):
        try: return float(x)
        except (TypeError, ValueError): return math.nan

    def i(x):
        try: return int(x)
        except (TypeError, ValueError): return -1

    records = bytearray()
    count = 0
    for row in csv.DictReader(io.StringIO(raw)):
        try:
            dist, mag = float(row["dist"]), float(row["mag"])
        except (TypeError, ValueError):
            continue
        if dist <= 0 or dist >= 100000 or mag > MAG_LIMIT:
            continue
        records.extend(struct.pack(RECORD_FMT,
            i(row["id"]), i(row["hip"]), i(row["hd"]),
            f(row["ra"]), f(row["dec"]), f(row["dist"]),
            f(row["x"]), f(row["y"]), f(row["z"]),
            f(row["mag"]), f(row["absmag"]), f(row["ci"]), f(row["lum"]),
            intern(row["proper"]), intern(row["bf"]), intern(row["con"]), intern(row["spect"])))
        count += 1

    with open(OUT, "wb") as out:
        out.write(b"AST1")
        out.write(struct.pack("<II", count, struct.calcsize(RECORD_FMT)))
        out.write(records)
        out.write(table)
    print(f"Wrote {count} stars -> {os.path.normpath(OUT)} ({os.path.getsize(OUT)} bytes)")


if __name__ == "__main__":
    main()
