import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

const REFRESH_AFTER = 60 * 60;  // re-download even without moving, to pick up newly processed activities
const EDGE_MARGIN = 40;         // re-download when closer than this many tiles to the window edge

// Runs in the background process (64 KB): fetches the tile window around the last position.
(:background)
class SyncDelegate extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var pos = Storage.getValue(KEY_POS) as Array<Double>?;
        if (pos == null || !needsSync(pos)) {
            Background.exit(null);
            return;
        }
        var url = Properties.getValue("workerUrl") as String;
        var params = {
            "key" => Properties.getValue("watchKey") as String,
            "lat" => pos[0].format("%.5f"),
            "lon" => pos[1].format("%.5f")
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(url, params, options, method(:onResponse));
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary) {
            Background.exit(data as Application.PropertyValueType);
        } else {
            Background.exit({"code" => code});
        }
    }

    private function needsSync(pos as Array<Double>) as Boolean {
        var window = Storage.getValue(KEY_WINDOW) as Dictionary?;
        var status = Storage.getValue(KEY_STATUS) as Dictionary?;
        if (window == null || status == null || !(status["ok"] as Boolean) || Storage.getValue(KEY_FORCE) != null) {
            return true;
        }
        if (Time.now().value() - (status["at"] as Number) > REFRESH_AFTER) {
            return true;
        }
        var tile = Tiles.toTile(pos[0], pos[1]);
        var x0 = window["x0"] as Number;
        var y0 = window["y0"] as Number;
        var w = window["w"] as Number;
        var h = window["h"] as Number;
        return tile[0] < x0 + EDGE_MARGIN || tile[0] >= x0 + w - EDGE_MARGIN
            || tile[1] < y0 + EDGE_MARGIN || tile[1] >= y0 + h - EDGE_MARGIN;
    }
}
