import QtQuick

// Snapshot of the current selection for the design panel. Re-collected
// on every document mutation; editors bind to `sel` and helpers.
QtObject {
    id: snapshot

    required property var doc

    readonly property var tops: collectTops()
    readonly property bool hasGroup: checkHasGroup()
    readonly property var selLeaves: collectLeaves()
    readonly property var sel: collectSelected()
    readonly property bool allLocked: checkAllLocked()

    function collectTops() {
        if (!snapshot.doc)
            return [];
        snapshot.doc.rev;
        return snapshot.doc.selectedTops();
    }

    function checkHasGroup() {
        for (var i = 0; i < snapshot.tops.length; i++) {
            if (snapshot.tops[i].kind === "group")
                return true;
        }
        return false;
    }

    function collectLeaves() {
        if (!snapshot.doc)
            return [];
        snapshot.doc.rev;
        var tops = snapshot.doc.selectedTops();
        var out = [];
        for (var i = 0; i < tops.length; i++) {
            var leaves = tops[i].kind === "shape" ? [tops[i]] : snapshot.doc._leavesUnder(tops[i]);
            for (var j = 0; j < leaves.length; j++) {
                var s = leaves[j];
                out.push({
                    uid: s.uid,
                    type: s.shapeType,
                    x: s.x,
                    y: s.y,
                    w: s.w,
                    h: s.h,
                    rotation: s.rotation,
                    fill: s.fill,
                    stroke: s.stroke,
                    strokeWidth: s.strokeWidth,
                    opacity: s.opacity,
                    radius: s.radius,
                    locked: snapshot.doc.isEffectivelyLocked(s)
                });
            }
        }
        return out;
    }

    function collectSelected() {
        if (!snapshot.doc)
            return [];
        snapshot.doc.rev;
        if (snapshot.hasGroup) {
            var box = snapshot.doc._selectionBBox();
            if (!box)
                return [];
            return [
                {
                    uid: -1,
                    type: "group",
                    x: box.x,
                    y: box.y,
                    w: box.w,
                    h: box.h,
                    rotation: 0,
                    fill: "#000000",
                    stroke: "#000000",
                    strokeWidth: 0,
                    opacity: 1,
                    radius: 0,
                    locked: checkAllLocked()
                }
            ];
        }
        return snapshot.selLeaves;
    }

    function checkAllLocked() {
        if (snapshot.selLeaves.length === 0)
            return false;
        for (var i = 0; i < snapshot.selLeaves.length; i++) {
            if (!snapshot.selLeaves[i].locked)
                return false;
        }
        return true;
    }

    function commonOf(role) {
        if (snapshot.sel.length === 0)
            return {
                mixed: true,
                value: 0
            };
        var v = snapshot.sel[0][role];
        for (var i = 1; i < snapshot.sel.length; i++) {
            if (snapshot.sel[i][role] !== v)
                return {
                    mixed: true,
                    value: v
                };
        }
        return {
            mixed: false,
            value: v
        };
    }

    function distinctFills() {
        var out = [];
        for (var i = 0; i < snapshot.sel.length; i++) {
            var f = String(snapshot.sel[i].fill);
            if (out.indexOf(f) < 0)
                out.push(f);
        }
        return out;
    }

    function allOfType(type) {
        if (snapshot.sel.length === 0)
            return false;
        for (var i = 0; i < snapshot.sel.length; i++) {
            if (snapshot.sel[i].type !== type)
                return false;
        }
        return true;
    }

    function setAll(role, value) {
        if (snapshot.doc)
            snapshot.doc.setPropSelected(role, value);
    }
}
