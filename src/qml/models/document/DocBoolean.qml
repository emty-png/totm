import QtQuick

// Live boolean groups over shapes, text, images and nested booleans.
// A boolean group keeps its children editable (drill-in) and paints
// one combined silhouette with the group's own style (see ShapePath),
// live-editable in Fill/Stroke/Appearance/Effects after combine.
// Plain groups stay untouched: boolOp "none" never paints. Operates
// on the owner via `doc`.
QtObject {
    id: docBoolean
    required property var doc

    function isOp(op) {
        var o = String(op ?? "").toLowerCase();
        return o === "union" || o === "subtract" || o === "intersect" || o === "exclude";
    }

    function isBooleanGroup(node) {
        return !!node && node.kind === "group" && node.boolOp !== undefined && node.boolOp !== "none";
    }

    function isCombinableShape(node) {
        if (!node || doc.isEffectivelyLocked(node))
            return false;
        // Boolean groups nest as operands (their silhouette feeds the
        // outer fold); hidden subtrees contribute nothing, so they stay
        // out with the same rule as hidden leaves below.
        if (node.kind === "group")
            return isBooleanGroup(node) && doc.isEffectivelyVisible(node);
        if (node.kind !== "shape")
            return false;
        if (node.isMask === true)
            return false;
        if (!doc.isEffectivelyVisible(node))
            return false;
        var t = node.shapeType;
        if (t !== "rectangle" && t !== "ellipse" && t !== "triangle" && t !== "star" && t !== "pen" && t !== "text" && t !== "image")
            return false;
        if (!(node.w > 0.01) || !(node.h > 0.01))
            return false;
        // Empty text contributes no glyphs; over-long runs exceed the
        // combine cap (see kMaxCombineGlyphs) and stay out as well.
        if (t === "text") {
            var len = String(node.textContent ?? "").length;
            return len > 0 && len <= 256;
        }
        if (t === "pen") {
            var subs = node.pathData || [];
            for (var i = 0; i < subs.length; i++) {
                if (((subs[i] || {}).pts || []).length > 0)
                    return true;
            }
            return false;
        }
        return true;
    }

    function canCombine() {
        var n = 0;
        var tops = doc.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            if (isCombinableShape(tops[i]))
                n++;
            else
                return false;
        }
        return n >= 2;
    }

    function canReleaseBoolean() {
        var tops = doc.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            if (isBooleanGroup(tops[i]) && !doc.isEffectivelyLocked(tops[i]))
                return true;
        }
        return false;
    }

    // Bottommost in top-first display order donates the group style,
    // mirroring the mask-source rule in DocGroup.
    function _bottommost(tops) {
        var ids = {};
        for (var i = 0; i < tops.length; i++)
            ids[tops[i].uid] = true;
        var last = null;
        var walk = list => {
            for (var j = 0; j < list.length; j++) {
                if (ids[list[j].uid])
                    last = list[j];
                if (list[j].kind === "group")
                    walk(list[j].children);
            }
        };
        walk(doc.rootChildren);
        return last;
    }

    function _applyStyleFrom(group, source) {
        group.fills = doc.factory._copyFills(source.fills, source);
        group.strokes = doc.factory._copyStrokes(source.strokes, source);
        group.shadows = doc.factory._copyShadows(source.shadows);
        group.glows = doc.factory._copyGlows(source.glows);
        group.layerBlur = doc.factory._copyBlur(source.layerBlur, 8, 1);
        group.backgroundBlur = doc.factory._copyBlur(source.backgroundBlur, 16, 0.7);
        group.grain = doc.factory._copyGrain(source.grain);
        group.opacity = source.opacity ?? 1;
        group.radius = source.radius ?? 0;
        group.independentCorners = source.independentCorners === true;
        group.cornerRadii = doc.factory._copyRadii(source.cornerRadii);
        group.penFill = source.penFill !== false;
        group.strokeCap = source.strokeCap ?? "round";
        group.strokeJoin = source.strokeJoin ?? "round";
        // Preserve shader: boolean groups are shaderable, so combining
        // shaded shapes keeps the donor look instead of dropping it.
        group.shaderId = String(source.shaderId ?? "");
        group.shaderMode = (source.shaderMode === "overlay") ? "overlay" : "fill";
        group.shaderParams = doc.factory._copyShaderParams(source.shaderParams);
    }

    function combineSelected(op) {
        var norm = String(op ?? "union").toLowerCase();
        if (!isOp(norm) || !canCombine())
            return -1;
        doc.history.checkpoint();
        var tops = [];
        var every = doc.selectedTops();
        for (var i = 0; i < every.length; i++) {
            if (isCombinableShape(every[i]))
                tops.push(every[i]);
        }
        if (tops.length < 2)
            return -1;
        var donor = _bottommost(tops);
        // Different parents: group first so the boolean has one boundary
        // (same rule as useAsMask), then convert that group.
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
        var group = null;
        if (!sameParent) {
            var gid = doc.grouper.groupSelectedInner();
            if (gid < 0)
                return -1;
            group = doc.findNode(gid);
            if (!group)
                return -1;
        } else {
            // Preserve display order (top-first) like groupSelected.
            var ordered = [];
            var walk = list => {
                for (var i = 0; i < list.length; i++) {
                    for (var q = 0; q < tops.length; q++) {
                        if (list[i].uid === tops[q].uid)
                            ordered.push(list[i]);
                    }
                    if (list[i].kind === "group")
                        walk(list[i].children);
                }
            };
            walk(doc.rootChildren);
            var fHit = doc._find(ordered[0].uid);
            if (!fHit)
                return -1;
            var parentUid = fHit.parentUid;
            // Detach ordered children from the parent.
            var list = doc._childrenOf(parentUid).slice();
            var at = list.length;
            for (var m = 0; m < ordered.length; m++) {
                for (var n = 0; n < list.length; n++) {
                    if (list[n].uid === ordered[m].uid) {
                        if (n < at)
                            at = n;
                        list.splice(n, 1);
                        break;
                    }
                }
            }
            doc._setChildren(parentUid, list);
            group = doc._makeGroupNode("", ordered);
            var clear = n2 => {
                n2.selected = false;
                if (n2.kind === "group") {
                    for (var c = 0; c < n2.children.length; c++)
                        clear(n2.children[c]);
                }
            };
            for (var c2 = 0; c2 < ordered.length; c2++)
                clear(ordered[c2]);
            var dest = doc._childrenOf(parentUid).slice();
            dest.splice(Math.min(at, dest.length), 0, group);
            doc._setChildren(parentUid, dest);
        }
        group.boolOp = norm;
        // Bottommost donor seeds the style (shape or boolean-group
        // stacks alike); live edits land on the group afterwards.
        if (donor && (donor.kind === "shape" || isBooleanGroup(donor)))
            _applyStyleFrom(group, donor);
        doc.clearSelectionSilent();
        group.selected = true;
        doc.anchorUid = group.uid;
        doc._refreshStructural();
        return group.uid;
    }

    function setBoolOp(uid, op) {
        var norm = String(op ?? "").toLowerCase();
        if (!isOp(norm))
            return false;
        var n = doc.findNode(uid);
        if (!n || n.kind !== "group" || doc.isEffectivelyLocked(n))
            return false;
        if (n.boolOp === norm)
            return true;
        doc.history.checkpoint();
        n.boolOp = norm;
        doc._refreshStructural();
        return true;
    }

    function releaseSelected() {
        var tops = doc.selectedTops();
        var targets = [];
        for (var i = 0; i < tops.length; i++) {
            if (isBooleanGroup(tops[i]) && !doc.isEffectivelyLocked(tops[i]))
                targets.push(tops[i].uid);
        }
        if (targets.length === 0)
            return;
        doc.history.checkpoint();
        // Deepest-first so indices stay valid (same rule as ungroup).
        var scored = [];
        for (var j = 0; j < targets.length; j++) {
            var hit = doc._find(targets[j]);
            if (hit)
                scored.push({
                    uid: targets[j],
                    depth: hit.ancestors.length,
                    index: hit.index
                });
        }
        scored.sort((a, b) => (b.depth - a.depth) || (b.index - a.index));
        doc.clearSelection();
        for (var k = 0; k < scored.length; k++) {
            var h = doc._find(scored[k].uid);
            if (!h || h.node.kind !== "group")
                continue;
            h.node.boolOp = "none";
            var kids = h.node.children.slice();
            for (var m = 0; m < kids.length; m++)
                kids[m].selected = true;
            var list = doc._childrenOf(h.parentUid).slice();
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
