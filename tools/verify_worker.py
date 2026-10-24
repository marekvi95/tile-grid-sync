"""Compare the Worker's /tiles bitmap with the GeoJSON tile set at several locations."""
import base64, json, os, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kml_to_tiles import load_tiles_geojson

base, key, geo = sys.argv[1], sys.argv[2], sys.argv[3]
tiles, _ = load_tiles_geojson(json.load(open(geo)))
places = {"Brno": (49.195, 16.608), "Vienna": (48.208, 16.372), "Bratislava": (48.145, 17.107),
          "Brno south edge": (49.10, 16.74), "Tokyo": (35.68, 139.77), "Atlantic (nothing)": (40.0, -30.0)}
for name, (lat, lon) in places.items():
    t = time.time()
    req = urllib.request.Request(f"{base}/tiles?key={key}&lat={lat}&lon={lon}", headers={"User-Agent": "tile-grid-sync-verify"})
    r = json.load(urllib.request.urlopen(req))
    ms = (time.time() - t) * 1000
    b = base64.b64decode(r["bits"])
    got = {(r["x0"] + j % r["w"], r["y0"] + j // r["w"]) for j in range(r["w"] * r["h"]) if b[j >> 3] & (0x80 >> (j & 7))}
    exp = {(x, y) for x, y in tiles if r["x0"] <= x < r["x0"] + r["w"] and r["y0"] <= y < r["y0"] + r["h"]}
    print(f"{name:20s} n={r['n']:5d} expected={len(exp):5d} identical={got == exp}  {ms:.0f} ms")
