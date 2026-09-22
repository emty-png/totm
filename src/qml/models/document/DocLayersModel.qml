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

    // Per-frame rows: touches rev so delegates refresh on any doc change.
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

    // Structural rows for the layers Repeater: touches structRev only, so
    // the list rebuilds on structure, never on geometry moves.
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

    // Filtered structural rows for the layers search field. Matches by
    // name or shape type (case-insensitive); groups auto-expand while
    // filtering so hits stay visible. A matching group shows its whole
    // subtree; a hit under a plain group pulls its ancestor chain
    // along so the hierarchy still reads. Blank queries fall back to
    // visibleRowList. Touches rev too so live renames re-filter (rename
    // only bumps rev, never structRev).
    function visibleRowListFiltered(filter) {
        doc.structRev;
        doc.rev;
        var q = (filter || "").trim().toLowerCase();
        if (!q)
            return visibleRowList();
        var out = [];
        var isMatch = node => {
            if ((node.name || "").toLowerCase().indexOf(q) !== -1)
                return true;
            return (node.shapeType || "").toLowerCase().indexOf(q) !== -1;
        };
        var subtreeHasMatch = list => {
            for (var i = 0; i < list.length; i++) {
                if (isMatch(list[i]))
                    return true;
                if (list[i].kind === "group" && subtreeHasMatch(list[i].children))
                    return true;
            }
            return false;
        };
        var pushAll = (list, level) => {
            for (var j = 0; j < list.length; j++) {
                out.push({
                    node: list[j],
                    level: level
                });
                if (list[j].kind === "group")
                    pushAll(list[j].children, level + 1);
            }
        };
        var walk = (list, level) => {
            for (var k = 0; k < list.length; k++) {
                var node = list[k];
                if (isMatch(node)) {
                    out.push({
                        node: node,
                        level: level
                    });
                    if (node.kind === "group")
                        pushAll(node.children, level + 1);
                } else if (node.kind === "group") {
                    if (subtreeHasMatch(node.children)) {
                        out.push({
                            node: node,
                            level: level
                        });
                        walk(node.children, level + 1);
                    }
                }
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
