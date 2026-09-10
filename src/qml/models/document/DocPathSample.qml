import QtQuick

// Motion-path measuring for animation sampling: bezier flattening plus
// arc-length sampling. Pure over explicit args. Distances are canvas px,
// angles degrees, matching the C++ video renderer (AnimSampler), which
// ports this file.
QtObject {
    id: path

    function cubicPoint(a, b, t) {
        var ax = Number(a.x) || 0, ay = Number(a.y) || 0;
        var bx = Number(b.x) || 0, by = Number(b.y) || 0;
        var aSmooth = a.smooth === true, bSmooth = b.smooth === true;
        if (!aSmooth && !bSmooth)
            return {
                x: ax + (bx - ax) * t,
                y: ay + (by - ay) * t,
                tx: bx - ax,
                ty: by - ay
            };
        var c1x = aSmooth ? (a.outX !== undefined ? Number(a.outX) : ax) : ax;
        var c1y = aSmooth ? (a.outY !== undefined ? Number(a.outY) : ay) : ay;
        var c2x = bSmooth ? (b.inX !== undefined ? Number(b.inX) : bx) : bx;
        var c2y = bSmooth ? (b.inY !== undefined ? Number(b.inY) : by) : by;
        var u = 1 - t;
        var x = u * u * u * ax + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * bx;
        var y = u * u * u * ay + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * by;
        var dx = 3 * u * u * (c1x - ax) + 6 * u * t * (c2x - c1x) + 3 * t * t * (bx - c2x);
        var dy = 3 * u * u * (c1y - ay) + 6 * u * t * (c2y - c1y) + 3 * t * t * (by - c2y);
        return {
            x: x,
            y: y,
            tx: dx,
            ty: dy
        };
    }

    // Motion-path sample by arc length. Pts are relative offsets from the
    // path start (first point 0,0), so motion stays valid when nodes move
    // after applying. Returns offset from start plus tangent delta from
    // the start tangent (no snap when orienting).
    function samplePath(pts, closed, e) {
        var list = pts || [];
        if (list.length < 2)
            return null;
        var segs = [];
        var count = closed ? list.length : list.length - 1;
        for (var i = 0; i < count; i++) {
            var a = list[i];
            var b = list[(i + 1) % list.length];
            segs.push({
                a: a,
                b: b
            });
        }
        var flat = [];
        var steps = 16;
        for (var s = 0; s < segs.length; s++) {
            for (var k = 0; k < steps; k++) {
                var p0 = path.cubicPoint(segs[s].a, segs[s].b, k / steps);
                var p1 = path.cubicPoint(segs[s].a, segs[s].b, (k + 1) / steps);
                flat.push({
                    x0: p0.x,
                    y0: p0.y,
                    x1: p1.x,
                    y1: p1.y,
                    tx: p1.tx,
                    ty: p1.ty,
                    len: Math.hypot(p1.x - p0.x, p1.y - p0.y)
                });
            }
        }
        var total = 0;
        for (var f = 0; f < flat.length; f++)
            total += flat[f].len;
        if (total <= 0)
            return {
                dx: list[0].x || 0,
                dy: list[0].y || 0,
                angleDelta: 0
            };
        var target = Math.min(total, Math.max(0, e)) * total;
        var acc = 0;
        var at = flat[flat.length - 1];
        var prev = 0;
        for (var g = 0; g < flat.length; g++) {
            prev = acc;
            acc += flat[g].len;
            if (acc >= target) {
                at = flat[g];
                break;
            }
        }
        var segLen = at.len > 0 ? at.len : 1;
        var f = Math.min(1, Math.max(0, (target - prev) / segLen));
        var px = at.x0 + (at.x1 - at.x0) * f;
        var py = at.y0 + (at.y1 - at.y0) * f;
        var start = flat[0];
        var a0 = Math.atan2(start.ty, start.tx) * 180 / Math.PI;
        var a1 = Math.atan2(at.ty, at.tx) * 180 / Math.PI;
        var delta = a1 - a0;
        while (delta > 180)
            delta -= 360;
        while (delta < -180)
            delta += 360;
        if (Math.hypot(at.tx, at.ty) < 1e-6 || Math.hypot(start.tx, start.ty) < 1e-6)
            delta = 0;
        return {
            dx: px,
            dy: py,
            angleDelta: delta
        };
    }
}
