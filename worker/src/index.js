// Serves a compact bitmap of collected tiles around a position, for the Garmin data field.
//
// GET /tiles?key=WATCH_KEY&lat=49.19&lon=16.60
// -> {"ts":..., "z":17, "x0":..., "y0":..., "w":128, "h":128, "n":..., "bits":"<base64>"}
// bits: row-major over the window, MSB first; bit set = collected.
//
// Data comes live from the upstream vector tile service: one z12 tile holds 32x32 tiles,
// so the 128x128 window is aligned to the z12 grid and built from 4x4 small tiles.

const ZOOM = 17;
const FETCH_ZOOM = 12;
const BLOCK = 2 ** (ZOOM - FETCH_ZOOM); // tiles per z12 tile side
const BLOCKS = 4;
const WINDOW = BLOCK * BLOCKS;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/tiles") return json({ error: "not found" }, 404);
    if (!env.WATCH_KEY || url.searchParams.get("key") !== env.WATCH_KEY) return json({ error: "unauthorized" }, 401);

    const lat = parseFloat(url.searchParams.get("lat"));
    const lon = parseFloat(url.searchParams.get("lon"));
    if (!(Math.abs(lat) < 85) || !(Math.abs(lon) <= 180)) return json({ error: "bad lat/lon" }, 400);

    try {
      const meta = await fetchJson(`https://mainframe-api.squadrats.com/anonymous/squadrants/${env.SQUADRATS_TOKEN}/geojson`);
      const [cx, cy] = lonLatToTile(lon, lat, ZOOM).map(Math.floor);
      // Nearest z12-aligned window, so the position is at most 16 tiles off center.
      const bx0 = Math.round((cx - WINDOW / 2) / BLOCK);
      const by0 = Math.round((cy - WINDOW / 2) / BLOCK);
      const bits = new Uint8Array((WINDOW * WINDOW) / 8);

      const jobs = [];
      for (let j = 0; j < BLOCKS; j++) {
        for (let i = 0; i < BLOCKS; i++) {
          const tileUrl = `https://tiles1.squadrats.com/${env.SQUADRATS_TOKEN}/trophies/${meta.timestamp}/${FETCH_ZOOM}/${bx0 + i}/${by0 + j}.pbf`;
          jobs.push(fetchTile(tileUrl).then((tile) => tile && fillBlock(tile, bits, i * BLOCK, j * BLOCK)));
        }
      }
      await Promise.all(jobs);

      let n = 0;
      for (const b of bits) for (let v = b; v; v &= v - 1) n++;
      return json({ ts: meta.timestamp, z: ZOOM, x0: bx0 * BLOCK, y0: by0 * BLOCK, w: WINDOW, h: WINDOW, n, bits: base64(bits) });
    } catch (e) {
      return json({ error: String(e.message).replaceAll(env.SQUADRATS_TOKEN, "…") }, 502);
    }
  },
};

// Even-odd fills the tile polygons of one vector tile into the window bitmap at (ox, oy).
function fillBlock(tile, bits, ox, oy) {
  // Upstream layer name; the data field does not depend on it.
  const layer = readLayers(tile).find((l) => l.name === "squadratinhos");
  if (!layer) return;
  const unit = layer.extent / BLOCK;
  const rows = Array.from({ length: BLOCK }, () => []);
  for (const feature of layer.features) {
    for (const ring of decodeRings(feature)) {
      // Snap to tile corners: the encoder leaves some vertices 1 unit off the grid.
      const pts = ring.map(([x, y]) => [Math.round(x / unit), Math.round(y / unit)]);
      for (let k = 0; k < pts.length; k++) {
        const [x1, y1] = pts[k];
        const [x2, y2] = pts[(k + 1) % pts.length];
        if (x1 !== x2 || y1 === y2) continue;
        for (let r = Math.max(Math.min(y1, y2), 0), end = Math.min(Math.max(y1, y2), BLOCK); r < end; r++) rows[r].push(x1);
      }
    }
  }
  rows.forEach((xs, r) => {
    xs.sort((a, b) => a - b);
    for (let k = 0; k + 1 < xs.length; k += 2) {
      for (let c = Math.max(xs[k], 0), end = Math.min(xs[k + 1], BLOCK); c < end; c++) {
        const i = (oy + r) * WINDOW + ox + c;
        bits[i >> 3] |= 0x80 >> (i & 7);
      }
    }
  });
}

// Minimal Mapbox Vector Tile reader: layer name, extent and raw feature geometries.
function readLayers(buf) {
  const layers = [];
  for (const [field, value] of protoFields(buf)) {
    if (field !== 3) continue;
    const layer = { name: "", extent: 4096, features: [] };
    for (const [f, v] of protoFields(value)) {
      if (f === 1) layer.name = new TextDecoder().decode(v);
      else if (f === 5) layer.extent = v;
      else if (f === 2) for (const [ff, vv] of protoFields(v)) if (ff === 4) layer.features.push(vv);
    }
    layers.push(layer);
  }
  return layers;
}

function decodeRings(geometry) {
  const ints = [];
  for (let p = 0; p < geometry.length; ) {
    const [v, next] = varint(geometry, p);
    ints.push(v);
    p = next;
  }
  const zigzag = (n) => (n >>> 1) ^ -(n & 1);
  const rings = [];
  let x = 0;
  let y = 0;
  for (let i = 0; i < ints.length; ) {
    const cmd = ints[i] & 7;
    const count = ints[i++] >>> 3;
    if (cmd === 7) continue; // ClosePath
    for (let c = 0; c < count; c++) {
      x += zigzag(ints[i++]);
      y += zigzag(ints[i++]);
      if (cmd === 1) rings.push([[x, y]]);
      else rings[rings.length - 1].push([x, y]);
    }
  }
  return rings;
}

function* protoFields(buf) {
  for (let p = 0; p < buf.length; ) {
    const [key, afterKey] = varint(buf, p);
    p = afterKey;
    const type = key & 7;
    if (type === 0) {
      const [v, next] = varint(buf, p);
      p = next;
      yield [key >>> 3, v];
    } else if (type === 2) {
      const [len, next] = varint(buf, p);
      p = next + len;
      yield [key >>> 3, buf.subarray(next, p)];
    } else {
      p += type === 5 ? 4 : 8;
    }
  }
}

function varint(buf, p) {
  let v = 0;
  let shift = 0;
  let b;
  do {
    b = buf[p++];
    v += (b & 0x7f) * 2 ** shift;
    shift += 7;
  } while (b & 0x80);
  return [v, p];
}

function lonLatToTile(lon, lat, z) {
  const n = 2 ** z;
  const x = ((lon + 180) / 360) * n;
  const y = ((1 - Math.asinh(Math.tan((lat * Math.PI) / 180)) / Math.PI) / 2) * n;
  return [x, y];
}

async function fetchTile(url) {
  const res = await fetch(url);
  if (res.status === 204 || res.status === 404) return null; // nothing collected there
  if (!res.ok) throw new Error(`tile HTTP ${res.status}: ${url}`);
  let bytes = new Uint8Array(await res.arrayBuffer());
  if (bytes[0] === 0x1f && bytes[1] === 0x8b) {
    // Served gzipped as octet-stream; not always decoded transparently.
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
    bytes = new Uint8Array(await new Response(stream).arrayBuffer());
  }
  return bytes;
}

async function fetchJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${url}`);
  return res.json();
}

function base64(bytes) {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}
