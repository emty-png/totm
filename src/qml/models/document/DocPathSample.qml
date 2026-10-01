import QtQuick
import Totm

// Motion-path measuring for animation sampling: bezier flattening plus
// arc-length sampling. Delegates to AnimBridge (the Anims:: core shared
// with video export), so preview and export follow identical paths by
// construction instead of a ported twin. Pts are relative offsets from
// the path start (first point 0,0), so motion stays valid when nodes
// move after applying. Distances are canvas px, angles degrees.
QtObject {
    id: path

    // Motion-path sample by arc length. Returns offset from start plus
    // tangent delta from the start tangent (no snap when orienting),
    // or null when fewer than 2 points ride along.
    function samplePath(pts, closed, e) {
        var s = AnimBridge.samplePath(pts || [], closed === true, Number(e) || 0);
        if (s === undefined || s === null)
            return null;
        return {
            dx: s.dx,
            dy: s.dy,
            angleDelta: s.angleDelta
        };
    }

    // Production sample: options carry speed/loop/reverse/orient-offset/
    // flip/follow, e is eased progress, p is linear progress, base is the
    // leaf base row for follow-pivot compensation. Old clips without the
    // new keys sample exactly like samplePath above (strict compat).
    function samplePathEx(pts, options, base, e, p) {
        var s = AnimBridge.samplePathEx(pts || [], options || {}, base || {}, Number(e) || 0, Number(p) || 0);
        if (s === undefined || s === null)
            return null;
        return {
            dx: s.dx,
            dy: s.dy,
            angleDelta: s.angleDelta
        };
    }
}
