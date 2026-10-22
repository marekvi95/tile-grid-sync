import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Storage keys shared by the foreground data field and the background sync service.
const KEY_POS = "pos";         // [lat, lon] last known position, written by the data field
const KEY_WINDOW = "window";   // last /tiles response from the sync server
const KEY_STATUS = "status";   // last sync outcome: {"ok"=>Boolean, "code"=>Number, "at"=>Number}
const KEY_FORCE = "force";     // set when settings change, so the next sync ignores freshness

const SYNC_INTERVAL = 5 * 60;  // Connect IQ minimum between temporal events

(:background)
class SquadratsSyncApp extends Application.AppBase {
    private var mView as SquadratsView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        mView = new SquadratsView();
        scheduleSync();
        return [mView];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new SyncDelegate()];
    }

    function onStop(state as Dictionary?) as Void {
        // onStop also runs when the background process exits; only the data field owns the schedule.
        if (mView != null) {
            Background.deleteTemporalEvent();
        }
    }

    function onBackgroundData(data as Application.PersistableType) as Void {
        var now = Time.now().value();
        if (data instanceof Dictionary && data["bits"] != null) {
            Storage.setValue(KEY_WINDOW, data);
            Storage.setValue(KEY_STATUS, {"ok" => true, "code" => 200, "at" => now});
            Storage.deleteValue(KEY_FORCE);
            if (mView != null) {
                mView.loadWindow();
            }
        } else if (data instanceof Dictionary && data["code"] != null) {
            Storage.setValue(KEY_STATUS, {"ok" => false, "code" => data["code"], "at" => now});
        }
        // A one-shot first event (see scheduleSync) is replaced by the regular interval.
        Background.registerForTemporalEvent(new Time.Duration(SYNC_INTERVAL));
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() as Void {
        Storage.setValue(KEY_FORCE, true);
        if (mView != null) {
            mView.loadSettings();
        }
        scheduleSync();
        WatchUi.requestUpdate();
    }

    // Sync as soon as Connect IQ allows: now, or 5 minutes after the previous background run.
    private function scheduleSync() as Void {
        var last = Background.getLastTemporalEventTime();
        var interval = new Time.Duration(SYNC_INTERVAL);
        if (last == null || Time.now().compare(last.add(interval)) >= 0) {
            Background.registerForTemporalEvent(Time.now());
        } else {
            Background.registerForTemporalEvent(last.add(interval));
        }
    }
}
