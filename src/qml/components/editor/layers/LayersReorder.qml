import QtQuick

// Drag-reorder for the layers list. Arms on plain press, lifts past 6px,
// marks the drop gap, drops on release. Same-parent gaps only; reparent
// via Group/Ungroup. Reads row geometry via `rows`, owns no visuals.
QtObject {
    id: reorder

    required property var view
    required property var rows

    function dragPress(uid, y, mods) {
        view.dragArming = false;
        view.forceActiveFocus();
        if (!view.doc)
            return;
        if (!!(mods & (Qt.ShiftModifier | Qt.ControlModifier | Qt.MetaModifier)))
            return;
        var hit = view.doc._find(uid);
        if (!hit || hit.node.renaming)
            return;
        view.dragArming = true;
        view.dragUid = uid;
        view.dragParentUid = hit.parentUid;
        view.dragPressY = y;
        view.dropValid = false;
    }

    function dragMove(y) {
        if (!view.dragArming || !view.doc)
            return;
        if (!view.dragging) {
            if (Math.abs(y - view.dragPressY) < 6)
                return;
            if (!view.doc.isSelected(view.dragUid))
                view.doc.selectOnly(view.dragUid);
            view.dragging = true;
        }
        view.dragLiftY = y - view.dragPressY;
        updateDrop(y);
        pushLift();
    }

    function dragRelease() {
        if (!view.dragArming)
            return;
        view.dragArming = false;
        if (!view.dragging)
            return;
        view.dragging = false;
        var target = view.doc ? view.doc.dropTargetForGap(view.dropIndex) : null;
        var from = -1;
        if (view.doc) {
            var hit = view.doc._find(view.dragUid);
            if (hit && hit.parentUid === view.dragParentUid)
                from = hit.index;
        }
        if (view.dropValid && target && from >= 0 && target.index !== from && target.index !== from + 1)
            view.doc.moveWithinParent(target.parentUid, from, target.index);
        clearLift();
        view.suppressClick = true;
        view.dragUid = -1;
        view.dragParentUid = -2;
        view.dropIndex = -1;
        view.dropValid = false;
    }

    function updateDrop(y) {
        var list = view.doc ? view.doc.visibleRowList() : [];
        var n = list.length;
        var idx = n, iy = 0;
        for (var i = 0; i < n; i++) {
            var it = rows.itemAt(i);
            if (!it)
                continue;
            if (y < it.y + it.height / 2) {
                idx = i;
                iy = it.y;
                break;
            }
            iy = it.y + it.height;
        }
        view.dropIndex = idx;
        view.dropY = iy;
        if (view.doc) {
            var target = view.doc.dropTargetForGap(idx);
            view.dropValid = target.parentUid === view.dragParentUid;
        } else {
            view.dropValid = false;
        }
    }

    function pushLift() {
        var list = view.doc ? view.doc.visibleRowList() : [];
        if (!view.doc)
            return;
        var from = -1;
        for (var i = 0; i < list.length; i++) {
            if (list[i].node.uid === view.dragUid) {
                from = i;
                break;
            }
        }
        var drop = view.dropIndex;
        var valid = view.dropValid;
        for (var j = 0; j < list.length; j++) {
            var it = rows.itemAt(j);
            if (!it)
                continue;
            if (j === from) {
                it.dragLift = view.dragLiftY;
                continue;
            }
            var shift = 0;
            if (valid && from >= 0 && drop >= 0) {
                if (drop <= from && j >= drop && j < from)
                    shift = it.height;
                else if (drop > from + 1 && j > from && j < drop)
                    shift = -it.height;
            }
            it.dragLift = shift;
        }
    }

    function clearLift() {
        var list = view.doc ? view.doc.visibleRowList() : [];
        for (var i = 0; i < list.length; i++) {
            var it = rows.itemAt(i);
            if (it)
                it.dragLift = 0;
        }
    }
}
