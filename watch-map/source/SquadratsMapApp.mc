import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

const MARKER_RADIUS = 3;    // tiles scanned around the position, covers the visible area
const MAX_TILES = 100;      // cap on tile markers
const VIEW_RADIUS = 1.5d;   // half-size of the visible map area, in tiles
const WORLD_LAT = 85.0d;    // Web Mercator latitude limit, used before any position is known
const COLOR_TILE = 0x00FF55;
const COLOR_HERE = 0xFFE000;     // current tile, collected
const COLOR_MISSING = 0xFF0000;  // current tile, not collected

(:background)
class SquadratsMapApp extends Application.AppBase {
    private var mMap as WatchUi.MapView?;
    private var mTile as Graphics.BufferedBitmapReference?;
    private var mHere as Graphics.BufferedBitmapReference?;
    private var mMissing as Graphics.BufferedBitmapReference?;
    private var mCell as Number = 0;     // screen pixels per tile at the fixed zoom
    private var mPos as Array<Double>?;  // [lat, lon]
    private var mBits as ByteArray?;
    private var mX0 as Number = 0;
    private var mY0 as Number = 0;
    private var mW as Number = 0;
    private var mH as Number = 0;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var map = new WatchUi.MapView();
        var screen = System.getDeviceSettings();
        map.setScreenVisibleArea(0, 0, screen.screenWidth, screen.screenHeight);
        mMap = map;
        // On a round screen MapView fits the visible area into the inscribed square, measured in the simulator.
        var side = screen.screenShape == System.SCREEN_SHAPE_ROUND ? screen.screenWidth * 0.7071d : screen.screenWidth.toDouble();
        mCell = (side / (2 * VIEW_RADIUS)).toNumber();
        mTile = createTile(mCell, COLOR_TILE);
        mHere = createTile(mCell, COLOR_HERE);
        mMissing = createTile(mCell, COLOR_MISSING);
        mPos = Storage.getValue(KEY_POS) as Array<Double>?;
        loadWindow();
        Sync.schedule();
        var loc = Position.getInfo().position;
        if (loc != null) {
            setPosition(loc);
        } else {
            refresh();
        }
        Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
        return [map, new MapTilesDelegate(map)];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new SyncDelegate()];
    }

    function onBackgroundData(data as Application.PersistableType) as Void {
        if (Sync.onResult(data)) {
            loadWindow();
            refresh();
        }
    }

    function onSettingsChanged() as Void {
        Storage.setValue(KEY_FORCE, true);
        Sync.schedule();
    }

    function onPosition(info as Position.Info) as Void {
        var loc = info.position;
        if (loc != null) {
            setPosition(loc);
        }
    }

    private function setPosition(loc as Position.Location) as Void {
        var deg = loc.toDegrees();
        var pos = [deg[0].toDouble(), deg[1].toDouble()];
        mPos = pos;
        Storage.setValue(KEY_POS, pos);
        refresh();
    }

    private function loadWindow() as Void {
        var window = Storage.getValue(KEY_WINDOW) as Dictionary?;
        if (window == null) {
            return;
        }
        mBits = Sync.bits(window);
        mX0 = window["x0"] as Number;
        mY0 = window["y0"] as Number;
        mW = window["w"] as Number;
        mH = window["h"] as Number;
    }

    private function collected(x as Number, y as Number) as Boolean {
        var bits = mBits;
        if (bits == null || x < mX0 || y < mY0 || x >= mX0 + mW || y >= mY0 + mH) {
            return false;
        }
        var i = (y - mY0) * mW + (x - mX0);
        return (bits[i >> 3] & (0x80 >> (i & 7))) != 0;
    }

    // Visible area around the position, a square per collected tile nearby, then the current tile and the pin on top.
    private function refresh() as Void {
        var map = mMap;
        var square = mTile;
        var here = mHere;
        var missing = mMissing;
        if (map == null || square == null || here == null || missing == null) {
            return;
        }
        var pos = mPos;
        if (pos == null) {
            // MapView crashes without a visible area, so show the whole world until a position is known.
            map.setMapVisibleArea(toLocation([WORLD_LAT, -180.0d]), toLocation([-WORLD_LAT, 180.0d]));
            WatchUi.requestUpdate();
            return;
        }
        var t = Tiles.toTileF(pos[0], pos[1]);
        var tile = Tiles.toTile(pos[0], pos[1]);
        map.setMapVisibleArea(
            toLocation(Tiles.tileToDeg(t[0] - VIEW_RADIUS, t[1] - VIEW_RADIUS)),
            toLocation(Tiles.tileToDeg(t[0] + VIEW_RADIUS, t[1] + VIEW_RADIUS)));

        var offset = (mCell + 2) / 2;
        var markers = [] as Array<WatchUi.MapMarker>;
        for (var dy = -MARKER_RADIUS; dy <= MARKER_RADIUS; dy++) {
            for (var dx = -MARKER_RADIUS; dx <= MARKER_RADIUS && markers.size() < MAX_TILES; dx++) {
                var x = tile[0] + dx;
                var y = tile[1] + dy;
                if ((dx == 0 && dy == 0) || !collected(x, y)) {
                    continue;
                }
                var center = Tiles.tileToDeg(x.toDouble() + 0.5d, y.toDouble() + 0.5d);
                var marker = new WatchUi.MapMarker(toLocation(center));
                marker.setIcon(square, offset, offset);
                markers.add(marker);
            }
        }
        var centerHere = Tiles.tileToDeg(tile[0].toDouble() + 0.5d, tile[1].toDouble() + 0.5d);
        var current = new WatchUi.MapMarker(toLocation(centerHere));
        current.setIcon(collected(tile[0], tile[1]) ? here : missing, offset, offset);
        markers.add(current);
        markers.add(new WatchUi.MapMarker(toLocation(pos)));
        map.setMapMarker(markers);
        WatchUi.requestUpdate();
    }

    private function toLocation(deg as Array<Double>) as Position.Location {
        return new Position.Location({:latitude => deg[0], :longitude => deg[1], :format => :degrees});
    }

    // Outline centred on the tile boundary, so neighbouring borders line up on the grid.
    private function createTile(cell as Number, color as Number) as Graphics.BufferedBitmapReference {
        var size = cell + 2;
        var ref = Graphics.createBufferedBitmap({
            :width => size,
            :height => size,
            :alphaBlending => Graphics.ALPHA_BLENDING_FULL
        });
        var dc = (ref.get() as Graphics.BufferedBitmap).getDc();
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        dc.clear();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRectangle(1, 1, cell, cell);
        return ref;
    }
}
