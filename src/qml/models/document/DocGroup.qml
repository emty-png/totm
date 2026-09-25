import QtQuick

// Group/ungroup over selected tops. Locked nodes are excluded;
// same-parent groups insert at the source index. Operates on the owner
// via `doc`.
QtObject {
    id: docGroup
    required property var doc

    function canGroup() {
        var n = 0;
        var tops = doc.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            if (!doc.isEffectivelyLocked(tops[i]))
                n++;
        }
        return n >= 2;
    }

    function canUngroup() {
        var tops = doc.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            if (tops[i].kind === "group" && !doc.isEffectivelyLocked(tops[i]))
                return true;
        }
        return false;
    }

    // Mask use (Figma/Jitter-style). Requires 2+ unlocked selected
    // tops; the bottommost (last in top-first order) becomes the mask.
    // Different parents auto-group first, mirroring Jitter Cmd+Ctrl+M.
    function canUseAsMask() {
        var tops = doc.selectedTops();
        var n = 0;
        for (var i = 0; i < tops.length; i++) {
            if (!doc.isEffectivelyLocked(tops[i]))
                n++;
        }
        return n >= 2;
    }

    function _bottommostUid(tops) {
        // Top-first display order: walk the tree and pick the last hit.
        var ids = {};
        for (var i = 0; i < tops.length; i++)
            ids[tops[i].uid] = true;
        var last = -1;
        var walk = list => {
            for (var j = 0; j < list.length; j++) {
                if (ids[list[j].uid])
                    last = list[j].uid;
                if (list[j].kind === "group")
                    walk(list[j].children);
            }
        };
        walk(doc.rootChildren);
        return last;
    }

    function useAsMask() {
        var every = doc.selectedTops();
        var tops = [];
        for (var i = 0; i < every.length; i++) {
            if (!doc.isEffectivelyLocked(every[i]))
                tops.push(every[i]);
        }
        if (tops.length < 2)
            return -1;
        doc.history.checkpoint();
        // Different parents: group first so the mask has one boundary.
        var firstParent = -2;
        var sameParent = true;
        for (var k = 0; k < tops.length; k++) {
            var hit = doc._find(tops[k].uid);
            if (!hit)
                continue;
            if (firstParent === -2)
                firstParent = hit.parentUid;
            else if (hit.parentUid !== firstParent)
                sameParent = false;
        }
        var maskUid = _bottommostUid(tops);
        if (!sameParent) {
            var gid = groupSelectedInner();
            if (gid < 0)
                return -1;
            // After grouping, bottommost of the new group is the mask.
            var g = doc.findNode(gid);
            if (!g || g.kind !== "group" || g.children.length < 2)
                return -1;
            maskUid = g.children[g.children.length - 1].uid;
        }
        var maskNode = doc.findNode(maskUid);
        if (!maskNode || doc.isEffectivelyLocked(maskNode))
            return -1;
        // Only shapes can be masks; groups stay content.
        var leaves = doc._leavesUnder(maskNode);
        var target = maskNode.kind === "shape" ? maskNode : (leaves.length > 0 ? leaves[leaves.length - 1] : null);
        if (!target)
            return -1;
        target.isMask = true;
        target.maskFeather = Math.max(0, Number(target.maskFeather) || 0);
        target.maskInverted = target.maskInverted === true;
        // Ensure the mask sits below all other selected siblings in
        // its parent so it clips them (top-first: larger index).
        var mHit = doc._find(target.uid);
        if (mHit) {
            var list = doc._childrenOf(mHit.parentUid).slice();
            var at = -1;
            for (var m = 0; m < list.length; m++) {
                if (list[m].uid === target.uid) {
                    at = m;
                    break;
                }
            }
            if (at >= 0 && at !== list.length - 1) {
                var item = list.splice(at, 1)[0];
                // Place after the lowest other selected sibling, or at
                // the very bottom when nothing else constrains it.
                var lowestSel = -1;
                for (var s = 0; s < list.length; s++) {
                    for (var t = 0; t < tops.length; t++) {
                        if (list[s].uid === tops[t].uid && tops[t].uid !== target.uid)
                            lowestSel = Math.max(lowestSel, s);
                    }
                }
                var dest = lowestSel >= 0 ? lowestSel + 1 : list.length;
                list.splice(Math.min(dest, list.length), 0, item);
                doc._setChildren(mHit.parentUid, list);
            }
        }
        doc.clearSelectionSilent();
        if (target)
            target.selected = true;
        doc.anchorUid = target ? target.uid : -1;
        doc._refreshStructural();
        return target ? target.uid : -1;
    }

    // Inner grouping without an extra checkpoint (useAsMask owns it).
    function groupSelectedInner() {
        var tops = [];
        var every = doc.selectedTops();
        for (var i = 0; i < every.length; i++) {
            if (!doc.isEffectivelyLocked(every[i]))
                tops.push(every[i]);
        }
        if (tops.length < 2)
            return -1;
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
        var parents = {};
        var firstHit = null;
        var firstParent = -2;
        for (var i = 0; i < ordered.length; i++) {
            var hit = doc._find(ordered[i].uid);
            if (!hit)
                continue;
            if (!firstHit)
                firstHit = hit;
            if (firstParent === -2)
                firstParent = hit.parentUid;
            var key = String(hit.parentUid);
            if (!parents[key])
                parents[key] = [];
            parents[key].push(hit);
        }
        if (!firstHit)
            return -1;
        for (var key in parents) {
            var hits = parents[key];
            hits.sort((a, b) => b.index - a.index);
            var list = doc._childrenOf(hits[0].parentUid).slice();
            for (var j = 0; j < hits.length; j++)
                list.splice(hits[j].index, 1);
            doc._setChildren(hits[0].parentUid, list);
        }
        var group = doc._makeGroupNode("", ordered);
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
        var container = doc._activeContainerUid();
        var top = doc._childrenOf(container).slice();
        top.unshift(group);
        doc._setChildren(container, top);
        doc.anchorUid = group.uid;
        doc._refreshStructural();
        return group.uid;
    }

    function canReleaseMask() {
        var tops = doc.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            if (tops[i].kind === "shape" && tops[i].isMask === true && !doc.isEffectivelyLocked(tops[i]))
                return true;
            if (tops[i].kind === "group") {
                var kids = tops[i].children || [];
                for (var k = 0; k < kids.length; k++) {
                    if (kids[k].kind === "shape" && kids[k].isMask === true && !doc.isEffectivelyLocked(kids[k]))
                        return true;
                }
            }
        }
        return false;
    }

    function releaseMask() {
        var tops = doc.selectedTops();
        var touched = false;
        doc.history.checkpoint();
        for (var i = 0; i < tops.length; i++) {
            var n = tops[i];
            if (n.kind === "shape" && n.isMask === true && !doc.isEffectivelyLocked(n)) {
                n.isMask = false;
                touched = true;
            } else if (n.kind === "group" && !doc.isEffectivelyLocked(n)) {
                var kids = n.children || [];
                for (var k = 0; k < kids.length; k++) {
                    if (kids[k].kind === "shape" && kids[k].isMask === true && !doc.isEffectivelyLocked(kids[k])) {
                        kids[k].isMask = false;
                        touched = true;
                    }
                }
            }
        }
        if (touched)
            doc._refreshStructural();
    }

    function groupSelected() {
        // Locked tops stay out of the new group.
        var tops = [];
        var every = doc.selectedTops();
        for (var i = 0; i < every.length; i++) {
            if (!doc.isEffectivelyLocked(every[i]))
                tops.push(every[i]);
        }
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
        if (!hit || hit.node.kind !== "group" || doc.isEffectivelyLocked(hit.node))
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
        doc.pruneDrillPath();
        return true;
    }

    function ungroupSelected() {
        var tops = doc.selectedTops();
        var groups = [];
        for (var i = 0; i < tops.length; i++) {
            if (tops[i].kind === "group" && !doc.isEffectivelyLocked(tops[i]))
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
        doc.pruneDrillPath();
    }
}
