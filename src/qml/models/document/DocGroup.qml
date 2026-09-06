import QtQuick

// Group and ungroup. Operates on the owning Document via `doc`.
QtObject {
    id: docGroup
    required property var doc

    function canGroup() {
        return doc.selectedTops().length >= 2;
    }

    function canUngroup() {
        var tops = doc.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            if (tops[i].kind === "group")
                return true;
        }
        return false;
    }

    function groupSelected() {
        var tops = doc.selectedTops();
        if (tops.length < 2)
            return -1;
        var parents = {};
        var firstHit = null;
        var sameParent = true;
        var firstParent = -2;
        // Preserve display order (top-first).
        var ordered = [];
        var walk = list => {
            for (var i = 0; i < list.length; i++) {
                for (var k = 0; k < tops.length; k++) {
                    if (list[i].uid === tops[k].uid)
                        ordered.push(list[i]);
                }
                if (list[i].kind === "group")
                    walk(list[i].children);
            }
        };
        walk(doc.rootChildren);
        for (var i = 0; i < ordered.length; i++) {
            var hit = doc._find(ordered[i].uid);
            if (!hit)
                continue;
            if (!firstHit)
                firstHit = hit;
            if (firstParent === -2)
                firstParent = hit.parentUid;
            else if (hit.parentUid !== firstParent)
                sameParent = false;
            var key = String(hit.parentUid);
            if (!parents[key])
                parents[key] = [];
            parents[key].push(hit);
        }
        if (!firstHit)
            return -1;
        // Detach from old parents (descending per parent).
        for (var key in parents) {
            var hits = parents[key];
            hits.sort((a, b) => b.index - a.index);
            var list = doc._childrenOf(hits[0].parentUid).slice();
            for (var j = 0; j < hits.length; j++)
                list.splice(hits[j].index, 1);
            doc._setChildren(hits[0].parentUid, list);
        }
        var group = doc._makeGroupNode("", ordered);
        group.selected = true;
        // Clear selection on moved children (group owns it now).
        var clear = n => {
            n.selected = false;
            if (n.kind === "group") {
                for (var i = 0; i < n.children.length; i++)
                    clear(n.children[i]);
            }
        };
        for (var m = 0; m < ordered.length; m++)
            clear(ordered[m]);
        group.selected = true;
        if (sameParent) {
            var dest = doc._childrenOf(firstParent).slice();
            dest.splice(Math.min(firstHit.index, dest.length), 0, group);
            doc._setChildren(firstParent, dest);
        } else {
            var container = doc._activeContainerUid();
            var top = doc._childrenOf(container).slice();
            top.unshift(group);
            doc._setChildren(container, top);
        }
        doc.anchorUid = group.uid;
        doc._refreshStructural();
        return group.uid;
    }

    function ungroupNode(uid) {
        var hit = doc._find(uid);
        if (!hit || hit.node.kind !== "group")
            return false;
        var kids = hit.node.children.slice();
        for (var i = 0; i < kids.length; i++)
            kids[i].selected = true;
        var list = doc._childrenOf(hit.parentUid).slice();
        list.splice(hit.index, 1);
        for (var j = 0; j < kids.length; j++)
            list.splice(hit.index + j, 0, kids[j]);
        hit.node.children = [];
        hit.node.destroy();
        doc._setChildren(hit.parentUid, list);
        doc.anchorUid = kids.length > 0 ? kids[0].uid : -1;
        doc._refreshStructural();
        return true;
    }

    function ungroupSelected() {
        var tops = doc.selectedTops();
        var groups = [];
        for (var i = 0; i < tops.length; i++) {
            if (tops[i].kind === "group")
                groups.push(tops[i].uid);
        }
        if (groups.length === 0)
            return;
        doc.clearSelection();
        // Ungroup deepest-first so indices stay valid (sort by depth desc).
        var scored = [];
        for (var j = 0; j < groups.length; j++) {
            var hit = doc._find(groups[j]);
            if (hit)
                scored.push({
                    uid: groups[j],
                    depth: hit.ancestors.length,
                    index: hit.index
                });
        }
        scored.sort((a, b) => (b.depth - a.depth) || (b.index - a.index));
        for (var k = 0; k < scored.length; k++) {
            var h = doc._find(scored[k].uid);
            if (!h)
                continue;
            var kids = h.node.children.slice();
            for (var m = 0; m < kids.length; m++)
                kids[m].selected = true;
            var list = doc._childrenOf(h.parentUid).slice();
            // Re-locate index (earlier ungroups may have shifted it).
            var at = -1;
            for (var n = 0; n < list.length; n++) {
                if (list[n].uid === h.node.uid) {
                    at = n;
                    break;
                }
            }
            if (at < 0)
                continue;
            list.splice(at, 1);
            for (var p = 0; p < kids.length; p++)
                list.splice(at + p, 0, kids[p]);
            h.node.children = [];
            h.node.destroy();
            doc._setChildren(h.parentUid, list);
        }
        var cur = doc.selectedTops();
        doc.anchorUid = cur.length > 0 ? cur[0].uid : -1;
        doc._refreshStructural();
    }
}
