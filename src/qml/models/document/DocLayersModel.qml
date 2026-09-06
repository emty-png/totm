import QtQuick

// Layers-list model, paint order and drop gaps. Operates on the owning Document via `doc`.
QtObject {
    id: docLayersModel
    required property var doc

    function renumberZ() {
        var leaves = doc.allLeaves();
        var n = leaves.length;
        for (var i = 0; i < n; i++)
            leaves[i].zOrder = n - i;
    }

    function totalCount() {
        doc.rev;
        return doc._allNodes().length;
    }

    function visibleRows() {
        doc.rev;
        var out = [];
        var walk = (list, level) => {
            for (var i = 0; i < list.length; i++) {
                out.push({
                    node: list[i],
                    level: level
                });
                if (list[i].kind === "group" && list[i].expanded)
                    walk(list[i].children, level + 1);
            }
        };
        walk(doc.rootChildren, 0);
        return out;
    }

    function visibleRowList() {
        doc.structRev;
        var out = [];
        var walk = (list, level) => {
            for (var i = 0; i < list.length; i++) {
                out.push({
                    node: list[i],
                    level: level
                });
                if (list[i].kind === "group" && list[i].expanded)
                    walk(list[i].children, level + 1);
            }
        };
        walk(doc.rootChildren, 0);
        return out;
    }

    function dropTargetForGap(gap) {
        var rows = visibleRowList();
        var n = rows.length;
        if (gap <= 0)
            return {
                parentUid: -1,
                index: 0
            };
        if (gap >= n) {
            if (n === 0)
                return {
                    parentUid: -1,
                    index: 0
                };
            var lastHit = doc._find(rows[n - 1].node.uid);
            if (!lastHit)
                return {
                    parentUid: -1,
                    index: 0
                };
            return {
                parentUid: lastHit.parentUid,
                index: doc._childrenOf(lastHit.parentUid).length
            };
        }
        var above = rows[gap - 1], below = rows[gap];
        if (below.level === above.level + 1)
            return {
                parentUid: above.node.uid,
                index: 0
            };
        var hit = doc._find(below.node.uid);
        if (!hit)
            return {
                parentUid: -1,
                index: 0
            };
        return {
            parentUid: hit.parentUid,
            index: hit.index
        };
    }
}
