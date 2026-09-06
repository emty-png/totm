import QtQuick

// Tree navigation for one Document. Finds nodes, walks children and leaves. Operates on the owning Document via `doc`.
QtObject {
    id: docTree
    required property var doc

    function _find(uid, nodes, parent, parentUid, ancestors) {
        if (uid < 0)
            return null;
        var list = nodes ?? doc.rootChildren;
        var anc = ancestors ?? [];
        for (var i = 0; i < list.length; i++) {
            var n = list[i];
            if (n.uid === uid)
                return {
                    node: n,
                    parent: parent ?? null,
                    parentUid: parentUid ?? -1,
                    index: i,
                    ancestors: anc.slice()
                };
            if (n.kind === "group") {
                var nextAnc = anc.concat([n]);
                var hit = _find(uid, n.children, n, n.uid, nextAnc);
                if (hit)
                    return hit;
            }
        }
        return null;
    }

    function findNode(uid) {
        var hit = _find(uid);
        return hit ? hit.node : null;
    }

    function _childrenOf(parentUid) {
        if (parentUid < 0)
            return doc.rootChildren;
        var p = findNode(parentUid);
        return (p && p.kind === "group") ? p.children : [];
    }

    function _setChildren(parentUid, arr) {
        if (parentUid < 0)
            doc.rootChildren = arr;
        else {
            var p = findNode(parentUid);
            if (p && p.kind === "group")
                p.children = arr;
        }
    }

    function _allNodes() {
        var out = [];
        var walk = list => {
            for (var i = 0; i < list.length; i++) {
                out.push(list[i]);
                if (list[i].kind === "group")
                    walk(list[i].children);
            }
        };
        walk(doc.rootChildren);
        return out;
    }

    function _leavesUnder(node) {
        if (!node)
            return [];
        if (node.kind === "shape")
            return [node];
        var out = [];
        for (var i = 0; i < node.children.length; i++)
            out = out.concat(_leavesUnder(node.children[i]));
        return out;
    }

    function allLeaves() {
        var out = [];
        for (var i = 0; i < doc.rootChildren.length; i++)
            out = out.concat(_leavesUnder(doc.rootChildren[i]));
        return out;
    }

    function selectedTops() {
        var tops = [];
        var walk = (list, selAbove) => {
            for (var i = 0; i < list.length; i++) {
                var n = list[i];
                var self = n.selected;
                if (self && !selAbove)
                    tops.push(n);
                if (n.kind === "group")
                    walk(n.children, selAbove || self);
            }
        };
        walk(doc.rootChildren, false);
        return tops;
    }

    function _selectedLeaves() {
        var tops = selectedTops();
        var out = [];
        for (var i = 0; i < tops.length; i++)
            out = out.concat(_leavesUnder(tops[i]));
        return out;
    }

    function _isDirectChildOf(uid, containerUid) {
        var hit = _find(uid);
        return !!hit && hit.parentUid === containerUid;
    }

    function _isDescendantOf(uid, containerUid) {
        if (containerUid < 0)
            return true;
        var hit = _find(uid);
        if (!hit)
            return false;
        var chain = hit.ancestors.concat([hit.node]);
        for (var i = 0; i < chain.length; i++) {
            if (chain[i].uid === containerUid)
                return true;
        }
        return false;
    }
}
