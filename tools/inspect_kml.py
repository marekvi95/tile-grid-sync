import sys, re, math
import xml.etree.ElementTree as ET
ns = {"k": "http://www.opengis.net/kml/2.2"}
root = ET.parse(sys.argv[1]).getroot()
for pm in root.iter("{http://www.opengis.net/kml/2.2}Placemark"):
    name = pm.find("k:name", ns).text
    data = {d.get("name"): d.find("k:value", ns).text for d in pm.iter("{http://www.opengis.net/kml/2.2}Data")}
    polys = pm.findall(".//k:Polygon", ns)
    inner = pm.findall(".//k:innerBoundaryIs", ns)
    lons, lats = [], []
    for c in pm.iter("{http://www.opengis.net/kml/2.2}coordinates"):
        for p in c.text.split():
            x, y = p.split(",")[:2]; lons.append(float(x)); lats.append(float(y))
    print(name, data, "polygons:", len(polys), "holes:", len(inner),
          "bbox:", (min(lons), min(lats), max(lons), max(lats)) if lons else None)
