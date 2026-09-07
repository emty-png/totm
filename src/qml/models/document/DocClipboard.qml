import QtQuick

// Snapshots, copy paste, duplicate and delete. Pastes land visible and unlocked. Operates on the owning Document via `doc`.
QtObject {
    id: clipboard
    required property var doc

    function snapshotNode(node) {
        if (node.kind === "group") {
            var kids = [];
            for (var i = 0; i < node.children.length; i++)
                kids.push(snapshotNode(node.children[i]));
            return {
                kind: "group",
                uid: node.uid,
                name: node.name,
                visible: node.visible,
                locked: node.locked,
                expanded: node.expanded,
                children: kids,
                selected: node.selected
            };
        }
        return {
            kind: "shape",
            uid: node.uid,
            type: node.shapeType,
            name: node.name,
            x: node.x,
            y: node.y,
            w: node.w,
            h: node.h,
            rotation: node.rotation,
            fill: String(node.fill),
            stroke: String(node.stroke),
            strokeWidth: node.strokeWidth,
            opacity: node.opacity,
            radius: node.radius,
            points: node.points,
            flipH: node.flipH,
            flipV: node.flipV,
            visible: node.visible,
            locked: node.locked,
            selected: node.selected
        };
    }

    // reuseUid preserves snapshot uids (full-scene restore/undo).
    // Clipboard ops (paste/duplicate) leave it false so copies get
    // fresh uids and never collide with their sources. Old scenes
    // without uids also fall back to fresh uids.
    function _instantiateSnapshot(snap, select, reuseUid) {
        if (snap.kind === "group") {
            var kids = [];
            for (var i = 0; i < (snap.children || []).length; i++)
                kids.push(_instantiateSnapshot(snap.children[i], select, reuseUid));
            var g = doc._makeGroupNode(snap.name, kids);
            if (reuseUid && typeof snap.uid === "number" && snap.uid >= 0) {
                g.uid = snap.uid;
                if (doc.nextNodeUid <= snap.uid)
                    doc.nextNodeUid = snap.uid + 1;
            }
            g.visible = snap.visible !== false;
            g.locked = snap.locked === true;
            g.expanded = snap.expanded !== false;
            g.selected = !!select;
            return g;
        }
        var n = doc._makeShapeNode(snap.type || "rectangle", snap);
        if (reuseUid && typeof snap.uid === "number" && snap.uid >= 0) {
            n.uid = snap.uid;
            if (doc.nextNodeUid <= snap.uid)
                doc.nextNodeUid = snap.uid + 1;
        }
        n.selected = !!select;
        n.visible = snap.visible !== false;
        n.locked = snap.locked === true;
        return n;
    }

    function copySelected() {
        var tops = doc.selectedTops();
        var out = [];
        // Top-first display order: walk root DFS and pick selected tops.
        var ordered = [];
        var walk = list => {
            for (var i = 0; i < list.length; i++) {
                var n = list[i];
                var isTop = false;
                for (var k = 0; k < tops.length; k++) {
                    if (tops[k].uid === n.uid) {
                        isTop = true;
                        break;
                    }
                }
                if (isTop)
                    ordered.push(n);
                if (n.kind === "group")
                    walk(n.children);
            }
        };
        walk(doc.rootChildren);
        for (var j = 0; j < ordered.length; j++)
            out.push(snapshotNode(ordered[j]));
        return out;
    }

    function insertCopies(items) {
        if (!items || items.length === 0)
            return;
        doc.clearSelection();
        var container = doc._activeContainerUid();
        var list = doc._childrenOf(container).slice();
        for (var k = items.length - 1; k >= 0; k--) {
            var n = _instantiateSnapshot(items[k], true);
            n.visible = true;
            n.locked = false;
            var fix = nd => {
                if (nd.kind === "group") {
                    nd.visible = true;
                    nd.locked = false;
                    for (var i = 0; i < nd.children.length; i++)
                        fix(nd.children[i]);
                } else {
                    nd.visible = true;
                    nd.locked = false;
                }
            };
            fix(n);
            list.unshift(n);
        }
        doc._setChildren(container, list);
        var tops = doc.selectedTops();
        doc.anchorUid = tops.length > 0 ? tops[0].uid : -1;
        doc._refreshStructural();
    }

    function duplicateSelected() {
        // Locked tops are left alone; only the unlocked subset copies.
        var tops = [];
        var every = doc.selectedTops();
        for (var i = 0; i < every.length; i++) {
            if (!doc.isEffectivelyLocked(every[i]))
                tops.push(every[i]);
        }
        if (tops.length === 0)
            return;
        // Group tops by parent so each copy lands right after its source.
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
        doc.clearSelection();
        for (var key in byParent) {
            var hits = byParent[key];
            var parentUid = hits[0].parentUid;
            // Descending index so splices don't shift pending positions.
            hits.sort((a, b) => b.index - a.index);
            var list = doc._childrenOf(parentUid).slice();
            // Account for earlier inserts in this parent.
            var offset = 0;
            hits.sort((a, b) => a.index - b.index);
            for (var j = 0; j < hits.length; j++) {
                var snap = snapshotNode(hits[j].node);
                var copy = _instantiateSnapshot(snap, true);
                list.splice(hits[j].index + 1 + offset, 0, copy);
                offset++;
            }
            doc._setChildren(parentUid, list);
        }
        var cur = doc.selectedTops();
        doc.anchorUid = cur.length > 0 ? cur[0].uid : -1;
        doc._refreshStructural();
    }

    function deleteSelected() {
        // Locked tops survive deletion like every other edit skips them.
        var tops = [];
        var every = doc.selectedTops();
        for (var i = 0; i < every.length; i++) {
            if (!doc.isEffectivelyLocked(every[i]))
                tops.push(every[i]);
        }
        if (tops.length === 0)
            return;
        var ids = {};
        for (var i = 0; i < tops.length; i++)
            ids[tops[i].uid] = true;
        var prune = list => {
            var out = [];
            for (var j = 0; j < list.length; j++) {
                if (ids[list[j].uid]) {
                    list[j].destroy();
                    continue;
                }
                if (list[j].kind === "group")
                    list[j].children = prune(list[j].children);
                out.push(list[j]);
            }
            return out;
        };
        doc.rootChildren = prune(doc.rootChildren);
        // Drill path may point into deleted groups: truncate dead tail.
        doc.pruneDrillPath();
        doc.anchorUid = -1;
        doc._refreshStructural();
    }

    // Whole-scene snapshot for the on-disk library. Plain data only, so
    // the C++ store can persist it untouched and previews can read it.
    function snapshotScene() {
        var nodes = [];
        for (var i = 0; i < doc.rootChildren.length; i++)
            nodes.push(snapshotNode(doc.rootChildren[i]));
        return {
            version: 1,
            sceneWidth: doc.sceneWidth,
            sceneHeight: doc.sceneHeight,
            sceneColor: String(doc.sceneColor),
            nodes: nodes
        };
    }

    // Replace the whole tree with a stored scene. Old nodes are
    // destroyed, drill and selection reset, nothing stays selected.
    function restoreScene(scene) {
        var s = scene || {};
        var old = doc.rootChildren.slice();
        for (var i = 0; i < old.length; i++)
            old[i].destroy();
        doc.rootChildren = [];
        doc.drillPath = [];
        doc.anchorUid = -1;
        if (s.sceneWidth > 0)
            doc.sceneWidth = s.sceneWidth;
        if (s.sceneHeight > 0)
            doc.sceneHeight = s.sceneHeight;
        if (s.sceneColor !== undefined)
            doc.sceneColor = s.sceneColor;
        var nodes = s.nodes || [];
        var list = [];
        for (var j = 0; j < nodes.length; j++)
            list.push(_instantiateSnapshot(nodes[j], false, true));
        doc.rootChildren = list;
        doc._refreshStructural();
    }
}
