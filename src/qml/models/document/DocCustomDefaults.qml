import QtQuick

// Seeded from-to defaults for custom clips. Seeds read live nodes so
// new clips start at the current look (no jump on first frame) and
// fall back to the shared preset defaults when the selection has no
// readable value. Pure over explicit args: no document is stored.
QtObject {
    id: defaults

    function seededOptions(presets, d, tops, presetId) {
        var first = tops.length > 0 ? tops[0] : null;
        var leaf = first ? defaults.firstLeaf(d, first) : null;
        if (presetId === "customOpacity" && leaf) {
            var op = Math.min(1, Math.max(0, Number(leaf.opacity) || 0));
            return {
                from: Math.round(op * 100) / 100,
                to: op > 0.5 ? 0 : 1
            };
        }
        if (presetId === "customColor" && leaf) {
            var fill = String(leaf.fill || "#000000");
            return {
                from: fill,
                to: "#ff0000"
            };
        }
        if (presetId === "customGradient" && leaf) {
            var fg = leaf.fillGradient ?? {};
            var fstops = fg.stops ?? [];
            var fc1 = fstops.length > 0 ? String(fstops[0].color) : String(leaf.fill || "#000000");
            var fc2 = fstops.length > 1 ? String(fstops[1].color) : "#ffffff";
            var fang = Number(fg.angle);
            if (isNaN(fang))
                fang = 90;
            return {
                fromC1: fc1,
                toC1: fc1,
                fromC2: fc2,
                toC2: "#ff0000",
                fromAngle: Math.round(fang * 100) / 100,
                toAngle: Math.round(fang * 100) / 100
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
            var sw = Math.max(0, Number(leaf.strokeWidth) || 0);
            return {
                from: Math.round(sw * 100) / 100,
                to: sw === 0 ? 4 : 0
            };
        }
        return presets.defaultsFor(presetId);
    }

    function firstLeaf(d, top) {
        if (!top)
            return null;
        if (top.kind === "shape")
            return top;
        var leaves = d._leavesUnder(top);
        return leaves.length > 0 ? leaves[0] : null;
    }
}
