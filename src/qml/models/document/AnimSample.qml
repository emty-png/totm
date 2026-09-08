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
                if (!doc.isEffectivelyVisible(lf))
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
    function applySample(doc, map) {
        for (var uid in map) {
            var n = doc.findNode(Number(uid));
            if (!n || doc.isEffectivelyLocked(n))
                continue;
            var ov = map[uid];
            if (ov.x !== undefined)
                n.x = ov.x;
            if (ov.y !== undefined)
                n.y = ov.y;
            if (ov.w !== undefined)
                n.w = ov.w;
            if (ov.h !== undefined)
                n.h = ov.h;
            if (ov.rotation !== undefined)
                n.rotation = ov.rotation;
            if (ov.opacity !== undefined)
                n.opacity = ov.opacity;
            if (ov.fontSize !== undefined && n.shapeType === "text")
                n.fontSize = ov.fontSize;
        }
    }
}
