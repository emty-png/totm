import QtQuick

// Seeded from-to defaults for custom clips. Seeds read live nodes so
// new clips start at the current look (no jump on first frame) and
// fall back to the shared preset defaults when the selection has no
// readable value. Pure over explicit args: no document is stored.
QtObject {
    id: defaults

    function seededOptions(presets, d, tops, presetId, entryIndex) {
        var first = tops.length > 0 ? tops[0] : null;
        var leaf = first ? defaults.firstLeaf(d, first) : null;
        var ei = Math.min(32, Math.max(0, Math.round(Number(entryIndex) || 0)));
        if (presetId === "customOpacity" && leaf) {
            var op = Math.min(1, Math.max(0, Number(leaf.opacity) || 0));
            return {
                from: Math.round(op * 100) / 100,
                to: op > 0.5 ? 0 : 1
            };
        }
        if (presetId === "customColor" && leaf) {
            var fills0 = defaults.stackEntry(leaf, "fills", ei);
            var fill = String(fills0.color ?? leaf.fill ?? "#000000");
            var fop = fills0.opacity !== undefined ? Math.min(1, Math.max(0, Number(fills0.opacity))) : 1;
            if (isNaN(fop))
                fop = 1;
            return {
                from: fill,
                to: "#ff0000",
                fromOpacity: Math.round(fop * 100) / 100,
                toOpacity: Math.round(fop * 100) / 100,
                fillIndex: ei
            };
        }
        if (presetId === "customGradient" && leaf) {
            var f0 = defaults.stackEntry(leaf, "fills", ei);
            var fg = f0.gradient ?? leaf.fillGradient ?? {};
            var fstops = fg.stops ?? [];
            var fc1 = fstops.length > 0 ? String(fstops[0].color) : String(f0.color ?? leaf.fill ?? "#000000");
            var fc2 = fstops.length > 1 ? String(fstops[1].color) : "#ffffff";
            var fang = Number(fg.angle);
            if (isNaN(fang))
                fang = 90;
            var fgop = f0.opacity !== undefined ? Math.min(1, Math.max(0, Number(f0.opacity))) : 1;
            if (isNaN(fgop))
                fgop = 1;
            return {
                fromC1: fc1,
                toC1: fc1,
                fromC2: fc2,
                toC2: "#ff0000",
                fromAngle: Math.round(fang * 100) / 100,
                toAngle: Math.round(fang * 100) / 100,
                fromOpacity: Math.round(fgop * 100) / 100,
                toOpacity: Math.round(fgop * 100) / 100,
                fillIndex: ei
            };
        }
        if (presetId === "customShadow" && leaf) {
            var sh = (leaf.shadows && leaf.shadows.length > 0 ? leaf.shadows[0] : {}) ?? {};
            var fx = Number(sh.x) || 0;
            var fy = sh.y !== undefined ? (Number(sh.y) || 0) : 4;
            var fb = sh.blur !== undefined ? Math.max(0, Number(sh.blur) || 0) : 8;
            var fs = sh.spread !== undefined ? Math.max(0, Number(sh.spread) || 0) : 0;
            return {
                fromColor: String(sh.color || "#80000000"),
                toColor: String(sh.color || "#80000000"),
                fromX: Math.round(fx * 100) / 100,
                toX: Math.round(fx * 100) / 100,
                fromY: Math.round(fy * 100) / 100,
                toY: Math.round(Math.min(500, fy + 8) * 100) / 100,
                fromBlur: Math.round(fb * 100) / 100,
                toBlur: Math.round(Math.min(100, fb + 8) * 100) / 100,
                fromSpread: Math.round(fs * 100) / 100,
                toSpread: Math.round(fs * 100) / 100,
                fromInner: sh.inner === true,
                toInner: sh.inner === true
            };
        }
        if (presetId === "customLayerBlur" && leaf) {
            var lb = leaf.layerBlur ?? {};
            var lr = lb.radius !== undefined ? Math.max(0, Number(lb.radius) || 0) : 8;
            var lo = lb.opacity !== undefined ? Math.min(1, Math.max(0, Number(lb.opacity))) : 1;
            return {
                fromRadius: Math.round(lr * 100) / 100,
                toRadius: Math.round(Math.min(100, lr + 8) * 100) / 100,
                fromOpacity: Math.round(lo * 100) / 100,
                toOpacity: Math.round(lo * 100) / 100
            };
        }
        if (presetId === "customBackgroundBlur" && leaf) {
            var bb = leaf.backgroundBlur ?? {};
            var br = bb.radius !== undefined ? Math.max(0, Number(bb.radius) || 0) : 16;
            var bo = bb.opacity !== undefined ? Math.min(1, Math.max(0, Number(bb.opacity))) : 0.7;
            return {
                fromRadius: Math.round(br * 100) / 100,
                toRadius: Math.round(Math.min(100, br + 8) * 100) / 100,
                fromOpacity: Math.round(bo * 100) / 100,
                toOpacity: Math.round(bo * 100) / 100
            };
        }
        if (presetId === "customGlow" && leaf) {
            var gl = (leaf.glows && leaf.glows.length > 0 ? leaf.glows[0] : {}) ?? {};
            var gb = gl.blur !== undefined ? Math.max(0, Number(gl.blur) || 0) : 16;
            var gs = gl.spread !== undefined ? Math.max(0, Number(gl.spread) || 0) : 4;
            return {
                fromColor: String(gl.color || "#cc00ffff"),
                toColor: String(gl.color || "#cc00ffff"),
                fromBlur: Math.round(gb * 100) / 100,
                toBlur: Math.round(Math.min(100, gb + 12) * 100) / 100,
                fromSpread: Math.round(gs * 100) / 100,
                toSpread: Math.round(gs * 100) / 100,
                fromInner: gl.inner === true,
                toInner: gl.inner === true
            };
        }
        if (presetId === "customGrain" && leaf) {
            var gn = leaf.grain ?? {};
            var ga = gn.amount !== undefined ? Math.min(1, Math.max(0, Number(gn.amount))) : 0.5;
            var gz = gn.size !== undefined ? Math.min(10, Math.max(1, Number(gn.size) || 0)) : 2;
            return {
                fromAmount: Math.round(ga * 100) / 100,
                toAmount: ga > 0 ? 0 : 0.5,
                fromSize: Math.round(gz * 100) / 100,
                toSize: Math.round(gz * 100) / 100
            };
        }
        if (presetId === "customResize" && leaf) {
            var fw = Math.max(1, Math.round(Number(leaf.w) || 100));
            var fh = Math.max(1, Math.round(Number(leaf.h) || 100));
            return {
                fromW: fw,
                fromH: fh,
                toW: Math.min(4000, Math.round(fw * 1.5)),
                toH: Math.min(4000, Math.round(fh * 1.5))
            };
        }
        if (presetId === "customCorner" && leaf) {
            var cr = Math.max(0, Number(leaf.radius) || 0);
            return {
                from: Math.round(cr * 100) / 100,
                to: cr === 0 ? 24 : 0
            };
        }
        if (presetId === "customStroke" && leaf) {
            var s0 = defaults.stackEntry(leaf, "strokes", ei);
            var sw = Math.max(0, Number(s0.width ?? leaf.strokeWidth) || 0);
            var sop = s0.opacity !== undefined ? Math.min(1, Math.max(0, Number(s0.opacity))) : 1;
            if (isNaN(sop))
                sop = 1;
            var sd = (s0.dash && typeof s0.dash.length === "number") ? s0.dash : [];
            var sdash = sd.length > 0 ? Math.max(0, Number(sd[0]) || 0) : 0;
            var sgap = sd.length > 1 ? Math.max(0, Number(sd[1]) || 0) : 0;
            var spos = (s0.position === "inside" || s0.position === "outside") ? s0.position : "center";
            return {
                from: Math.round(sw * 100) / 100,
                to: sw === 0 ? 4 : 0,
                fromOpacity: Math.round(sop * 100) / 100,
                toOpacity: Math.round(sop * 100) / 100,
                fromDash: Math.round(sdash * 100) / 100,
                toDash: Math.round(sdash * 100) / 100,
                fromGap: Math.round(sgap * 100) / 100,
                toGap: Math.round(sgap * 100) / 100,
                fromPosition: spos,
                toPosition: spos,
                strokeIndex: ei
            };
        }
        if (presetId === "customStrokeColor" && leaf) {
            var s1 = defaults.stackEntry(leaf, "strokes", ei);
            var sc = String(s1.color ?? leaf.stroke ?? "#000000");
            var scop = s1.opacity !== undefined ? Math.min(1, Math.max(0, Number(s1.opacity))) : 1;
            if (isNaN(scop))
                scop = 1;
            return {
                from: sc,
                to: "#ff0000",
                fromOpacity: Math.round(scop * 100) / 100,
                toOpacity: Math.round(scop * 100) / 100,
                strokeIndex: ei
            };
        }
        if (presetId === "customStrokeGradient" && leaf) {
            var sg0 = defaults.stackEntry(leaf, "strokes", ei);
            var sgg = sg0.gradient ?? {};
            var sgstops = sgg.stops ?? [];
            var sgc1 = sgstops.length > 0 ? String(sgstops[0].color) : String(sg0.color ?? "#000000");
            var sgc2 = sgstops.length > 1 ? String(sgstops[1].color) : "#ffffff";
            var sgang = Number(sgg.angle);
            if (isNaN(sgang))
                sgang = 90;
            var sgop = sg0.opacity !== undefined ? Math.min(1, Math.max(0, Number(sg0.opacity))) : 1;
            if (isNaN(sgop))
                sgop = 1;
            return {
                fromC1: sgc1,
                toC1: sgc1,
                fromC2: sgc2,
                toC2: "#ff0000",
                fromAngle: Math.round(sgang * 100) / 100,
                toAngle: Math.round(sgang * 100) / 100,
                fromOpacity: Math.round(sgop * 100) / 100,
                toOpacity: Math.round(sgop * 100) / 100,
                strokeIndex: ei
            };
        }
        if (presetId === "customFontSize" && leaf) {
            var fs = Math.min(500, Math.max(1, Math.round(Number(leaf.fontSize) || 16)));
            return {
                from: fs,
                to: Math.min(500, fs * 2)
            };
        }
        return presets.defaultsFor(presetId);
    }

    // One stack entry (fills/strokes) by index, {} when the leaf is
    // short. Seeding and reseeds read through here so clips can target
    // any entry, not just the top one.
    function stackEntry(leaf, kind, index) {
        var ei = Math.min(32, Math.max(0, Math.round(Number(index) || 0)));
        var list = (leaf && leaf[kind]) || [];
        if (ei < list.length)
            return list[ei] ?? {};
        return {};
    }

    // From-side-only reseed when the user retargets a style clip onto
    // another entry: From tracks the live entry (no jump at clip
    // start), To stays user-edited. Carries the index key itself.
    function fromPatchForEntry(presets, d, tops, presetId, index) {
        var ei = Math.min(32, Math.max(0, Math.round(Number(index) || 0)));
        var full = defaults.seededOptions(presets, d, tops, presetId, ei);
        var patch = {};
        var keys = ["from", "fromOpacity", "fromC1", "fromC2", "fromAngle", "fromDash", "fromGap", "fromPosition"];
        for (var i = 0; i < keys.length; i++) {
            if (full[keys[i]] !== undefined)
                patch[keys[i]] = full[keys[i]];
        }
        if (presetId === "customColor" || presetId === "customGradient")
            patch.fillIndex = ei;
        else
            patch.strokeIndex = ei;
        return patch;
    }

    function firstLeaf(d, top) {
        if (!top)
            return null;
        if (top.kind === "shape")
            return top;
        var leaves = d._leavesUnder(top);
        return leaves.length > 0 ? leaves[0] : null;
    }

    // Top stack entry paint type for gallery routing: color rows
    // auto-upgrade to their gradient sibling when the target's top
    // entry is linear, so a gradient stroke never lands in a solid
    // hex editor. Missing entries read as solid.
    function topFillType(d, tops) {
        var leaf = tops.length > 0 ? firstLeaf(d, tops[0]) : null;
        var f0 = (leaf && leaf.fills && leaf.fills.length > 0 ? leaf.fills[0] : {}) ?? {};
        return f0.type === "linear" ? "linear" : "solid";
    }

    function topStrokeType(d, tops) {
        var leaf = tops.length > 0 ? firstLeaf(d, tops[0]) : null;
        var s0 = (leaf && leaf.strokes && leaf.strokes.length > 0 ? leaf.strokes[0] : {}) ?? {};
        return s0.type === "linear" ? "linear" : "solid";
    }
}
