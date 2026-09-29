import QtQuick
import Totm

// Easing table for animation sampling: named easings plus custom
// cubic-bezier. Delegates to AnimBridge (the Anims:: core shared with
// video export), so preview and export ease identically by
// construction instead of a ported twin.
QtObject {
    id: easing

    // Easing ids: linear | easeIn | easeOut | easeInOut | slowDown |
    // backOut | backInOut | bounceOut | elasticOut | custom
    // (cubic-bezier [x1, y1, x2, y2]). Segment id "hold" never reaches
    // here: keyed interpolation intercepts it first (constant).
    function easeValue(id, bezier, t) {
        return AnimBridge.easeValue(id, bezier || [], t);
    }
}
