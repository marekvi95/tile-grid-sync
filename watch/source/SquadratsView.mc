import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Time;
import Toybox.WatchUi;

const COLOR_COLLECTED = 0x006E6E;
const COLOR_NEW = 0x00FF55;
const COLOR_UNKNOWN = 0x222222;  // outside the synced window
const COLOR_GRID = 0x3A3A3A;
const COLOR_TRACK = 0xFFAA00;

const TRACK_POINTS = 60;
const SEARCH_RADIUS = 25;        // tiles searched for the nearest uncollected squadratinho
const POS_SAVE_INTERVAL = 60;    // seconds between position writes for the background service

class SquadratsView extends WatchUi.DataField {
    // Synced window of collected tiles (bit set = collected), row-major, MSB first.
    private var mBits as ByteArray?;
    private var mX0 as Number = 0;
    private var mY0 as Number = 0;
    private var mW as Number = 0;
    private var mH as Number = 0;

    // Tiles entered during this activity that were not collected yet, keyed by tileKey().
    private var mNew as Dictionary<Long, Boolean> = {};
    private var mNewCount as Number = 0;

    private var mPos as Array<Double>?;      // fractional tile [x, y]
    private var mLat as Double = 0.0d;
    private var mHeading as Float?;
    private var mTile as Array<Number>?;
    private var mTrack as Array<Array<Double>> = [];
    private var mNearest as Array<Number>?;  // nearest uncollected tile, found when entering a tile
    private var mPosSavedAt as Number = 0;

    private var mCell as Number = 0;
    private var mVibrate as Boolean = true;

    function initialize() {
        DataField.initialize();
        loadSettings();
        loadWindow();
    }

    function loadSettings() as Void {
        mCell = Properties.getValue("cellSize") as Number;
        mVibrate = Properties.getValue("vibrate") as Boolean;
    }

    function loadWindow() as Void {
        var window = Storage.getValue(KEY_WINDOW) as Dictionary?;
        if (window == null) {
            return;
        }
        mBits = Sync.bits(window);
        mX0 = window["x0"] as Number;
        mY0 = window["y0"] as Number;
        mW = window["w"] as Number;
        mH = window["h"] as Number;
        mNearest = findNearest();
    }

    // 1 = collected (before or during this activity), 0 = uncollected, -1 = unknown (outside window).
    private function state(x as Number, y as Number) as Number {
        if (mNew.hasKey(tileKey(x, y))) {
            return 1;
        }
        var bits = mBits;
        if (bits == null || x < mX0 || y < mY0 || x >= mX0 + mW || y >= mY0 + mH) {
            return -1;
        }
        var i = (y - mY0) * mW + (x - mX0);
        return (bits[i >> 3] & (0x80 >> (i & 7))) != 0 ? 1 : 0;
    }

    private function tileKey(x as Number, y as Number) as Long {
        return x.toLong() * 131072l + y;
    }

    function compute(info as Activity.Info) as Void {
        var loc = info.currentLocation;
        if (loc == null) {
            // Before the activity has a fix (and in the simulator's Set Position) only Position has it.
            var p = Position.getInfo();
            if (p.accuracy == Position.QUALITY_NOT_AVAILABLE) {
                return;
            }
            loc = p.position;
            if (loc == null) {
                return;
            }
        }
        var deg = loc.toDegrees();
        mLat = deg[0].toDouble();
        mPos = Tiles.toTileF(mLat, deg[1].toDouble());
        mHeading = info.currentHeading;

        var now = Time.now().value();
        if (now - mPosSavedAt >= POS_SAVE_INTERVAL || mBits == null && mPosSavedAt == 0) {
            Storage.setValue(KEY_POS, [mLat, deg[1].toDouble()]);
            mPosSavedAt = now;
        }

        var pos = mPos as Array<Double>;
        mTrack.add([pos[0], pos[1]]);
        if (mTrack.size() > TRACK_POINTS) {
            mTrack = mTrack.slice(1, null);
        }

        var tile = [Math.floor(pos[0]).toNumber(), Math.floor(pos[1]).toNumber()];
        if (mTile == null || tile[0] != mTile[0] || tile[1] != mTile[1]) {
            mTile = tile;
            if (state(tile[0], tile[1]) == 0) {
                mNew.put(tileKey(tile[0], tile[1]), true);
                mNewCount++;
                if (mVibrate && Attention has :vibrate) {
                    Attention.vibrate([new Attention.VibeProfile(75, 300)]);
                }
            }
            mNearest = findNearest();
        }
    }

    // Closest uncollected tile to the position, searching ring by ring.
    private function findNearest() as Array<Number>? {
        var pos = mPos;
        var tile = mTile;
        if (pos == null || tile == null || mBits == null) {
            return null;
        }
        var best = null as Double?;
        var bestTile = null as Array<Number>?;
        for (var r = 0; r <= SEARCH_RADIUS; r++) {
            if (best != null && r - 1 >= best) {
                break;  // tiles in ring r are at least r-1 tiles away
            }
            for (var dy = -r; dy <= r; dy++) {
                var step = (dy == -r || dy == r) ? 1 : 2 * r;
                for (var dx = -r; dx <= r; dx += step) {
                    var x = tile[0] + dx;
                    var y = tile[1] + dy;
                    if (state(x, y) != 0) {
                        continue;
                    }
                    var d = gapTo(pos, x, y);
                    if (best == null || d < best) {
                        best = d;
                        bestTile = [x, y];
                    }
                }
            }
        }
        return bestTile;
    }

    // Distance in tiles from a fractional position to the nearest edge of tile (x, y).
    private function gapTo(pos as Array<Double>, x as Number, y as Number) as Double {
        var dx = clampGap(pos[0], x);
        var dy = clampGap(pos[1], y);
        return Math.sqrt(dx * dx + dy * dy);
    }

    // Gap along one axis from coordinate p to the tile spanning [t, t+1).
    private function clampGap(p as Double, t as Number) as Double {
        if (p < t) {
            return t - p;
        }
        if (p > t + 1) {
            return p - (t + 1);
        }
        return 0.0d;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var pos = mPos;
        if (pos == null || mBits == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, pos == null ? "Waiting for GPS" : statusText(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        if (h < 150) {
            drawCompact(dc, w, h);
            return;
        }
        drawMap(dc, w, h, pos);
        drawLabels(dc, w, h);
    }

    private function drawMap(dc as Graphics.Dc, w as Number, h as Number, pos as Array<Double>) as Void {
        var cell = mCell;
        if (cell == 0) {
            // Auto: 3 squadratinhos across the shorter side, so a 3x3 block fills the field.
            cell = (w < h ? w : h) / 3;
        }
        var cx = w / 2.0d;
        var cy = h / 2.0d;
        var minX = Math.floor(pos[0] - cx / cell).toNumber();
        var maxX = Math.floor(pos[0] + cx / cell).toNumber();
        var minY = Math.floor(pos[1] - cy / cell).toNumber();
        var maxY = Math.floor(pos[1] + cy / cell).toNumber();

        for (var y = minY; y <= maxY; y++) {
            var sy = (cy + (y - pos[1]) * cell).toNumber();
            for (var x = minX; x <= maxX; x++) {
                var s = state(x, y);
                if (s == 0) {
                    continue;
                }
                var color = COLOR_UNKNOWN;
                if (mNew.hasKey(tileKey(x, y))) {
                    color = COLOR_NEW;
                } else if (s == 1) {
                    color = COLOR_COLLECTED;
                }
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle((cx + (x - pos[0]) * cell).toNumber(), sy, cell, cell);
            }
        }

        dc.setColor(COLOR_GRID, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        for (var x = minX; x <= maxX + 1; x++) {
            var sx = (cx + (x - pos[0]) * cell).toNumber();
            dc.drawLine(sx, 0, sx, h);
        }
        for (var y = minY; y <= maxY + 1; y++) {
            var sy = (cy + (y - pos[1]) * cell).toNumber();
            dc.drawLine(0, sy, w, sy);
        }

        dc.setColor(COLOR_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        for (var i = 1; i < mTrack.size(); i++) {
            var a = mTrack[i - 1];
            var b = mTrack[i];
            dc.drawLine((cx + (a[0] - pos[0]) * cell).toNumber(), (cy + (a[1] - pos[1]) * cell).toNumber(),
                (cx + (b[0] - pos[0]) * cell).toNumber(), (cy + (b[1] - pos[1]) * cell).toNumber());
        }

        drawMarker(dc, cx.toNumber(), cy.toNumber());
    }

    // White arrow pointing along the heading (or a dot when not moving).
    private function drawMarker(dc as Graphics.Dc, x as Number, y as Number) as Void {
        var heading = mHeading;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (heading == null) {
            dc.fillCircle(x, y, 7);
            return;
        }
        var s = Math.sin(heading);
        var c = Math.cos(heading);
        var pts = [[0, -14], [9, 10], [0, 5], [-9, 10]];
        var poly = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i < pts.size(); i++) {
            var px = pts[i][0];
            var py = pts[i][1];
            poly.add([x + (px * c - py * s).toNumber(), y + (px * s + py * c).toNumber()]);
        }
        dc.fillPolygon(poly);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var i = 0; i < poly.size(); i++) {
            var a = poly[i];
            var b = poly[(i + 1) % poly.size()];
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
    }

    private function drawLabels(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var font = Graphics.FONT_SMALL;
        var fh = dc.getFontHeight(font);
        var top = (h * 0.06).toNumber();
        var bottom = h - fh - (h * 0.06).toNumber();
        drawBoxedText(dc, w, top, font, "+" + mNewCount + " new", COLOR_NEW);
        drawBoxedText(dc, w, bottom, font, nearestText(), Graphics.COLOR_WHITE);
    }

    private function drawBoxedText(dc as Graphics.Dc, w as Number, y as Number, font as Graphics.FontType,
            text as String, color as Number) as Void {
        var pad = 8;
        var tw = dc.getTextWidthInPixels(text, font);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(w / 2 - tw / 2 - pad, y, tw + 2 * pad, dc.getFontHeight(font));
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawCompact(dc as Graphics.Dc, w as Number, h as Number) as Void {
        dc.setColor(COLOR_NEW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2, Graphics.FONT_MEDIUM, "+" + mNewCount + "  " + nearestText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function nearestText() as String {
        var nearest = mNearest;
        var pos = mPos;
        if (nearest == null || pos == null) {
            return "none near";
        }
        var d = gapTo(pos, nearest[0], nearest[1]) * Tiles.tileMeters(mLat);
        if (d < 1.0d) {
            return "new here";
        }
        return d < 1000 ? "next " + d.format("%d") + " m" : "next " + (d / 1000).format("%.1f") + " km";
    }

    private function statusText() as String {
        var status = Storage.getValue(KEY_STATUS) as Dictionary?;
        if (status == null) {
            return "Syncing tiles...";
        }
        return "Sync error " + status["code"];
    }
}
