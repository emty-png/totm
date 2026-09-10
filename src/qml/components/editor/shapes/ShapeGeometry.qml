import QtQuick

// Vector path builders for shape paint. Pure over an explicit shape-like
// `s` (never stored): the same curves feed canvas paint and the C++
// video renderer. Caller passes its shape item straight through.
QtObject {
    id: geo

    function vectorPath(s) {
        var w = s.sw, h = s.sh;
        switch (s.shapeType) {
        case "ellipse":
            {
                var rx = w / 2, ry = h / 2;
                return "M " + w + "," + h / 2 + " A " + rx + "," + ry + " 0 1,0 0," + h / 2 + " A " + rx + "," + ry + " 0 1,0 " + w + "," + h / 2 + " Z";
            }
        case "rectangle":
            return s.independentCorners ? geo.rectPath(s) : "";
        case "triangle":
            return geo.roundedPoly(s, geo.cornerPoints(s), false);
        case "star":
            return geo.roundedPoly(s, geo.cornerPoints(s), true);
        case "pen":
            return geo.penPath(s);
        default:
            return "";
        }
    }

    // Corner points for the pointed shapes. Star alternates outer and
    // inner tips (first tip up); the inner notch is a fixed ratio.
    function cornerPoints(s) {
        var w = s.sw, h = s.sh;
        if (s.shapeType === "triangle")
            return [w / 2, 0, w, h, 0, h];
        var n = Math.max(3, Math.min(12, Math.round(s.points)));
        var cx = w / 2, cy = h / 2, inner = 0.4;
        var pts = [];
        for (var k = 0; k < n * 2; k++) {
            var a = -Math.PI / 2 + k * Math.PI / n;
            var rr = (k % 2 === 0) ? 1 : inner;
            pts.push(cx + w / 2 * rr * Math.cos(a), cy + h / 2 * rr * Math.sin(a));
        }
        return pts;
    }

    // Per-vertex radius in paint order. Uniform shapes return -1 so
    // the caller falls back to shape.radius; independent shapes read
    // cornerRadii (star maps outer tip k to vertex 2k, inner stays 0).
    function radiusAt(s, i, tipsOnly) {
        if (s.independentCorners !== true)
            return -1;
        var arr = s.cornerRadii || [];
        if (s.shapeType === "star") {
            if (i % 2 === 1)
                return 0;
            var tip = i / 2;
            return tip < arr.length ? Math.max(0, Number(arr[tip]) || 0) : 0;
        }
        return i < arr.length ? Math.max(0, Number(arr[i]) || 0) : 0;
    }

    // Rounded rectangle with a cut per corner (TL,TR,BR,BL clockwise).
    // Overclaimed edges share proportionally like the polygons below.
    function rectPath(s) {
        var w = s.sw, h = s.sh;
        var src = s.cornerRadii || [];
        var r = [];
        for (var i = 0; i < 4; i++)
            r.push(Math.max(0, i < src.length ? (Number(src[i]) || 0) : 0));
        var caps = [Math.min(w / 2, h / 2), Math.min(w / 2, h / 2), Math.min(w / 2, h / 2), Math.min(w / 2, h / 2)];
        for (var k = 0; k < 4; k++)
            r[k] = Math.min(r[k], caps[k]);
        var edges = [[0, 1, w], [1, 2, h], [2, 3, w], [3, 0, h]];
        for (var e = 0; e < 4; e++) {
            var a = edges[e][0], b = edges[e][1], len = edges[e][2];
            var sum = r[a] + r[b];
            if (len > 0 && sum > len) {
                r[a] *= len / sum;
                r[b] *= len / sum;
            }
        }
        var seg = (x1, y1, cx, cy, x2, y2, cut) => {
            if (cut <= 0)
                return " L " + x2 + "," + y2;
            return " L " + x1 + "," + y1 + " Q " + cx + "," + cy + " " + x2 + "," + y2;
        };
        var d = "M " + r[0] + ",0 L " + (w - r[1]) + ",0";
        d += seg(w - r[1], 0, w, 0, w, r[1], r[1]);
        d += seg(w, h - r[2], w, h, w - r[2], h, r[2]);
        d += seg(r[3], h, 0, h, 0, h - r[3], r[3]);
        d += seg(0, r[0], 0, 0, r[0], 0, r[0]);
        return d + " Z";
    }

    // Closed polygon path with per-vertex rounding. Each cut takes up to
    // the full neighbor edges; where two cuts would overlap an edge they
    // share it proportionally, so roundings meet into blobs instead of
    // folding over. tipsOnly rounds even vertices (star tips).
    function roundedPoly(s, pts, tipsOnly) {
        var n = pts.length / 2;
        var uniform = Math.max(0, s.radius);
        var cut = [];
        for (var i = 0; i < n; i++) {
            var want = geo.radiusAt(s, i, tipsOnly);
            var r = want >= 0 ? want : uniform;
            if (r <= 0 || (tipsOnly && i % 2 === 1 && s.independentCorners !== true)) {
                cut.push(0);
                continue;
            }
            var px = pts[((i - 1 + n) % n) * 2], py = pts[((i - 1 + n) % n) * 2 + 1];
            var vx = pts[i * 2], vy = pts[i * 2 + 1];
            var nx = pts[((i + 1) % n) * 2], ny = pts[((i + 1) % n) * 2 + 1];
            var l1 = Math.hypot(vx - px, vy - py);
            var l2 = Math.hypot(nx - vx, ny - vy);
            cut.push(l1 <= 0 || l2 <= 0 ? 0 : Math.min(r, l1, l2));
        }
        // Share overclaimed edges: neighbors meet instead of crossing.
        for (var e = 0; e < n; e++) {
            var f = e, g = (e + 1) % n;
            var len = Math.hypot(pts[g * 2] - pts[f * 2], pts[g * 2 + 1] - pts[f * 2 + 1]);
            var sum = cut[f] + cut[g];
            if (len > 0 && sum > len) {
                cut[f] *= len / sum;
                cut[g] *= len / sum;
            }
        }
        var d = "";
        for (var j = 0; j < n; j++) {
            var qx = pts[((j - 1 + n) % n) * 2], qy = pts[((j - 1 + n) % n) * 2 + 1];
            var wx = pts[j * 2], wy = pts[j * 2 + 1];
            var ex = pts[((j + 1) % n) * 2], ey = pts[((j + 1) % n) * 2 + 1];
            var m1 = Math.hypot(wx - qx, wy - qy);
            var m2 = Math.hypot(ex - wx, ey - wy);
            var ax = wx, ay = wy, bx = wx, by = wy;
            if (cut[j] > 0 && m1 > 0 && m2 > 0) {
                ax = wx - (wx - qx) / m1 * cut[j];
                ay = wy - (wy - qy) / m1 * cut[j];
                bx = wx + (ex - wx) / m2 * cut[j];
                by = wy + (ey - wy) / m2 * cut[j];
            }
            d += (j === 0 ? "M " : " L ") + ax + "," + ay;
            if (cut[j] > 0)
                d += " Q " + wx + "," + wy + " " + bx + "," + by;
        }
        return d + " Z";
    }

    // Pen subpath as local SVG. Anchors stay absolute in the model so
    // moves stay exact; paint subtracts the bbox origin. Smooth sides
    // emit cubics, corner sides collapse their control onto the anchor.
    function penPath(s) {
        var subs = s.pathData || [];
        var ox = s.sx, oy = s.sy;
        var d = "";
        for (var s2 = 0; s2 < subs.length; s2++) {
            var sub = subs[s2] || {};
            var pts = sub.pts || [];
            if (pts.length === 0)
                continue;
            var first = pts[0] || {};
            d += (d === "" ? "M " : " M ") + ((Number(first.x) || 0) - ox) + "," + ((Number(first.y) || 0) - oy);
            var seg = (a, b) => {
                var ax = (Number(a.x) || 0) - ox, ay = (Number(a.y) || 0) - oy;
                var bx = (Number(b.x) || 0) - ox, by = (Number(b.y) || 0) - oy;
                var aSmooth = a.smooth === true, bSmooth = b.smooth === true;
                if (!aSmooth && !bSmooth)
                    return " L " + bx + "," + by;
                var c1x = aSmooth ? (a.outX !== undefined ? Number(a.outX) - ox : ax) : ax;
                var c1y = aSmooth ? (a.outY !== undefined ? Number(a.outY) - oy : ay) : ay;
                var c2x = bSmooth ? (b.inX !== undefined ? Number(b.inX) - ox : bx) : bx;
                var c2y = bSmooth ? (b.inY !== undefined ? Number(b.inY) - oy : by) : by;
                return " C " + c1x + "," + c1y + " " + c2x + "," + c2y + " " + bx + "," + by;
            };
            for (var i = 1; i < pts.length; i++)
                d += seg(pts[i - 1], pts[i]);
            if (sub.closed === true && pts.length > 1)
                d += seg(pts[pts.length - 1], pts[0]) + " Z";
        }
        return d;
    }
}
