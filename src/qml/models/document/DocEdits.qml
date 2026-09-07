import QtQuick

// Geometry edits for selected leaves. Moves mutate in place, scaling is absolute from press. Operates on the owning Document via `doc`.
QtObject {
    id: edits
    required property var doc

    function moveSelected(dx, dy) {
        var leaves = doc._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (doc.isEffectivelyLocked(leaves[i]))
                continue;
            leaves[i].x += dx;
            leaves[i].y += dy;
        }
        doc.touch();
    }

    function snapSelection() {
        var leaves = doc._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (doc.isEffectivelyLocked(leaves[i]))
                continue;
            leaves[i].x = Math.round(leaves[i].x);
            leaves[i].y = Math.round(leaves[i].y);
            leaves[i].w = Math.max(1, Math.round(leaves[i].w));
            leaves[i].h = Math.max(1, Math.round(leaves[i].h));
        }
        doc.touch();
    }

    function scaleSelection(orig, box0, newBox) {
        if (!box0 || box0.w <= 0 || box0.h <= 0)
            return;
        var sx = newBox.w / box0.w, sy = newBox.h / box0.h;
        for (var k = 0; k < orig.length; k++) {
            var o = orig[k];
            var n = doc.findNode(o.uid);
            if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
                continue;
            var ncx = newBox.x + (o.x + o.w / 2 - box0.x) * sx;
            var ncy = newBox.y + (o.y + o.h / 2 - box0.y) * sy;
            var nw = Math.max(1, o.w * sx);
            var nh = Math.max(1, o.h * sy);
            n.x = ncx - nw / 2;
            n.y = ncy - nh / 2;
            n.w = nw;
            n.h = nh;
        }
        doc.touch();
    }

    function selectedLeafSnapshot() {
        var leaves = doc._selectedLeaves();
        var out = [];
        for (var i = 0; i < leaves.length; i++)
            out.push({
                uid: leaves[i].uid,
                x: leaves[i].x,
                y: leaves[i].y,
                w: leaves[i].w,
                h: leaves[i].h
            });
        return out;
    }

    function setShapeProp(uid, role, value) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return;
        if (role === "w" || role === "h")
            value = Math.max(1, value);
        if (role === "points")
            value = Math.min(12, Math.max(3, Math.round(value)));
        n[role] = value;
        doc.touch();
    }

    function setPropSelected(role, value) {
        var tops = doc.selectedTops();
        var hasGroup = false;
        for (var i = 0; i < tops.length; i++) {
            if (tops[i].kind === "group") {
                hasGroup = true;
                break;
            }
        }
        if (hasGroup && (role === "x" || role === "y" || role === "w" || role === "h")) {
            _setBBoxProp(role, value);
            return;
        }
        var leaves = doc._selectedLeaves();
        for (var j = 0; j < leaves.length; j++) {
            if (doc.isEffectivelyLocked(leaves[j]))
                continue;
            // Groups have no style: skip them (leaves only here anyway).
            if (role === "w" || role === "h")
                value = Math.max(1, value);
            if (role === "points")
                value = Math.min(12, Math.max(3, Math.round(value)));
            if (role in leaves[j])
                leaves[j][role] = value;
        }
        doc.touch();
    }

    function _setBBoxProp(role, value) {
        var box = doc._selectionBBox();
        if (!box)
            return;
        var leaves = doc._selectedLeaves();
        if (leaves.length === 0)
            return;
        if (role === "x") {
            var dx = value - box.x;
            for (var i = 0; i < leaves.length; i++) {
                if (!doc.isEffectivelyLocked(leaves[i]))
                    leaves[i].x += dx;
            }
        } else if (role === "y") {
            var dy = value - box.y;
            for (var j = 0; j < leaves.length; j++) {
                if (!doc.isEffectivelyLocked(leaves[j]))
                    leaves[j].y += dy;
            }
        } else if (role === "w" || role === "h") {
            var nw = Math.max(1, value);
            var newBox = {
                x: box.x,
                y: box.y,
                w: box.w,
                h: box.h
            };
            if (role === "w")
                newBox.w = nw;
            else
                newBox.h = nw;
            var orig = [];
            for (var k = 0; k < leaves.length; k++)
                orig.push({
                    uid: leaves[k].uid,
                    x: leaves[k].x,
                    y: leaves[k].y,
                    w: leaves[k].w,
                    h: leaves[k].h
                });
            scaleSelection(orig, box, newBox);
            return;
        }
        doc.touch();
    }

    // Recolor one fill variant within the selection only. A global
    // replace-all would repaint same-colored shapes the user never
    // selected, so this stays scoped like every other panel edit.
    function recolorSelected(oldFill, newFill) {
        var leaves = doc._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (String(leaves[i].fill) === String(oldFill) && !doc.isEffectivelyLocked(leaves[i]))
                leaves[i].fill = newFill;
        }
        doc.touch();
    }

    // Quarter turn clockwise per leaf, normalized to [0, 360).
    function rotateSelected90() {
        var leaves = doc._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (doc.isEffectivelyLocked(leaves[i]))
                continue;
            leaves[i].rotation = (((leaves[i].rotation + 90) % 360) + 360) % 360;
        }
        doc.touch();
    }

    function flipSelectedH() {
        var leaves = doc._selectedLeaves();
        for (var j = 0; j < leaves.length; j++) {
            if (doc.isEffectivelyLocked(leaves[j]))
                continue;
            leaves[j].flipH = !leaves[j].flipH;
        }
        doc.touch();
    }

    function flipSelectedV() {
        var leaves = doc._selectedLeaves();
        for (var k = 0; k < leaves.length; k++) {
            if (doc.isEffectivelyLocked(leaves[k]))
                continue;
            leaves[k].flipV = !leaves[k].flipV;
        }
        doc.touch();
    }
}
