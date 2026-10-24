import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Time;

// Storage keys shared by the foreground apps and the background sync service.
const KEY_POS = "pos";         // [lat, lon] last known position, written by the foreground app
const KEY_WINDOW = "window";   // last /tiles response from the sync server
const KEY_STATUS = "status";   // last sync outcome: {"ok"=>Boolean, "code"=>Number, "at"=>Number}
const KEY_FORCE = "force";     // set when settings change, so the next sync ignores freshness

const SYNC_INTERVAL = 5 * 60;  // Connect IQ minimum between temporal events

module Sync {
    // Collected-tile bits of a stored window (bit set = collected), row-major from (x0, y0).
    function bits(window as Dictionary) as ByteArray {
        return StringUtil.convertEncodedString(window["bits"] as String, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
    }

    // Sync as soon as Connect IQ allows: now, or SYNC_INTERVAL after the previous background run.
    function schedule() as Void {
        var last = Background.getLastTemporalEventTime();
        var interval = new Time.Duration(SYNC_INTERVAL);
        if (last == null || Time.now().compare(last.add(interval)) >= 0) {
            Background.registerForTemporalEvent(Time.now());
        } else {
            Background.registerForTemporalEvent(last.add(interval));
        }
    }

    // Stores a background result. Returns true when a new tile window arrived.
    function onResult(data as Application.PersistableType) as Boolean {
        var now = Time.now().value();
        var updated = false;
        if (data instanceof Dictionary && data["bits"] != null) {
            Storage.setValue(KEY_WINDOW, data);
            Storage.setValue(KEY_STATUS, {"ok" => true, "code" => 200, "at" => now});
            Storage.deleteValue(KEY_FORCE);
            updated = true;
        } else if (data instanceof Dictionary && data["code"] != null) {
            Storage.setValue(KEY_STATUS, {"ok" => false, "code" => data["code"], "at" => now});
        }
        // Replaces the one-shot event from schedule() with the regular interval.
        Background.registerForTemporalEvent(new Time.Duration(SYNC_INTERVAL));
        return updated;
    }
}
