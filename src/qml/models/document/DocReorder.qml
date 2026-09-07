import QtQuick

// Paint-order moves within a parent. Operates on the owning Document via `doc`.
QtObject {
    id: docReorder
    required property var doc

    function _reorderInParent(parentUid, order) {
        // order: new array of child nodes for the parent.
        doc._setChildren(parentUid, order);
        doc._refreshStructural();
    }

    function bringToFront() {
        // Locked tops stay pinned where they are.
        var tops = [];
        var every = doc.selectedTops();
        for (var i = 0; i < every.length; i++) {
            if (!doc.isEffectivelyLocked(every[i]))
                tops.push(every[i]);
        }
        if (tops.length === 0)
            return;
        var byParent = {};
        for (var i = 0; i < tops.length; i++) {
            var hit = doc._find(tops[i].uid);
            if (!hit)
                continue;
            var key = String(hit.parentUid);
            if (!byParent[key])
                byParent[key] = [];
            byParent[key].push(hit.node);
        }
        for (var key in byParent) {
            var parentUid = Number(key);
            var list = doc._childrenOf(parentUid).slice();
            var sel = byParent[key];
            var ids = {};
            for (var a = 0; a < sel.length; a++)
                ids[sel[a].uid] = true;
            var rest = [];
            for (var b = 0; b < list.length; b++) {
                if (!ids[list[b].uid])
                    rest.push(list[b]);
            }
            // Top-most-first: front is index 0. Preserve selection order.
            var selOrdered = [];
            for (var c = 0; c < list.length; c++) {
                if (ids[list[c].uid])
                    selOrdered.push(list[c]);
            }
            doc._setChildren(parentUid, selOrdered.concat(rest));
        }
        doc._refreshStructural();
    }

    function sendToBack() {
        // Locked tops stay pinned where they are.
        var tops = [];
        var every = doc.selectedTops();
        for (var i = 0; i < every.length; i++) {
            if (!doc.isEffectivelyLocked(every[i]))
                tops.push(every[i]);
        }
        if (tops.length === 0)
            return;
        var byParent = {};
        for (var i = 0; i < tops.length; i++) {
            var hit = doc._find(tops[i].uid);
            if (!hit)
                continue;
            var key = String(hit.parentUid);
            if (!byParent[key])
                byParent[key] = [];
            byParent[key].push(hit.node);
        }
        for (var key in byParent) {
            var parentUid = Number(key);
            var list = doc._childrenOf(parentUid).slice();
            var ids = {};
            var sel = byParent[key];
            for (var a = 0; a < sel.length; a++)
                ids[sel[a].uid] = true;
            var rest = [];
            for (var b = 0; b < list.length; b++) {
                if (!ids[list[b].uid])
                    rest.push(list[b]);
            }
            var selOrdered = [];
            for (var c = 0; c < list.length; c++) {
                if (ids[list[c].uid])
                    selOrdered.push(list[c]);
            }
            doc._setChildren(parentUid, rest.concat(selOrdered));
        }
        doc._refreshStructural();
    }

    function moveForward() {
        // Locked tops stay pinned; unlocked ones swap around them.
        var tops = [];
        var every = doc.selectedTops();
        for (var i = 0; i < every.length; i++) {
            if (!doc.isEffectivelyLocked(every[i]))
                tops.push(every[i]);
        }
        if (tops.length === 0)
            return;
        var moved = false;
        var byParent = {};
        for (var i = 0; i < tops.length; i++) {
            var hit = doc._find(tops[i].uid);
            if (!hit)
                continue;
            var key = String(hit.parentUid);
            if (!byParent[key])
                byParent[key] = [];
            byParent[key].push(hit);
        }
        for (var key in byParent) {
            var hits = byParent[key];
            var parentUid = hits[0].parentUid;
            var list = doc._childrenOf(parentUid).slice();
            var selIds = {};
            for (var a = 0; a < hits.length; a++)
                selIds[hits[a].node.uid] = true;
            for (var idx = 1; idx < list.length; idx++) {
                if (selIds[list[idx].uid] && !selIds[list[idx - 1].uid]) {
                    var tmp = list[idx - 1];
                    list[idx - 1] = list[idx];
                    list[idx] = tmp;
                    moved = true;
                }
            }
            doc._setChildren(parentUid, list);
        }
        if (moved)
            doc._refreshStructural();
        else
            doc.touch();
    }

    function moveBackward() {
        // Locked tops stay pinned; unlocked ones swap around them.
        var tops = [];
        var every = doc.selectedTops();
        for (var i = 0; i < every.length; i++) {
            if (!doc.isEffectivelyLocked(every[i]))
                tops.push(every[i]);
        }
        if (tops.length === 0)
            return;
        var moved = false;
        var byParent = {};
        for (var i = 0; i < tops.length; i++) {
            var hit = doc._find(tops[i].uid);
            if (!hit)
                continue;
            var key = String(hit.parentUid);
            if (!byParent[key])
                byParent[key] = [];
            byParent[key].push(hit);
        }
        for (var key in byParent) {
            var hits = byParent[key];
            var parentUid = hits[0].parentUid;
            var list = doc._childrenOf(parentUid).slice();
            var selIds = {};
            for (var a = 0; a < hits.length; a++)
                selIds[hits[a].node.uid] = true;
            for (var idx = list.length - 2; idx >= 0; idx--) {
                if (selIds[list[idx].uid] && !selIds[list[idx + 1].uid]) {
                    var tmp = list[idx + 1];
                    list[idx + 1] = list[idx];
                    list[idx] = tmp;
                    moved = true;
                }
            }
            doc._setChildren(parentUid, list);
        }
        if (moved)
            doc._refreshStructural();
        else
            doc.touch();
    }

    function moveWithinParent(parentUid, from, to) {
        var list = doc._childrenOf(parentUid).slice();
        if (from < 0 || to < 0 || from === to || from >= list.length || to > list.length)
            return;
        // Drag-reorder never moves a locked row.
        if (doc.isEffectivelyLocked(list[from]))
            return;
        var item = list.splice(from, 1)[0];
        var at = to > from ? to - 1 : to;
        // Gap positions straddle rows: dropping right below the dragged
        // row (from+1) is a no-op (handled by callers, kept safe here).
        list.splice(at, 0, item);
        doc._setChildren(parentUid, list);
        doc._refreshStructural();
    }
}
