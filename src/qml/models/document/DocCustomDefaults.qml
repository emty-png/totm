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
