"""Decode a z12 vector tile and compare its tiles with the GeoJSON tile set."""
import gzip, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kml_to_tiles import load_tiles_geojson


def varint(b, i):
    v = s = 0
    while True:
        c = b[i]; i += 1; v |= (c & 0x7F) << s; s += 7
        if c < 0x80: return v, i


def fields(b):
    i = 0
    while i < len(b):
        k, i = varint(b, i); f, t = k >> 3, k & 7
        if t == 0: v, i = varint(b, i)
        elif t == 2: n, i = varint(b, i); v = b[i:i + n]; i += n
        elif t == 5: v = b[i:i + 4]; i += 4
        elif t == 1: v = b[i:i + 8]; i += 8
        yield f, t, v


def layers(data):
    for f, _, v in fields(data):
        if f == 3:
            name, extent, feats = None, 4096, []
            for lf, _, lv in fields(v):
                if lf == 1: name = lv.decode()
                elif lf == 5: extent = lv
                elif lf == 2: feats.append(lv)
            yield name, extent, feats


def rings(feat):
    geom = b"".join(v for f, _, v in fields(feat) if f == 4)
    ints, i = [], 0
    while i < len(geom):
        v, i = varint(geom, i); ints.append(v)
    out, x, y, i = [], 0, 0, 0
    zz = lambda n: (n >> 1) ^ -(n & 1)
    while i < len(ints):
        cmd, cnt = ints[i] & 7, ints[i] >> 3; i += 1
        if cmd == 1:
            for _ in range(cnt): x += zz(ints[i]); y += zz(ints[i + 1]); i += 2; out.append([(x, y)])
        elif cmd == 2:
            for _ in range(cnt): x += zz(ints[i]); y += zz(ints[i + 1]); i += 2; out[-1].append((x, y))
    return out


pbf, geo, tx, ty = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
data = gzip.decompress(open(pbf, "rb").read())
for name, extent, feats in layers(data):
    rs = [r for ft in feats for r in rings(ft)]
    pts = [p for r in rs for p in r]
    print(f"layer {name}: extent {extent}, features {len(feats)}, rings {len(rs)}, "
          f"x {min(p[0] for p in pts)}..{max(p[0] for p in pts)}, y {min(p[1] for p in pts)}..{max(p[1] for p in pts)}")
    if name == "squadratinhos":
        unit = extent // 32
        offgrid = sum(1 for p in pts if p[0] % unit or p[1] % unit)
        print("  vertices not on z17 grid:", offgrid)
        # Snap vertices to z17 tile corners (the encoder leaves some 1 unit off), then even-odd fill.
        snapped = [[(round(x / unit), round(y / unit)) for x, y in r] for r in rs]
        rows = {}
        for r in snapped:
            for (x1, y1), (x2, y2) in zip(r, r[1:] + r[:1]):
                if x1 == x2 and y1 != y2:
                    for row in range(max(min(y1, y2), 0), min(max(y1, y2), 32)):
                        rows.setdefault(row, []).append(x1)
        got = set()
        for row, xs in rows.items():
            xs.sort()
            for a, b in zip(xs[0::2], xs[1::2]):
                got.update((tx * 32 + col, ty * 32 + row) for col in range(max(a, 0), min(b, 32)))
        tiles, _ = load_tiles_geojson(json.load(open(geo)))
        exp = {t for t in tiles if t[0] >> 5 == tx and t[1] >> 5 == ty}
        print(f"  pbf: {len(got)} tiles, geojson: {len(exp)} tiles, identical: {got == exp}")
