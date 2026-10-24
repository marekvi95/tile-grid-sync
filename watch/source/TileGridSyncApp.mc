import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

(:background)
class TileGridSyncApp extends Application.AppBase {
    private var mView as TileGridView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        mView = new TileGridView();
        Sync.schedule();
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
        if (Sync.onResult(data) && mView != null) {
            mView.loadWindow();
        }
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() as Void {
        Storage.setValue(KEY_FORCE, true);
        if (mView != null) {
            mView.loadSettings();
        }
        Sync.schedule();
        WatchUi.requestUpdate();
    }
}
