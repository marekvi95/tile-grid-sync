import Toybox.Lang;
import Toybox.Math;

// Web Mercator tile maths at tile zoom (z17), shared by the data field and the background service.
(:background)
module Tiles {
    const ZOOM_SCALE = 131072.0d;  // 2^17
    const EARTH_CIRCUMFERENCE = 40075016.686d;

    // Fractional tile coordinates [x, y] of a position in degrees.
    function toTileF(lat as Double, lon as Double) as Array<Double> {
        var phi = lat * Math.PI / 180.0d;
        var x = (lon + 180.0d) / 360.0d * ZOOM_SCALE;
        var y = (1.0d - Math.ln(Math.tan(phi) + 1.0d / Math.cos(phi)) / Math.PI) / 2.0d * ZOOM_SCALE;
        return [x, y];
    }

    // Integer tile [x, y] containing a position.
    function toTile(lat as Double, lon as Double) as Array<Number> {
        var t = toTileF(lat, lon);
        return [Math.floor(t[0]).toNumber(), Math.floor(t[1]).toNumber()];
    }

    // [lat, lon] in degrees of a fractional tile position; inverse of toTileF.
    function tileToDeg(x as Double, y as Double) as Array<Double> {
        var lon = x / ZOOM_SCALE * 360.0d - 180.0d;
        var n = Math.PI - 2.0d * Math.PI * y / ZOOM_SCALE;
        var lat = Math.atan((Math.pow(2.718281828459045d, n) - Math.pow(2.718281828459045d, -n)) / 2.0d) * 180.0d / Math.PI;
        return [lat, lon];
    }

    // Width of one tile in metres at a latitude.
    function tileMeters(lat as Double) as Double {
        return EARTH_CIRCUMFERENCE * Math.cos(lat * Math.PI / 180.0d) / ZOOM_SCALE;
    }
}
