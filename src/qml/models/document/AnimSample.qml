import QtQuick

// Pure animation sampler: easing table plus per-preset overlay math.
// sampleAnim() evaluates overlays against a STABLE base snapshot (never
// the live tree: reading live values would feed each frame's output back
// as the next frame's input and collapse every preset). applySample()
// writes overlays with no touch() so playback never dirties the doc,
// never triggers autosave, never pollutes undo.
// Units are frozen for the future backend: times in seconds, angles in
// degrees, distances in canvas px, cubic-bezier solved by Newton plus a
// bisection fallback. The C++ video renderer ports this file 1:1.
QtObject {
    id: sampler

    // Easing ids: linear | easeIn | easeOut | easeInOut | slowDown |
    // custom (cubic-bezier [x1, y1, x2, y2]). Cubics match CSS
    // ease-in/out/in-out; slowDown is bezier(0.22, 1, 0.36, 1).
    function easeValue(id, bezier, t) {
        var x = Math.min(1, Math.max(0, t));
        if (id === "linear")
            return x;
        if (id === "easeIn")
            return x * x * x;
        if (id === "easeOut") {
            var u = 1 - x;
            return 1 - u * u * u;
        }
        if (id === "easeInOut")
            return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
        if (id === "custom") {
            var b = bezier || [0.25, 0.1, 0.25, 1];
            return cubicBezier(b[0], b[1], b[2], b[3], x);
        }
        if (id === "slowDown")
            return cubicBezier(0.22, 1, 0.36, 1, x);
        return x;
    }

    function cubicBezier(x1, y1, x2, y2, x) {
        if (x <= 0)
            return 0;
        if (x >= 1)
            return 1;
        var s = x, converged = false;
        for (var i = 0; i < 8; i++) {
            var u = 1 - s;
            var xs = 3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s;
            var dx = 3 * u * u * x1 + 6 * u * s * (x2 - x1) + 3 * s * s * (1 - x2);
            if (Math.abs(xs - x) < 1e-6) {
                converged = true;
                break;
            }
            if (Math.abs(dx) < 1e-6 || (s = s - (xs - x) / dx) < 0 || s > 1)
                break;
        }
        if (!converged) {
            var lo = 0, hi = 1;
            s = Math.min(1, Math.max(0, s));
            for (var j = 0; j < 24; j++) {
                var v = 1 - s;
                var xsv = 3 * v * v * s * x1 + 3 * v * s * s * x2 + s * s * s;
                if (Math.abs(xsv - x) < 1e-6)
                    break;
                if (xsv < x)
                    lo = s;
                else
                    hi = s;
                s = (lo + hi) / 2;
            }
        }
        var w = 1 - s;
        return 3 * w * w * s * y1 + 3 * w * s * s * y2 + s * s * s;
    }

    function slideVec(direction) {
        if (direction === "right")
            return {
                x: 1,
                y: 0
            };
        if (direction === "up")
            return {
                x: 0,
                y: -1
            };
        if (direction === "down")
            return {
                x: 0,
                y: 1
            };
        return {
            x: -1,
            y: 0
        };
    }

    function scaleBox(b, cx, cy, s) {
        return {
            x: cx + (b.x - cx) * s,
            y: cy + (b.y - cy) * s,
            w: Math.max(0.01, b.w * s),
            h: Math.max(0.01, b.h * s)
        };
    }

    function lerp(a, b, t) {
        return a + (b - a) * t;
    }

    function parseHex(hex) {
        var t = String(hex || "").trim().toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (/^[0-9a-f]{3}$/.test(t))
            t = t.charAt(0) + t.charAt(0) + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2);
        if (!/^[0-9a-f]{6}$/.test(t))
            return null;
        return {
            r: parseInt(t.slice(0, 2), 16),
            g: parseInt(t.slice(2, 4), 16),
            b: parseInt(t.slice(4, 6), 16)
        };
    }

    function toHex(r, g, b) {
        function hx(v) {
            var c = Math.round(Math.min(255, Math.max(0, v))).toString(16);
            return c.length < 2 ? "0" + c : c;
        }
        return "#" + hx(r) + hx(g) + hx(b);
    }

    function lerpColor(fromHex, toHex, t) {
        var a = parseHex(fromHex);
        var b = parseHex(toHex);
        if (!a || !b)
            return null;
        return toHex(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t));
    }

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
                var p0 = cubicPoint(segs[s].a, segs[s].b, k / steps);
                var p1 = cubicPoint(segs[s].a, segs[s].b, (k + 1) / steps);
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

    // One clip's contribution for a single leaf. base holds the leaf's
    // captured values ({x, y, w, h, rotation, opacity, fontSize,
    // shapeType}) and is the ONLY read source: deriving frames from live
    // node values would integrate each frame's output back in (fade
    // multiplies toward zero, slide drifts away). e is eased progress,
    // p is raw progress (appear steps on it, sway needs the linear
    // clock). cx/cy is the target's bbox center from base.
    function presetOverlay(preset, mode, o, base, cx, cy, e, p) {
        var out = {};
        var inward = mode !== "out";
        if (preset === "appear") {
            // Hard pop on the raw clock (easing-independent): visible
            // from the first stepped frame in, held till the last frame
            // out. Base opacity scales it like every other preset.
            out.opacity = base.opacity * (inward ? (p <= 0 ? 0 : 1) : (p >= 1 ? 0 : 1));
        } else if (preset === "fade") {
            out.opacity = base.opacity * (inward ? e : 1 - e);
        } else if (preset === "slide" || preset === "movescale") {
            var d = slideVec(o.direction);
            var dist = Math.max(0, o.distance || 0);
            var k = inward ? 1 - e : e;
            var sgn = inward ? -1 : 1;
            var bx = base.x, by = base.y, bw = base.w, bh = base.h;
            if (preset === "movescale") {
                var s0 = Math.max(0, (o.scale === undefined ? 0 : o.scale) / 100);
                var s = inward ? s0 + (1 - s0) * e : 1 + (s0 - 1) * e;
                var g = scaleBox({
                    x: base.x,
                    y: base.y,
                    w: base.w,
                    h: base.h
                }, cx, cy, Math.max(0.001, s));
                bx = g.x;
                by = g.y;
                bw = g.w;
                bh = g.h;
            }
            out.x = bx + sgn * d.x * dist * k;
            out.y = by + sgn * d.y * dist * k;
            if (preset === "movescale" || o.fade) {
                out.opacity = base.opacity * (inward ? e : 1 - e);
            }
            if (preset === "movescale") {
                out.w = bw;
                out.h = bh;
            }
        } else if (preset === "grow" || preset === "shrink") {
            var end = preset === "grow" ? 0 : 1.5;
            var sc = inward ? end + (1 - end) * e : 1 + (end - 1) * e;
            var gs = scaleBox({
                x: base.x,
                y: base.y,
                w: base.w,
                h: base.h
            }, cx, cy, Math.max(0.001, sc));
            out.x = gs.x;
            out.y = gs.y;
            out.w = gs.w;
            out.h = gs.h;
            // Text scales its glyphs, not just its box: a bigger box
            // with the same font would only reflow. Glyph width tracks
            // font size linearly, so the scaled box stays registered.
            if (base.shapeType === "text" && base.fontSize > 0)
                out.fontSize = base.fontSize * sc;
        } else if (preset === "spin") {
            var turns = Math.min(10, Math.max(0.25, o.turns || 1));
            var dir = o.direction === "ccw" ? -1 : 1;
            out.rotation = base.rotation + dir * 360 * turns * (inward ? 1 - e : e);
        } else if (preset === "twist") {
            var dir2 = o.direction === "ccw" ? -1 : 1;
            var env = inward ? 1 - p : p;
            out.rotation = base.rotation + dir2 * 15 * Math.sin(p * 4 * Math.PI) * env;
        } else if (preset === "customScale") {
            // Uniform factor about the target center (group-aware like
            // grow). From/to are factors, base supplies the box.
            var sc = lerp(Number(o.from) || 0, Number(o.to) || 0, e);
            var cgs = scaleBox({
                x: base.x,
                y: base.y,
                w: base.w,
                h: base.h
            }, cx, cy, Math.max(0.001, sc));
            out.x = cgs.x;
            out.y = cgs.y;
            out.w = cgs.w;
            out.h = cgs.h;
            if (base.shapeType === "text" && base.fontSize > 0)
                out.fontSize = base.fontSize * Math.max(0.001, sc);
        } else if (preset === "customRotate") {
            // Offset degrees from base (no jump, stays valid on move).
            out.rotation = (Number(base.rotation) || 0) + lerp(Number(o.from) || 0, Number(o.to) || 0, e);
        } else if (preset === "customMove") {
            // Relative offset from base (drawn paths stay valid on move).
            out.x = (Number(base.x) || 0) + lerp(Number(o.fromX) || 0, Number(o.toX) || 0, e);
            out.y = (Number(base.y) || 0) + lerp(Number(o.fromY) || 0, Number(o.toY) || 0, e);
        } else if (preset === "customOpacity") {
            out.opacity = lerp(Number(o.from) || 0, Number(o.to) || 0, e);
        } else if (preset === "customColor") {
            var cc = lerpColor(o.from, o.to, e);
            if (cc)
                out.fill = cc;
        } else if (preset === "customHide") {
            // Stepped visibility (bools can't ease): first half reads
            // from, second half reads to.
            out.visible = e < 0.5 ? o.fromVisible !== false : o.toVisible === true;
        } else if (preset === "customResize") {
            // Absolute box centered on the leaf's own center (shape-only
            // semantics; groups equalize per leaf but keep centers).
            var nw = Math.max(1, lerp(Number(o.fromW) || 0, Number(o.toW) || 0, e));
            var nh = Math.max(1, lerp(Number(o.fromH) || 0, Number(o.toH) || 0, e));
            var lcx = (Number(base.x) || 0) + (Number(base.w) || 0) / 2;
            var lcy = (Number(base.y) || 0) + (Number(base.h) || 0) / 2;
            out.x = lcx - nw / 2;
            out.y = lcy - nh / 2;
            out.w = nw;
            out.h = nh;
        } else if (preset === "customCorner") {
            out.radius = lerp(Number(o.from) || 0, Number(o.to) || 0, e);
        } else if (preset === "customStroke") {
            out.strokeWidth = lerp(Number(o.from) || 0, Number(o.to) || 0, e);
        } else if (preset === "customPath") {
            var sampled = samplePath(o.pts, o.closed === true, e);
            if (sampled) {
                out.x = (Number(base.x) || 0) + sampled.dx;
                out.y = (Number(base.y) || 0) + sampled.dy;
                if (o.orient === true)
                    out.rotation = (Number(base.rotation) || 0) + sampled.angleDelta;
            }
        }
        return out;
    }

    // Full overlay map for time t: later clips win per property, so
    // stacked presets coexist (Slide owns x/y, Fade owns opacity) while
    // same-property overlaps resolve to the topmost clip. Times outside
    // a clip hold its end state; times before its start stay silent.
    // Every frame derives from base (the playBase snapshot, or live
    // values only for nodes born mid-play): never from the live tree.
    function sampleAnim(doc, t, base) {
        var acc = {};
        var clips = doc.anim.clips;
        for (var i = 0; i < clips.length; i++) {
            var c = clips[i];
            if (t < c.t0)
                continue;
            var dur = Math.max(0.001, c.duration);
            var p = Math.min(1, Math.max(0, (t - c.t0) / dur));
            var ez = c.easing || {};
            var e = easeValue(ez.id || "easeOut", ez.bezier, p);
            var node = doc.findNode(c.targetUid);
            if (!node)
                continue;
            var leaves = node.kind === "group" ? doc._leavesUnder(node) : [node];
            var box = baseBox(doc, leaves, base);
            if (!box)
                continue;
            var cx = box.x + box.w / 2, cy = box.y + box.h / 2;
            for (var j = 0; j < leaves.length; j++) {
                var lf = leaves[j];
                if (c.preset !== "customHide" && !doc.isEffectivelyVisible(lf))
                    continue;
                var bv = base && base[lf.uid] ? base[lf.uid] : lf;
                var ov = presetOverlay(c.preset, c.mode, c.options || {}, bv, cx, cy, e, p);
                var entry = acc[lf.uid] || {};
                for (var k in ov)
                    entry[k] = ov[k];
                acc[lf.uid] = entry;
            }
        }
        return acc;
    }

    // Axis-aligned bbox over base rects, never the live tree: the center
    // stays fixed for the whole gesture even as leaves move, so group
    // transforms never chase themselves from frame to frame.
    function baseBox(doc, leaves, base) {
        var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        var found = false;
        for (var i = 0; i < leaves.length; i++) {
            var b = base && base[leaves[i].uid] ? base[leaves[i].uid] : leaves[i];
            if (b.x === undefined || b.w <= 0 || b.h <= 0)
                continue;
            found = true;
            if (b.x < x0)
                x0 = b.x;
            if (b.y < y0)
                y0 = b.y;
            if (b.x + b.w > x1)
                x1 = b.x + b.w;
            if (b.y + b.h > y1)
                y1 = b.y + b.h;
        }
        if (!found)
            return null;
        return {
            x: x0,
            y: y0,
            w: Math.max(0.01, x1 - x0),
            h: Math.max(0.01, y1 - y0)
        };
    }

    // Writes an overlay map with no touch(): playback stays invisible to
    // autosave, undo and selection bindings. Locked leaves hold still.
    // Pen paths ride their bbox so previews never shear off the points.
    function applySample(doc, map) {
        for (var uid in map) {
            var n = doc.findNode(Number(uid));
            if (!n || doc.isEffectivelyLocked(n))
                continue;
            var ov = map[uid];
            if (n.shapeType === "pen" && (ov.x !== undefined || ov.y !== undefined || ov.w !== undefined || ov.h !== undefined)) {
                var nx = ov.x !== undefined ? ov.x : n.x;
                var ny = ov.y !== undefined ? ov.y : n.y;
                var nw = ov.w !== undefined ? Math.max(0.01, ov.w) : n.w;
                var nh = ov.h !== undefined ? Math.max(0.01, ov.h) : n.h;
                var sx = n.w > 0 ? nw / n.w : 1;
                var sy = n.h > 0 ? nh / n.h : 1;
                var src = n.pathData || [];
                var out = [];
                for (var i = 0; i < src.length; i++) {
                    var sub = src[i] || {};
                    var pts = [];
                    var arr = sub.pts || [];
                    for (var j = 0; j < arr.length; j++) {
                        var p = arr[j] || {};
                        var px = Number(p.x) || 0, py = Number(p.y) || 0;
                        var ix = p.inX !== undefined ? Number(p.inX) : px;
                        var iy = p.inY !== undefined ? Number(p.inY) : py;
                        var ox = p.outX !== undefined ? Number(p.outX) : px;
                        var oy = p.outY !== undefined ? Number(p.outY) : py;
                        pts.push({
                            x: nx + (px - n.x) * sx,
                            y: ny + (py - n.y) * sy,
                            smooth: p.smooth === true,
                            inX: nx + (ix - n.x) * sx,
                            inY: ny + (iy - n.y) * sy,
                            outX: nx + (ox - n.x) * sx,
                            outY: ny + (oy - n.y) * sy
                        });
                    }
                    out.push({
                        closed: sub.closed === true,
                        pts: pts
                    });
                }
                n.pathData = out;
                n.x = nx;
                n.y = ny;
                n.w = nw;
                n.h = nh;
            } else {
                if (ov.x !== undefined)
                    n.x = ov.x;
                if (ov.y !== undefined)
                    n.y = ov.y;
                if (ov.w !== undefined)
                    n.w = ov.w;
                if (ov.h !== undefined)
                    n.h = ov.h;
            }
            if (ov.rotation !== undefined)
                n.rotation = ov.rotation;
            if (ov.opacity !== undefined)
                n.opacity = ov.opacity;
            if (ov.fontSize !== undefined && n.shapeType === "text")
                n.fontSize = ov.fontSize;
            if (ov.fill !== undefined)
                n.fill = ov.fill;
            if (ov.visible !== undefined)
                n.visible = ov.visible;
            if (ov.radius !== undefined) {
                var rv = Math.max(0, Number(ov.radius) || 0);
                n.radius = rv;
                if (n.independentCorners)
                    n.cornerRadii = [rv, rv, rv, rv];
            }
            if (ov.strokeWidth !== undefined)
                n.strokeWidth = Math.max(0, Number(ov.strokeWidth) || 0);
        }
    }
}
