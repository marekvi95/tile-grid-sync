import Toybox.Lang;
import Toybox.WatchUi;

class MapTilesDelegate extends WatchUi.BehaviorDelegate {
    private var mMap as WatchUi.MapView;

    function initialize(map as WatchUi.MapView) {
        BehaviorDelegate.initialize();
        mMap = map;
    }

    // Enter starts browsing, so the map can be panned and zoomed.
    function onSelect() as Boolean {
        mMap.setMapMode(WatchUi.MAP_MODE_BROWSE);
        return true;
    }

    // Back leaves browsing first; a second press exits the app.
    function onBack() as Boolean {
        if (mMap.getMapMode() == WatchUi.MAP_MODE_BROWSE) {
            mMap.setMapMode(WatchUi.MAP_MODE_PREVIEW);
            return true;
        }
        return false;
    }
}
