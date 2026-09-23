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
        var seed = defaults._seedFor(presetId);
        if (seed && leaf)
            return seed(leaf, ei);
        return presets.defaultsFor(presetId);
    }

    function _seedFor(presetId) {
        var table = {
            "customOpacity": defaults._seedOpacity,
            "customColor": defaults._seedColor,
            "customGradient": defaults._seedGradient,
            "customShadow": defaults._seedShadow,
            "customLayerBlur": defaults._seedLayerBlur,
            "customBackgroundBlur": defaults._seedBackgroundBlur,
            "customGlow": defaults._seedGlow,
            "customGrain": defaults._seedGrain,
            "customResize": defaults._seedResize,
            "customCorner": defaults._seedCorner,
            "customStroke": defaults._seedStroke,
            "customStrokeColor": defaults._seedStrokeColor,
            "customStrokeGradient": defaults._seedStrokeGradient,
            "customFontSize": defaults._seedFontSize
        };
        return table[presetId];
    }

    function _round2(v) {
        return Math.round(v * 100) / 100;
    }

    function _opacity(v) {
        if (v === undefined)
            return 1;
        var n = Math.min(1, Math.max(0, Number(v)));
        return isNaN(n) ? 1 : n;
    }

    function _dashOf(entry) {
        var raw = (entry.dash && typeof entry.dash.length === "number") ? entry.dash : [];
        return {
            dash: raw.length > 0 ? Math.max(0, Number(raw[0]) || 0) : 0,
            gap: raw.length > 1 ? Math.max(0, Number(raw[1]) || 0) : 0
        };
    }

    function _positionOf(entry) {
        return (entry.position === "inside" || entry.position === "outside") ? entry.position : "center";
    }

    function _stopsOf(entry, fallbackColor) {
        var grad = entry.gradient ?? {};
        var stops = grad.stops ?? [];
        var angle = Number(grad.angle);
        return {
            c1: stops.length > 0 ? String(stops[0].color) : String(fallbackColor),
            c2: stops.length > 1 ? String(stops[1].color) : "#ffffff",
            angle: isNaN(angle) ? 90 : angle
        };
    }

    function _seedOpacity(leaf, ei) {
        var op = Math.min(1, Math.max(0, Number(leaf.opacity) || 0));
        return {
            from: defaults._round2(op),
            to: op > 0.5 ? 0 : 1
        };
    }

    function _seedColor(leaf, ei) {
        var entry = defaults.stackEntry(leaf, "fills", ei);
        var fop = defaults._opacity(entry.opacity);
        return {
            from: String(entry.color ?? leaf.fill ?? "#000000"),
            to: "#ff0000",
            fromOpacity: defaults._round2(fop),
            toOpacity: defaults._round2(fop),
            fillIndex: ei
        };
    }

    function _seedGradient(leaf, ei) {
        var entry = defaults.stackEntry(leaf, "fills", ei);
        var stops = defaults._stopsOf(entry, entry.color ?? leaf.fill ?? "#000000");
        var fop = defaults._opacity(entry.opacity);
        return {
            fromC1: stops.c1,
            toC1: stops.c1,
            fromC2: stops.c2,
            toC2: "#ff0000",
            fromAngle: defaults._round2(stops.angle),
            toAngle: defaults._round2(stops.angle),
            fromOpacity: defaults._round2(fop),
            toOpacity: defaults._round2(fop),
            fillIndex: ei
        };
    }

    function _seedShadow(leaf, ei) {
        var entry = defaults.stackEntry(leaf, "shadows", ei);
        var fx = Number(entry.x) || 0;
        var fy = entry.y !== undefined ? (Number(entry.y) || 0) : 4;
        var fb = entry.blur !== undefined ? Math.max(0, Number(entry.blur) || 0) : 8;
        var fs = entry.spread !== undefined ? Math.max(0, Number(entry.spread) || 0) : 0;
        return {
            fromColor: String(entry.color || "#80000000"),
            toColor: String(entry.color || "#80000000"),
            fromX: defaults._round2(fx),
            toX: defaults._round2(fx),
            fromY: defaults._round2(fy),
            toY: defaults._round2(Math.min(500, fy + 8)),
            fromBlur: defaults._round2(fb),
            toBlur: defaults._round2(Math.min(100, fb + 8)),
            fromSpread: defaults._round2(fs),
            toSpread: defaults._round2(fs),
            fromInner: entry.inner === true,
            toInner: entry.inner === true,
            shadowIndex: ei
        };
    }

    function _seedLayerBlur(leaf, ei) {
        var lb = leaf.layerBlur ?? {};
        var lr = lb.radius !== undefined ? Math.max(0, Number(lb.radius) || 0) : 8;
        var lo = lb.opacity !== undefined ? Math.min(1, Math.max(0, Number(lb.opacity))) : 1;
        return {
            fromRadius: defaults._round2(lr),
            toRadius: defaults._round2(Math.min(100, lr + 8)),
            fromOpacity: defaults._round2(lo),
            toOpacity: defaults._round2(lo)
        };
    }

    function _seedBackgroundBlur(leaf, ei) {
        var bb = leaf.backgroundBlur ?? {};
        var br = bb.radius !== undefined ? Math.max(0, Number(bb.radius) || 0) : 16;
        var bo = bb.opacity !== undefined ? Math.min(1, Math.max(0, Number(bb.opacity))) : 0.7;
        return {
            fromRadius: defaults._round2(br),
            toRadius: defaults._round2(Math.min(100, br + 8)),
            fromOpacity: defaults._round2(bo),
            toOpacity: defaults._round2(bo)
        };
    }

    function _seedGlow(leaf, ei) {
        var entry = defaults.stackEntry(leaf, "glows", ei);
        var gb = entry.blur !== undefined ? Math.max(0, Number(entry.blur) || 0) : 16;
        var gs = entry.spread !== undefined ? Math.max(0, Number(entry.spread) || 0) : 4;
        return {
            fromColor: String(entry.color || "#cc00ffff"),
            toColor: String(entry.color || "#cc00ffff"),
            fromBlur: defaults._round2(gb),
            toBlur: defaults._round2(Math.min(100, gb + 12)),
            fromSpread: defaults._round2(gs),
            toSpread: defaults._round2(gs),
            fromInner: entry.inner === true,
            toInner: entry.inner === true,
            glowIndex: ei
        };
    }

    function _seedGrain(leaf, ei) {
        var gn = leaf.grain ?? {};
        var ga = gn.amount !== undefined ? Math.min(1, Math.max(0, Number(gn.amount))) : 0.5;
        var gz = gn.size !== undefined ? Math.min(10, Math.max(1, Number(gn.size) || 0)) : 2;
        return {
            fromAmount: defaults._round2(ga),
            toAmount: ga > 0 ? 0 : 0.5,
            fromSize: defaults._round2(gz),
            toSize: defaults._round2(gz)
        };
    }

    function _seedResize(leaf, ei) {
        var fw = Math.max(1, Math.round(Number(leaf.w) || 100));
        var fh = Math.max(1, Math.round(Number(leaf.h) || 100));
        return {
            fromW: fw,
            fromH: fh,
            toW: Math.min(4000, Math.round(fw * 1.5)),
            toH: Math.min(4000, Math.round(fh * 1.5))
        };
    }

    function _seedCorner(leaf, ei) {
        var cr = Math.max(0, Number(leaf.radius) || 0);
        return {
            from: defaults._round2(cr),
            to: cr === 0 ? 24 : 0
        };
    }

    function _seedStroke(leaf, ei) {
        var entry = defaults.stackEntry(leaf, "strokes", ei);
        var sw = Math.max(0, Number(entry.width ?? leaf.strokeWidth) || 0);
        var sop = defaults._opacity(entry.opacity);
        var dash = defaults._dashOf(entry);
        var spos = defaults._positionOf(entry);
        return {
            from: defaults._round2(sw),
            to: sw === 0 ? 4 : 0,
            fromOpacity: defaults._round2(sop),
            toOpacity: defaults._round2(sop),
            fromDash: defaults._round2(dash.dash),
            toDash: defaults._round2(dash.dash),
            fromGap: defaults._round2(dash.gap),
            toGap: defaults._round2(dash.gap),
            fromPosition: spos,
            toPosition: spos,
            strokeIndex: ei
        };
    }

    function _seedStrokeColor(leaf, ei) {
        var entry = defaults.stackEntry(leaf, "strokes", ei);
        var sop = defaults._opacity(entry.opacity);
        return {
            from: String(entry.color ?? leaf.stroke ?? "#000000"),
            to: "#ff0000",
            fromOpacity: defaults._round2(sop),
            toOpacity: defaults._round2(sop),
            strokeIndex: ei
        };
    }

    function _seedStrokeGradient(leaf, ei) {
        var entry = defaults.stackEntry(leaf, "strokes", ei);
        var stops = defaults._stopsOf(entry, entry.color ?? "#000000");
        var sop = defaults._opacity(entry.opacity);
        var sw = Math.max(0, Number(entry.width) || 0);
        var dash = defaults._dashOf(entry);
        var spos = defaults._positionOf(entry);
        return {
            fromC1: stops.c1,
            toC1: stops.c1,
            fromC2: stops.c2,
            toC2: "#ff0000",
            fromAngle: defaults._round2(stops.angle),
            toAngle: defaults._round2(stops.angle),
            fromOpacity: defaults._round2(sop),
            toOpacity: defaults._round2(sop),
            from: defaults._round2(sw),
            to: defaults._round2(sw),
            fromDash: defaults._round2(dash.dash),
            toDash: defaults._round2(dash.dash),
            fromGap: defaults._round2(dash.gap),
            toGap: defaults._round2(dash.gap),
            fromPosition: spos,
            toPosition: spos,
            strokeIndex: ei
        };
    }

    function _seedFontSize(leaf, ei) {
        var fs = Math.min(500, Math.max(1, Math.round(Number(leaf.fontSize) || 16)));
        return {
            from: fs,
            to: Math.min(500, fs * 2)
        };
    }

    // One stack entry (fills/strokes/shadows/glows) by index, {} when
    // the leaf is short. Seeding and reseeds read through here so clips
    // can target any entry, not just the top one.
    function stackEntry(leaf, kind, index) {
        var ei = Math.min(32, Math.max(0, Math.round(Number(index) || 0)));
        var list = (leaf && leaf[kind]) || [];
        if (ei < list.length)
            return list[ei] ?? {};
        return {};
    }

    // From-side-only reseed when the user retargets a style or effect
    // clip onto another entry: From tracks the live entry (no jump at
    // clip start), To stays user-edited. Carries the index key itself.
    function fromPatchForEntry(presets, d, tops, presetId, index) {
        var ei = Math.min(32, Math.max(0, Math.round(Number(index) || 0)));
        var full = defaults.seededOptions(presets, d, tops, presetId, ei);
        var patch = {};
        var keys = ["from", "fromOpacity", "fromC1", "fromC2", "fromAngle", "fromDash", "fromGap", "fromPosition", "fromColor", "fromX", "fromY", "fromBlur", "fromSpread", "fromInner"];
        for (var i = 0; i < keys.length; i++) {
            if (full[keys[i]] !== undefined)
                patch[keys[i]] = full[keys[i]];
        }
        if (presetId === "customColor" || presetId === "customGradient")
            patch.fillIndex = ei;
        else if (presetId === "customShadow")
            patch.shadowIndex = ei;
        else if (presetId === "customGlow")
            patch.glowIndex = ei;
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
