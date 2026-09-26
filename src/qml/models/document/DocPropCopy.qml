import QtQuick
import Totm

// Panel three-dot copy/paste for design properties and animation clips.
// Design scope ("Everything"): values = every value incl. geometry,
// typography and style values applied onto same-index entries (never
// adds/removes entries); props = style structure only (entry counts,
// paint types, dash positions, inner flags, enabled toggles); both =
// wholesale replace. Animation scope: same-preset clips across objects
// (values = option values incl. keyframes, props = timing/easing/mode/
// loop/entry shell, both = full replace); missing target clips are
// created. Payloads ride TabState.propClipboard so copy works across
// shapes and designs. Pastes checkpoint once for a single undo entry.
QtObject {
    id: propCopy
    required property var doc

    // ---- design: source snapshot ----

    function firstLeaf() {
        if (!propCopy.doc)
            return null;
        var tops = propCopy.doc.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            if (tops[i].kind === "shape")
                return tops[i];
            var leaves = propCopy.doc._leavesUnder(tops[i]);
            if (leaves.length > 0)
                return leaves[0];
        }
        return null;
    }

    function targetLeaves() {
        var out = [];
        if (!propCopy.doc)
            return out;
        var tops = propCopy.doc.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            var leaves = tops[i].kind === "shape" ? [tops[i]] : propCopy.doc._leavesUnder(tops[i]);
            for (var j = 0; j < leaves.length; j++) {
                if (!propCopy.doc.isEffectivelyLocked(leaves[j]))
                    out.push({
                        node: leaves[j],
                        // Geometry pastes only onto direct shape tops;
                        // group descendants keep their layout.
                        geom: tops[i].kind === "shape"
                    });
            }
        }
        return out;
    }

    function canCopyDesign() {
        return propCopy.firstLeaf() !== null;
    }

    function canPasteDesign() {
        var c = TabState.propClipboard;
        if (!c || c.scope !== "design")
            return false;
        return propCopy.targetLeaves().length > 0;
    }

    function snapValues(n) {
        var f = propCopy.doc.factory;
        var fills = [], strokes = [], shadows = [], glows = [];
        var src = n.fills || [];
        for (var i = 0; i < src.length; i++) {
            var fe = src[i] ?? {};
            var fg = fe.gradient ?? {};
            var fs = fg.stops ?? [];
            fills.push({
                color: String(fe.color ?? "#d9d9d9"),
                opacity: propCopy._op(fe.opacity),
                gradient: {
                    angle: Number(fg.angle) || 0,
                    c1: String((fs[0] ?? {}).color ?? "#000000"),
                    c2: String((fs[1] ?? {}).color ?? "#ffffff")
                }
            });
        }
        var st = n.strokes || [];
        for (var j = 0; j < st.length; j++) {
            var se = st[j] ?? {};
            var sg = se.gradient ?? {};
            var ss = sg.stops ?? [];
            var dd = (se.dash && typeof se.dash.length === "number") ? se.dash : [];
            strokes.push({
                color: String(se.color ?? "#000000"),
                opacity: propCopy._op(se.opacity),
                width: Math.max(0, Number(se.width) || 0),
                dash: dd.length > 0 ? Math.max(0, Number(dd[0]) || 0) : 0,
                gap: dd.length > 1 ? Math.max(0, Number(dd[1]) || 0) : 0,
                gradient: {
                    angle: Number(sg.angle) || 0,
                    c1: String((ss[0] ?? {}).color ?? "#000000"),
                    c2: String((ss[1] ?? {}).color ?? "#ffffff")
                }
            });
        }
        var sh = n.shadows || [];
        for (var k = 0; k < sh.length; k++) {
            var he = sh[k] ?? {};
            shadows.push({
                color: String(he.color ?? "#80000000"),
                x: Number(he.x) || 0,
                y: he.y !== undefined ? (Number(he.y) || 0) : 4,
                blur: Math.max(0, Number(he.blur) || 0),
                spread: Math.max(0, Number(he.spread) || 0)
            });
        }
        var gl = n.glows || [];
        for (var m = 0; m < gl.length; m++) {
            var ge = gl[m] ?? {};
            glows.push({
                color: String(ge.color ?? "#cc00ffff"),
                blur: Math.max(0, Number(ge.blur) || 0),
                spread: Math.max(0, Number(ge.spread) || 0)
            });
        }
        var lb = n.layerBlur ?? {}, bb = n.backgroundBlur ?? {}, gr = n.grain ?? {};
        return {
            geom: {
                x: n.x,
                y: n.y,
                w: n.w,
                h: n.h,
                rotation: n.rotation,
                opacity: n.opacity,
                radius: n.radius,
                flipH: n.flipH === true,
                flipV: n.flipV === true,
                independentCorners: n.independentCorners === true,
                cornerRadii: (n.cornerRadii || []).slice()
            },
            typo: n.shapeType === "text" ? {
                textContent: String(n.textContent ?? ""),
                fontFamily: String(n.fontFamily ?? ""),
                fontWeight: n.fontWeight,
                fontSize: n.fontSize,
                lineHeightAuto: n.lineHeightAuto !== false,
                lineHeight: n.lineHeight,
                letterSpacing: n.letterSpacing,
                hAlign: n.hAlign,
                vAlign: n.vAlign,
                autoSize: n.autoSize
            } : null,
            pen: n.shapeType === "pen" ? {
                penFill: n.penFill !== false,
                strokeCap: n.strokeCap ?? "round",
                strokeJoin: n.strokeJoin ?? "round"
            } : null,
            image: n.shapeType === "image" ? {
                imageSource: String(n.imageSource ?? "")
            } : null,
            fills: fills,
            strokes: strokes,
            shadows: shadows,
            glows: glows,
            layerBlur: {
                radius: Math.max(0, Number(lb.radius) || 0),
                opacity: propCopy._op(lb.opacity, 1)
            },
            backgroundBlur: {
                radius: Math.max(0, Number(bb.radius) || 0),
                opacity: propCopy._op(bb.opacity, 0.7)
            },
            grain: {
                amount: Math.min(1, Math.max(0, Number(gr.amount) || 0)),
                size: Math.min(10, Math.max(1, Number(gr.size) || 2))
            },
            mask: {
                feather: Math.max(0, Number(n.maskFeather) || 0),
                inverted: n.maskInverted === true
            }
        };
    }

    function snapProps(n) {
        var fills = [], strokes = [], shadows = [], glows = [];
        var src = n.fills || [];
        for (var i = 0; i < src.length; i++) {
            var fe = src[i] ?? {};
            fills.push({
                type: fe.type === "linear" ? "linear" : "solid",
                enabled: fe.enabled !== false
            });
        }
        var st = n.strokes || [];
        for (var j = 0; j < st.length; j++) {
            var se = st[j] ?? {};
            strokes.push({
                type: se.type === "linear" ? "linear" : "solid",
                enabled: se.enabled !== false,
                position: (se.position === "inside" || se.position === "outside") ? se.position : "center"
            });
        }
        var sh = n.shadows || [];
        for (var k = 0; k < sh.length; k++) {
            var he = sh[k] ?? {};
            shadows.push({
                inner: he.inner === true,
                enabled: he.enabled !== false
            });
        }
        var gl = n.glows || [];
        for (var m = 0; m < gl.length; m++) {
            var ge = gl[m] ?? {};
            glows.push({
                inner: ge.inner === true,
                enabled: ge.enabled !== false
            });
        }
        var lb = n.layerBlur ?? {}, bb = n.backgroundBlur ?? {}, gr = n.grain ?? {};
        return {
            fills: fills,
            strokes: strokes,
            shadows: shadows,
            glows: glows,
            layerBlur: lb.enabled === true,
            backgroundBlur: bb.enabled === true,
            grain: gr.enabled === true,
            mask: n.isMask === true
        };
    }

    function copyDesign(mode) {
        var n = propCopy.firstLeaf();
        if (!n)
            return false;
        var m = mode === "props" ? "props" : mode === "both" ? "both" : "values";
        var payload = {};
        if (m === "values" || m === "both")
            payload.values = propCopy.snapValues(n);
        if (m === "props" || m === "both")
            payload.props = propCopy.snapProps(n);
        TabState.propClipboard = {
            scope: "design",
            mode: m,
            payload: payload
        };
        return true;
    }

    // Values ride onto same-index entries (structure untouched);
    // extras on either side are skipped. Returns applied leaf count.
    function pasteDesignValues(v) {
        var targets = propCopy.targetLeaves();
        if (targets.length === 0)
            return 0;
        propCopy.doc.history.checkpoint();
        for (var i = 0; i < targets.length; i++)
            propCopy.applyDesignValues(targets[i].node, targets[i].geom, v);
        propCopy.doc.touch();
        return targets.length;
    }

    function applyDesignValues(n, geom, v) {
        var f = propCopy.doc.factory;
        if (geom) {
            var g = v.geom;
            n.x = g.x;
            n.y = g.y;
            n.w = Math.max(0.01, g.w);
            n.h = Math.max(0.01, g.h);
            n.rotation = g.rotation;
            n.opacity = g.opacity;
            n.radius = Math.max(0, g.radius);
            n.flipH = g.flipH === true;
            n.flipV = g.flipV === true;
            if (g.independentCorners && (g.cornerRadii || []).length === 4) {
                n.independentCorners = true;
                n.cornerRadii = g.cornerRadii.slice();
            } else {
                n.independentCorners = false;
            }
        }
        if (v.typo && n.shapeType === "text") {
            var t = v.typo;
            n.textContent = String(t.textContent);
            if (t.fontFamily !== "")
                n.fontFamily = String(t.fontFamily);
            n.fontWeight = t.fontWeight;
            n.fontSize = Math.min(500, Math.max(1, Number(t.fontSize) || 16));
            n.lineHeightAuto = t.lineHeightAuto !== false;
            n.lineHeight = t.lineHeight;
            n.letterSpacing = t.letterSpacing;
            n.hAlign = t.hAlign;
            n.vAlign = t.vAlign;
            n.autoSize = t.autoSize;
        }
        if (v.pen && n.shapeType === "pen") {
            n.penFill = v.pen.penFill !== false;
            n.strokeCap = v.pen.strokeCap ?? "round";
            n.strokeJoin = v.pen.strokeJoin ?? "round";
        }
        if (v.image && n.shapeType === "image" && v.image.imageSource !== "")
            n.imageSource = String(v.image.imageSource);
        var dst = f._copyFills(n.fills, n);
        var lim = Math.min(dst.length, v.fills.length);
        for (var fi = 0; fi < lim; fi++) {
            dst[fi].color = String(v.fills[fi].color);
            dst[fi].opacity = propCopy._op(v.fills[fi].opacity);
            dst[fi].gradient = f._copyGradient({
                angle: v.fills[fi].gradient.angle,
                stops: [
                    {
                        color: v.fills[fi].gradient.c1,
                        pos: 0
                    },
                    {
                        color: v.fills[fi].gradient.c2,
                        pos: 1
                    }
                ]
            });
        }
        n.fills = dst;
        var ds = f._copyStrokes(n.strokes, n);
        var sl = Math.min(ds.length, v.strokes.length);
        for (var si = 0; si < sl; si++) {
            ds[si].color = String(v.strokes[si].color);
            ds[si].opacity = propCopy._op(v.strokes[si].opacity);
            ds[si].width = Math.max(0, Number(v.strokes[si].width) || 0);
            var dd = Number(v.strokes[si].dash) || 0, gg = Number(v.strokes[si].gap) || 0;
            ds[si].dash = (dd > 0.001 && gg > 0.001) ? [dd, gg] : [];
            ds[si].gradient = f._copyGradient({
                angle: v.strokes[si].gradient.angle,
                stops: [
                    {
                        color: v.strokes[si].gradient.c1,
                        pos: 0
                    },
                    {
                        color: v.strokes[si].gradient.c2,
                        pos: 1
                    }
                ]
            });
        }
        n.strokes = ds;
        var dh = f._copyShadows(n.shadows);
        var hl = Math.min(dh.length, v.shadows.length);
        for (var hi = 0; hi < hl; hi++) {
            dh[hi].color = String(v.shadows[hi].color);
            dh[hi].x = Number(v.shadows[hi].x) || 0;
            dh[hi].y = Number(v.shadows[hi].y) || 0;
            dh[hi].blur = Math.max(0, Number(v.shadows[hi].blur) || 0);
            dh[hi].spread = Math.max(0, Number(v.shadows[hi].spread) || 0);
        }
        n.shadows = dh;
        var dg = f._copyGlows(n.glows);
        var gl2 = Math.min(dg.length, v.glows.length);
        for (var gi = 0; gi < gl2; gi++) {
            dg[gi].color = String(v.glows[gi].color);
            dg[gi].blur = Math.max(0, Number(v.glows[gi].blur) || 0);
            dg[gi].spread = Math.max(0, Number(v.glows[gi].spread) || 0);
        }
        n.glows = dg;
        n.layerBlur = {
            enabled: (n.layerBlur ?? {}).enabled === true,
            radius: Math.max(0, Number(v.layerBlur.radius) || 0),
            opacity: propCopy._op(v.layerBlur.opacity, 1)
        };
        n.backgroundBlur = {
            enabled: (n.backgroundBlur ?? {}).enabled === true,
            radius: Math.max(0, Number(v.backgroundBlur.radius) || 0),
            opacity: propCopy._op(v.backgroundBlur.opacity, 0.7)
        };
        n.grain = {
            enabled: (n.grain ?? {}).enabled === true,
            amount: Math.min(1, Math.max(0, Number(v.grain.amount) || 0)),
            size: Math.min(10, Math.max(1, Number(v.grain.size) || 2))
        };
        n.maskFeather = Math.max(0, Number(v.mask.feather) || 0);
        n.maskInverted = v.mask.inverted === true;
    }

    // Structure rebuild (counts, paint types, positions, inner flags,
    // enabled toggles); values stay target-owned. Returns leaf count.
    function pasteDesignProps(p) {
        var targets = propCopy.targetLeaves();
        if (targets.length === 0)
            return 0;
        propCopy.doc.history.checkpoint();
        for (var i = 0; i < targets.length; i++)
            propCopy.applyDesignProps(targets[i].node, p);
        propCopy.doc.touch();
        return targets.length;
    }

    function applyDesignProps(n, p) {
        var f = propCopy.doc.factory;
        var dst = f._copyFills(n.fills, n);
        while (dst.length < p.fills.length)
            dst.push(f.defaultFill());
        dst.length = p.fills.length;
        for (var fi = 0; fi < dst.length; fi++) {
            dst[fi].type = p.fills[fi].type === "linear" ? "linear" : "solid";
            dst[fi].enabled = p.fills[fi].enabled !== false;
        }
        n.fills = dst;
        var ds = f._copyStrokes(n.strokes, n);
        while (ds.length < p.strokes.length)
            ds.push(f.defaultStroke());
        ds.length = p.strokes.length;
        for (var si = 0; si < ds.length; si++) {
            ds[si].type = p.strokes[si].type === "linear" ? "linear" : "solid";
            ds[si].enabled = p.strokes[si].enabled !== false;
            ds[si].position = p.strokes[si].position;
        }
        n.strokes = ds;
        var dh = f._copyShadows(n.shadows);
        while (dh.length < p.shadows.length)
            dh.push(f.defaultShadow(false));
        dh.length = p.shadows.length;
        for (var hi = 0; hi < dh.length; hi++) {
            dh[hi].inner = p.shadows[hi].inner === true;
            dh[hi].enabled = p.shadows[hi].enabled !== false;
        }
        n.shadows = dh;
        var dg = f._copyGlows(n.glows);
        while (dg.length < p.glows.length)
            dg.push(f.defaultGlow(false));
        dg.length = p.glows.length;
        for (var gi = 0; gi < dg.length; gi++) {
            dg[gi].inner = p.glows[gi].inner === true;
            dg[gi].enabled = p.glows[gi].enabled !== false;
        }
        n.glows = dg;
        var lb = f._copyBlur(n.layerBlur, 8, 1);
        lb.enabled = p.layerBlur === true;
        n.layerBlur = lb;
        var bb = f._copyBlur(n.backgroundBlur, 16, 0.7);
        bb.enabled = p.backgroundBlur === true;
        n.backgroundBlur = bb;
        var gr = f._copyGrain(n.grain);
        gr.enabled = p.grain === true;
        n.grain = gr;
    }

    // Wholesale replace (geometry only for direct shape tops).
    // Returns applied leaf count.
    function pasteDesignBoth(payload) {
        var targets = propCopy.targetLeaves();
        if (targets.length === 0)
            return 0;
        propCopy.doc.history.checkpoint();
        for (var i = 0; i < targets.length; i++) {
            var n = targets[i].node;
            if (payload.props)
                propCopy.applyDesignProps(n, payload.props);
            if (payload.values)
                propCopy.applyDesignValues(n, targets[i].geom, payload.values);
        }
        propCopy.doc.touch();
        return targets.length;
    }

    function pasteDesign(mode) {
        var c = TabState.propClipboard;
        if (!c || c.scope !== "design")
            return 0;
        if (mode === "props") {
            if (!c.payload.props)
                return 0;
            return propCopy.pasteDesignProps(c.payload.props);
        }
        if (mode === "both") {
            if (!c.payload.values || !c.payload.props)
                return 0;
            return propCopy.pasteDesignBoth(c.payload);
        }
        if (!c.payload.values)
            return 0;
        return propCopy.pasteDesignValues(c.payload.values);
    }

    function _op(v, fallback) {
        var n = Number(v !== undefined ? v : fallback);
        if (isNaN(n))
            n = fallback === undefined ? 1 : fallback;
        return Math.min(1, Math.max(0, n));
    }

    // ---- animation: same-preset clips across objects ----

    // Stack entry the clip targets (0 = top); masks carry none.
    function entryOf(preset, options) {
        var o = options || {};
        var key = preset === "customColor" || preset === "customGradient" ? "fillIndex" : preset === "customShadow" ? "shadowIndex" : preset === "customGlow" ? "glowIndex" : (preset === "customStroke" || preset === "customStrokeColor" || preset === "customStrokeGradient") ? "strokeIndex" : "";
        if (key === "" || o[key] === undefined)
            return 0;
        var n = Math.round(Number(o[key]));
        return isNaN(n) ? 0 : Math.min(32, Math.max(0, n));
    }

    function matchKey(preset, options) {
        return preset + "|" + propCopy.entryOf(preset, options);
    }

    function snapClip(c) {
        var ez = c.easing || {};
        return {
            preset: c.preset,
            t0: c.t0,
            duration: c.duration,
            mode: c.mode,
            loop: propCopy.doc.anim.presets.normalizeLoop(c.loop),
            options: propCopy.doc.anim.copyMap(c.options),
            easing: {
                id: ez.id,
                bezier: ez.bezier ? ez.bezier.slice() : ez.bezier
            }
        };
    }

    function canCopyAnim(ids) {
        return (ids || []).length > 0;
    }

    function copyAnim(mode, ids) {
        var list = ids || [];
        if (list.length === 0)
            return false;
        var m = mode === "props" ? "props" : mode === "both" ? "both" : "values";
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var c = propCopy.doc.anim.clipById(list[i]);
            if (c)
                out.push(propCopy.snapClip(c));
        }
        if (out.length === 0)
            return false;
        TabState.propClipboard = {
            scope: "anim",
            mode: m,
            payload: {
                clips: out
            }
        };
        return true;
    }

    function canPasteAnim(targetUids) {
        var c = TabState.propClipboard;
        if (!c || c.scope !== "anim")
            return false;
        return (targetUids || []).length > 0;
    }

    // Values overwrite option values (keys ride along); shell
    // (t0/duration/mode/easing/loop/entry) stays target-owned.
    // Missing same-preset clips are created at the playhead.
    // Returns applied clip count.
    function pasteAnim(mode, targetUids) {
        var c = TabState.propClipboard;
        if (!c || c.scope !== "anim")
            return 0;
        var targets = [];
        var asked = targetUids || [];
        for (var i = 0; i < asked.length; i++) {
            if (propCopy.doc.findNode(asked[i]))
                targets.push(asked[i]);
        }
        if (targets.length === 0)
            return 0;
        var m = mode === "props" ? "props" : mode === "both" ? "both" : "values";
        var comp = Math.max(0.5, propCopy.doc.anim.duration);
        var base = Math.min(propCopy.doc.anim.currentTime, Math.max(0, comp - 0.1));
        propCopy.doc.history.checkpoint();
        var made = 0;
        var list = propCopy.doc.anim.clips.slice();
        for (var t = 0; t < targets.length; t++) {
            var existing = [];
            for (var e = 0; e < list.length; e++) {
                if (list[e].targetUid === targets[t])
                    existing.push(list[e]);
            }
            var src = c.payload.clips;
            for (var s = 0; s < src.length; s++) {
                var tmpl = src[s];
                var at = -1;
                for (var k = 0; k < list.length; k++) {
                    if (list[k].targetUid === targets[t] && propCopy.matchKey(list[k].preset, list[k].options) === propCopy.matchKey(tmpl.preset, tmpl.options)) {
                        at = k;
                        break;
                    }
                }
                var P = propCopy.doc.anim.presets;
                if (at >= 0) {
                    var old = list[at];
                    var fixed;
                    if (m === "values") {
                        var opts = propCopy.doc.anim.copyMap(tmpl.options);
                        propCopy.carryEntry(old.preset, old.options, opts);
                        fixed = P.buildClip(old.preset, old.id, old.targetUid, old.t0, old.duration, old.mode, opts, old.easing, old.loop);
                    } else if (m === "props") {
                        fixed = P.buildClip(old.preset, old.id, old.targetUid, tmpl.t0, tmpl.duration, tmpl.mode, old.options, tmpl.easing, tmpl.loop);
                        propCopy.carryEntry(tmpl.preset, tmpl.options, fixed.options);
                    } else {
                        fixed = P.buildClip(tmpl.preset, old.id, old.targetUid, tmpl.t0, tmpl.duration, tmpl.mode, propCopy.doc.anim.copyMap(tmpl.options), tmpl.easing, tmpl.loop);
                    }
                    list[at] = fixed;
                    made++;
                } else {
                    var nt0 = m === "both" ? Math.min(tmpl.t0, Math.max(0, comp - 0.1)) : base;
                    var node = propCopy.doc.findNode(targets[t]);
                    var tops = node ? [node] : [];
                    var fresh;
                    if (m === "props") {
                        var ei = propCopy.entryOf(tmpl.preset, tmpl.options);
                        var seed = propCopy.doc.anim.customDefaults.seededOptions(P, propCopy.doc, tops, tmpl.preset, ei);
                        fresh = P.buildClip(tmpl.preset, propCopy.doc.anim.nextClipId++, targets[t], nt0, tmpl.duration, tmpl.mode, seed, tmpl.easing, tmpl.loop);
                        propCopy.carryEntry(tmpl.preset, tmpl.options, fresh.options);
                        fresh = P.buildClip(tmpl.preset, fresh.id, targets[t], nt0, tmpl.duration, tmpl.mode, fresh.options, tmpl.easing, tmpl.loop);
                    } else {
                        fresh = P.buildClip(tmpl.preset, propCopy.doc.anim.nextClipId++, targets[t], nt0, tmpl.duration, tmpl.mode, propCopy.doc.anim.copyMap(tmpl.options), tmpl.easing, tmpl.loop);
                    }
                    list.push(fresh);
                    made++;
                }
            }
        }
        propCopy.doc.anim.clips = list;
        propCopy.doc.touch();
        return made;
    }

    // Carries the stack-entry index key (fill/stroke/shadow/glow) from
    // one option set onto another so values land on the right entry.
    // Missing source reads entry 0, so a stray target key is dropped.
    function carryEntry(preset, from, onto) {
        var key = preset === "customColor" || preset === "customGradient" ? "fillIndex" : preset === "customShadow" ? "shadowIndex" : preset === "customGlow" ? "glowIndex" : (preset === "customStroke" || preset === "customStrokeColor" || preset === "customStrokeGradient") ? "strokeIndex" : "";
        if (key === "")
            return;
        if (from && from[key] !== undefined)
            onto[key] = propCopy.doc.anim.presets.normalizeEntryIndex(from[key]);
        else if (onto)
            delete onto[key];
    }
}
