# Tile Grid Sync for Garmin

A Garmin Connect IQ data field for the Forerunner 970 that shows the map tiles you have already collected
on a tile-tracking service, around your current position.

This is an unofficial project. It is not affiliated with or endorsed by any tile service. See [DISCLAIMER.md](DISCLAIMER.md).

## How it works

```
tile service ──► Cloudflare Worker (worker/) ──► Garmin data field (watch/)
   vector tiles      /tiles?key=…&lat=…&lon=…       shared/ sync + tile math
```

- **Worker** (`worker/src/index.js`): given a position, fetches your collected tiles from the
  tile service's vector tiles and returns a compact bitmap of about 128×128 tiles (z17) around you.
  It is protected by a shared key, so only your watch can read it.
- **Watch** (`watch/`): a data field. A background service syncs the bitmap every 5 minutes. The field draws
  a grid of tiles around you: collected ones are filled, and the nearest uncollected one is labelled
  with its distance. It vibrates briefly when you enter a new tile (configurable).
- **Shared** (`shared/`): Monkey C code used by the data field: background sync, the sync delegate and the tile math.
- **Tools** (`tools/`): optional Python scripts that check the worker against a local KML/GeoJSON export of your tiles.

## Requirements

- Garmin Connect IQ SDK 9.x (tested with 9.2.0) and Java 21 for `monkeyc`
- A Forerunner 970 (the manifest targets `fr970` only)
- A Cloudflare account and [Wrangler](https://developers.cloudflare.com/workers/wrangler/) (`npm i -g wrangler`), for the worker
- Your account token for the tile service

## Setup

### 1. Deploy the worker

```sh
cd worker
npx wrangler secret put SQUADRATS_TOKEN   # your account token for the tile service
npx wrangler secret put WATCH_KEY         # any long random string; you will reuse it on the watch
npx wrangler deploy
```

Note the URL Wrangler prints, for example `https://squadrats-sync.<your-subdomain>.workers.dev`.

### 2. Configure the watch build

Copy the template and fill in your values:

```sh
cp shared/resources/settings/properties.xml.example shared/resources/settings/properties.xml
```

Set `workerUrl` to the worker URL and `watchKey` to the same `WATCH_KEY` you set in step 1.
`properties.xml` is gitignored because it holds your key.

### 3. Create a developer key

Connect IQ needs a signing key in DER format. Keep it out of git (the `keys/` folder is ignored):

```sh
mkdir -p keys
openssl genrsa -out keys/developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in keys/developer_key.pem -out keys/developer_key.der -nocrypt
```

### 4. Build

```sh
cd watch
export PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/<your-sdk-folder>/bin"
"$SDK/monkeyc" -d fr970 -f monkey.jungle -y ../keys/developer_key.der -o bin/TileGridSync.prg
```

### 5. Run or install

- Simulator: start the Connect IQ simulator, then run `"$SDK/monkeydo" bin/TileGridSync.prg fr970`.
- Watch: connect the watch by USB and copy `bin/TileGridSync.prg` into `GARMIN/APPS/`.
  On macOS the watch may not mount as a drive. Android File Transfer works (it uses MTP).
  Then add the data field to an activity screen.

**The built `.prg` contains your watch key.** Do not share it.

## Settings

| Setting | Default | Meaning |
| --- | --- | --- |
| Sync server URL | from `properties.xml` | Your worker URL |
| Sync key | from `properties.xml` | Must match `WATCH_KEY` |
| Tile size on screen | 0 (auto) | Pixels per tile; auto fits about 3×3 tiles |
| Vibrate on new tile | on | Short vibration when you enter an uncollected tile |

## Limitations

- Only the Forerunner 970 is targeted.
- The sync runs no more often than every 5 minutes, which is the Connect IQ minimum for background events.
- The worker uses endpoints of the tile service that are not documented as a public API. They may change without notice.

## Contributing

Issues and pull requests are welcome. Please keep secrets (tokens, watch keys, signing keys, `properties.xml`)
out of commits.

## License

MIT License. See [LICENSE](LICENSE).
