import QtQuick

// Selection, range select, visibility and lock flags, marquee apply. Operates on the owning Document via `doc`.
QtObject {
    id: docSelection
    required property var doc

    function isSelected(uid) {
        var n = doc.findNode(uid);
        return !!n && n.selected;
    }

    function clearSelection() {
        var all = doc._allNodes();
        for (var i = 0; i < all.length; i++)
            all[i].selected = false;
        doc.anchorUid = -1;
        doc.touch();
    }

    function clearSelectionSilent() {
        var all = doc._allNodes();
        for (var i = 0; i < all.length; i++)
            all[i].selected = false;
        doc.anchorUid = -1;
    }

    function selectOnly(uid) {
        var all = doc._allNodes();
        for (var i = 0; i < all.length; i++)
            all[i].selected = all[i].uid === uid;
        doc.anchorUid = uid;
        doc.touch();
    }

    function addToSelection(uid) {
        var n = doc.findNode(uid);
        if (n)
            n.selected = true;
        doc.anchorUid = uid;
        doc.touch();
    }

    function toggleSelect(uid) {
        var n = doc.findNode(uid);
        if (n)
            n.selected = !n.selected;
        doc.anchorUid = uid;
        doc.touch();
    }

    function selectRange(uid) {
        var rows = doc.visibleRows();
        var a = -1, b = -1;
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].node.uid === doc.anchorUid)
                a = i;
            if (rows[i].node.uid === uid)
                b = i;
        }
        if (a < 0 || b < 0) {
            selectOnly(uid);
            return;
        }
        var lo = Math.min(a, b), hi = Math.max(a, b);
        for (var j = 0; j < rows.length; j++)
            rows[j].node.selected = j >= lo && j <= hi;
        doc.touch();
    }

    function addRange(uid) {
        var rows = doc.visibleRows();
        var a = -1, b = -1;
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].node.uid === doc.anchorUid)
                a = i;
            if (rows[i].node.uid === uid)
                b = i;
        }
        if (a < 0 || b < 0) {
            addToSelection(uid);
            return;
        }
        var lo = Math.min(a, b), hi = Math.max(a, b);
        for (var j = 0; j < rows.length; j++) {
            if (j >= lo && j <= hi)
                rows[j].node.selected = true;
        }
        doc.touch();
    }

    function toggleVisible(uid) {
        var n = doc.findNode(uid);
        if (n)
            n.visible = !n.visible;
        doc.touch();
    }

    function toggleLocked(uid) {
        var n = doc.findNode(uid);
        if (n)
            n.locked = !n.locked;
        doc.touch();
    }

    function toggleExpanded(uid) {
        var n = doc.findNode(uid);
        if (n && n.kind === "group") {
            n.expanded = !n.expanded;
            doc.structRev++;
        }
        doc.touch();
    }

    function selectInRect(rx, ry, rw, rh, additive) {
        var active = doc._activeContainerUid();
        if (!additive)
            clearSelectionSilent();
        var leaves = doc.allLeaves();
        for (var j = 0; j < leaves.length; j++) {
            var s = leaves[j];
            if (!doc.isEffectivelyVisible(s) || doc.isEffectivelyLocked(s))
                continue;
            if (active >= 0 && !doc._isDescendantOf(s.uid, active))
                continue;
            var b = doc.rotatedBounds(s);
            var touches = !(b.x > rx + rw || b.x + b.w < rx || b.y > ry + rh || b.y + b.h < ry);
            if (touches) {
                var target = doc.resolvePress(s.uid);
                var t = doc.findNode(target);
                if (t)
                    t.selected = true;
            }
        }
        doc.touch();
    }
}
