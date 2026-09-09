import QtQuick

// Shared bezier math for the pen/path tools and paint: segment SVG and
// point evaluation. Single source so curve behavior can never drift
// between tools. Pure over explicit args.
QtObject {
    id: bezier

    // One segment as SVG: line for corner sides, cubic otherwise.
    function segSvg(a, b) {
        var ax = Number(a.x) || 0, ay = Number(a.y) || 0;
        var bx = Number(b.x) || 0, by = Number(b.y) || 0;
        var aSmooth = a.smooth === true, bSmooth = b.smooth === true;
        if (!aSmooth && !bSmooth)
            return " L " + bx + "," + by;
        var c1x = aSmooth ? (a.outX !== undefined ? Number(a.outX) : ax) : ax;
        var c1y = aSmooth ? (a.outY !== undefined ? Number(a.outY) : ay) : ay;
        var c2x = bSmooth ? (b.inX !== undefined ? Number(b.inX) : bx) : bx;
        var c2y = bSmooth ? (b.inY !== undefined ? Number(b.inY) : by) : by;
        return " C " + c1x + "," + c1y + " " + c2x + "," + c2y + " " + bx + "," + by;
    }

    // Point on the segment at t (mirrored smooth handles included).
    function bezierPoint(a, b, t) {
        var ax = Number(a.x) || 0, ay = Number(a.y) || 0;
        var bx = Number(b.x) || 0, by = Number(b.y) || 0;
        var aS = a.smooth === true, bS = b.smooth === true;
        var c1x = aS ? (a.outX !== undefined ? Number(a.outX) : ax) : ax;
        var c1y = aS ? (a.outY !== undefined ? Number(a.outY) : ay) : ay;
        var c2x = bS ? (b.inX !== undefined ? Number(b.inX) : bx) : bx;
        var c2y = bS ? (b.inY !== undefined ? Number(b.inY) : by) : by;
        var u = 1 - t;
        return {
            x: u * u * u * ax + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * bx,
            y: u * u * u * ay + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * by
        };
    }
}
