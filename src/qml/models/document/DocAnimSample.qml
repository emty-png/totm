import QtQuick

// Pure animation sampler: per-preset overlay math plus sampling and
// writeback. sampleAnim() evaluates overlays against a STABLE base
// snapshot (never the live tree: reading live values would feed each
// frame's output back as the next frame's input and collapse every
// preset). applySample() writes overlays with no touch() so playback
// never dirties the doc, never triggers autosave, never pollutes undo.
// Easing curves live in DocEasing, motion-path measuring in
// DocPathSample. Units match the C++ video renderer (AnimSampler), which
// ports this file: times in seconds, angles in degrees, distances in
// canvas px.
QtObject {
    id: sampler

    property var easing: DocEasing {
        id: samplerEasing
    }
    property var path: DocPathSample {
        id: samplerPath
    }

    // Easing pass-through (math lives in DocEasing): preset cards and
    // the graph canvas sample curves straight off the sampler.
    function easeValue(id, bezier, t) {
        return samplerEasing.easeValue(id, bezier, t);
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

    // Param is `to`, not `toHex`: that name would shadow the helper below.
    function lerpColor(fromHex, to, t) {
        var a = parseHex(fromHex);
        var b = parseHex(to);
        if (!a || !b)
            return null;
        return toHex(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t));
    }

    // Alpha-aware twin for shadow colors (#aarrggbb in, out). Opaque
    // pairs stay #rrggbb so stored clips never gain stray alpha.
    function parseHexA(hex) {
        var t = String(hex || "").trim().toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (/^[0-9a-f]{3}$/.test(t))
            t = t.charAt(0) + t.charAt(0) + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2);
        var a = 255;
        if (t.length === 8) {
            a = parseInt(t.slice(0, 2), 16);
            if (isNaN(a))
                return null;
            t = t.slice(2);
        } else if (t.length !== 6) {
            return null;
        }
        if (!/^[0-9a-f]{6}$/.test(t))
            return null;
        return {
            a: a,
            r: parseInt(t.slice(0, 2), 16),
            g: parseInt(t.slice(2, 4), 16),
            b: parseInt(t.slice(4, 6), 16)
        };
    }

    function lerpColorA(fromHex, to, t) {
        var a = parseHexA(fromHex);
        var b = parseHexA(to);
        if (!a || !b)
            return null;
        var al = Math.round(Math.min(255, Math.max(0, lerp(a.a, b.a, t))));
        var body = toHex(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t)).slice(1);
        if (al >= 255)
            return "#" + body;
        var h = al.toString(16);
        return "#" + (h.length === 1 ? "0" + h : h) + body;
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
        } else if (preset === "customGradient") {
            // Fill gradient from-to: stop colors ease in sRGB, angle
            // linearly. Ports to AnimSampler; also flips fillType so a
            // solid base renders the gradient from the first frame.
            var gc1 = lerpColor(o.fromC1, o.toC1, e);
            var gc2 = lerpColor(o.fromC2, o.toC2, e);
            if (gc1 && gc2) {
                out.fillType = "linear";
                out.fillGradient = {
                    angle: lerp(Number(o.fromAngle) || 0, Number(o.toAngle) || 0, e),
                    stops: [
                        {
                            color: gc1,
                            pos: 0
                        },
                        {
                            color: gc2,
                            pos: 1
                        }
                    ]
                };
            }
        } else if (preset === "customShadow") {
            var sc = lerpColorA(o.fromColor, o.toColor, e);
            if (sc) {
                out.shadows = [
                    {
                        enabled: true,
                        // Stepped like customHide (bools can't ease): first
                        // half reads from, second half reads to.
                        inner: e < 0.5 ? o.fromInner === true : o.toInner === true,
                        color: sc,
                        x: lerp(Number(o.fromX) || 0, Number(o.toX) || 0, e),
                        y: lerp(Number(o.fromY) || 0, Number(o.toY) || 0, e),
                        blur: Math.max(0, lerp(Number(o.fromBlur) || 0, Number(o.toBlur) || 0, e)),
                        spread: Math.max(0, lerp(Number(o.fromSpread) || 0, Number(o.toSpread) || 0, e))
                    }
                ];
            }
        } else if (preset === "customLayerBlur") {
            out.layerBlur = {
                enabled: true,
                radius: Math.max(0, lerp(Number(o.fromRadius) || 0, Number(o.toRadius) || 0, e)),
                opacity: Math.min(1, Math.max(0, lerp(Number(o.fromOpacity) ?? 1, Number(o.toOpacity) ?? 1, e)))
            };
        } else if (preset === "customBackgroundBlur") {
            out.backgroundBlur = {
                enabled: true,
                radius: Math.max(0, lerp(Number(o.fromRadius) || 0, Number(o.toRadius) || 0, e)),
                opacity: Math.min(1, Math.max(0, lerp(Number(o.fromOpacity) ?? 0.7, Number(o.toOpacity) ?? 0.7, e)))
            };
        } else if (preset === "customGlow") {
            var gc = lerpColorA(o.fromColor, o.toColor, e);
            if (gc) {
                out.glows = [
                    {
                        enabled: true,
                        // Stepped like customHide (bools can't ease): first
                        // half reads from, second half reads to.
                        inner: e < 0.5 ? o.fromInner === true : o.toInner === true,
                        color: gc,
                        blur: Math.max(0, lerp(Number(o.fromBlur) || 0, Number(o.toBlur) || 0, e)),
                        spread: Math.max(0, lerp(Number(o.fromSpread) || 0, Number(o.toSpread) || 0, e))
                    }
                ];
            }
        } else if (preset === "customGrain") {
            out.grain = {
                enabled: true,
                amount: Math.min(1, Math.max(0, lerp(Number(o.fromAmount) || 0, Number(o.toAmount) || 0, e))),
                size: Math.min(10, Math.max(1, lerp(Number(o.fromSize) || 0, Number(o.toSize) || 0, e)))
            };
        } else if (preset === "customPath") {
            var sampled = samplerPath.samplePath(o.pts, o.closed === true, e);
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
            var e = samplerEasing.easeValue(ez.id || "easeOut", ez.bezier, p);
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
    // Nodes resolve in one traversal (not one tree search per leaf), so
    // wide scenes stay at 60fps; every write below is unchanged.
    function applySample(doc, map) {
        var anyWork = false;
        for (var probe in map) {
            anyWork = true;
            break;
        }
        if (!anyWork)
            return;
        var byUid = {};
        var all = doc.tree.allLeaves();
        for (var i = 0; i < all.length; i++)
            byUid[all[i].uid] = all[i];
        for (var uid in map) {
            var n = byUid[Number(uid)] ?? doc.findNode(Number(uid));
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
            if (ov.fillType !== undefined)
                n.fillType = ov.fillType;
            if (ov.fillGradient !== undefined)
                n.fillGradient = {
                    angle: ov.fillGradient.angle,
                    stops: [
                        {
                            color: String(ov.fillGradient.stops[0].color),
                            pos: 0
                        },
                        {
                            color: String(ov.fillGradient.stops[1].color),
                            pos: 1
                        }
                    ]
                };
            if (ov.shadows !== undefined) {
                var shOut = [];
                var shSrc = ov.shadows || [];
                for (var si = 0; si < shSrc.length; si++) {
                    var ss = shSrc[si] || {};
                    shOut.push({
                        enabled: ss.enabled !== false,
                        inner: ss.inner === true,
                        color: String(ss.color),
                        x: ss.x,
                        y: ss.y,
                        blur: ss.blur,
                        spread: ss.spread
                    });
                }
                n.shadows = shOut;
            }
            if (ov.layerBlur !== undefined)
                n.layerBlur = {
                    enabled: ov.layerBlur.enabled === true,
                    radius: Math.max(0, Number(ov.layerBlur.radius) || 0),
                    opacity: Math.min(1, Math.max(0, Number(ov.layerBlur.opacity ?? 1)))
                };
            if (ov.backgroundBlur !== undefined)
                n.backgroundBlur = {
                    enabled: ov.backgroundBlur.enabled === true,
                    radius: Math.max(0, Number(ov.backgroundBlur.radius) || 0),
                    opacity: Math.min(1, Math.max(0, Number(ov.backgroundBlur.opacity ?? 0.7)))
                };
            if (ov.glows !== undefined) {
                var glOut = [];
                var glSrc = ov.glows || [];
                for (var gi = 0; gi < glSrc.length; gi++) {
                    var gs = glSrc[gi] || {};
                    glOut.push({
                        enabled: gs.enabled !== false,
                        inner: gs.inner === true,
                        color: String(gs.color),
                        blur: Math.max(0, Number(gs.blur) || 0),
                        spread: Math.max(0, Number(gs.spread) || 0)
                    });
                }
                n.glows = glOut;
            }
            if (ov.grain !== undefined)
                n.grain = {
                    enabled: ov.grain.enabled === true,
                    amount: Math.min(1, Math.max(0, Number(ov.grain.amount) || 0)),
                    size: Math.min(10, Math.max(1, Number(ov.grain.size) || 0))
                };
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
