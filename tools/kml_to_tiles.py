"""Convert a tile-service export (KML or live GeoJSON) into a set of visited OSM tiles (x, y)."""
import json
import math
import xml.etree.ElementTree as ET

KML = "{http://www.opengis.net/kml/2.2}"


def lonlat_to_tile(lon, lat, z):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    y = (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n
    return round(x), round(y)  # KML vertices sit on tile corners


def rasterize(rings, zoom):
    """Fill lon/lat rings (outer boundaries and holes alike) with the even-odd rule."""
    # Scanline: for every tile row, collect x positions of vertical edges crossing the row center.
    rows = {}
    for ring in rings:
        pts = [lonlat_to_tile(lon, lat, zoom) for lon, lat in ring]
        for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
            if x1 != x2 or y1 == y2:
                continue  # only vertical edges matter for row crossings
            for y in range(min(y1, y2), max(y1, y2)):
                rows.setdefault(y, []).append(x1)
    tiles = set()
    for y, xs in rows.items():
        xs.sort()
        for a, b in zip(xs[0::2], xs[1::2]):
            tiles.update((x, y) for x in range(a, b))
    return tiles


def load_tiles_geojson(data, layer="squadratinhos", zoom=17):
    feature = next(f for f in data["features"] if f["properties"].get("name") == layer)
    geom = feature["geometry"]
    polygons = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    rings = [[tuple(pt[:2]) for pt in ring] for poly in polygons for ring in poly]
    return rasterize(rings, zoom), feature["properties"]["size"]


def load_tiles(path, layer="squadratinhos", zoom=17):
    root = ET.parse(path).getroot()
    for pm in root.iter(KML + "Placemark"):
        if pm.find(KML + "name").text == layer:
            break
    else:
        raise ValueError(f"layer {layer!r} not found")
    rings = [[tuple(map(float, p.split(",")[:2])) for p in c.text.split()] for c in pm.iter(KML + "coordinates")]
    tiles = rasterize(rings, zoom)
    expected = int(next(d.find(KML + "value").text for d in pm.iter(KML + "Data") if d.get("name") == "size"))
    return tiles, expected


if __name__ == "__main__":
    import sys
    path = sys.argv[1]
    if path.endswith(".kml"):
        tiles, expected = load_tiles(path)
    else:
        with open(path) as f:
            tiles, expected = load_tiles_geojson(json.load(f))
    print(f"tiles: {len(tiles)}  expected (KML size): {expected}  match: {len(tiles) == expected}")
