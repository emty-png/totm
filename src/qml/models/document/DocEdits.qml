import QtQuick

// Geometry edits for selected leaves. Moves mutate in place, scaling is absolute from press. Operates on the owning Document via `doc`.
QtObject {
    id: edits
    required property var doc

    function shiftPath(node, dx, dy) {
        var src = node.pathData || [];
        var out = [];
        for (var i = 0; i < src.length; i++) {
            var sub = src[i] || {};
            var pts = [];
            var arr = sub.pts || [];
            for (var j = 0; j < arr.length; j++) {
                var p = arr[j] || {};
                pts.push({
                    x: (Number(p.x) || 0) + dx,
                    y: (Number(p.y) || 0) + dy,
                    smooth: p.smooth === true,
                    inX: (p.inX !== undefined ? Number(p.inX) : (Number(p.x) || 0)) + dx,
                    inY: (p.inY !== undefined ? Number(p.inY) : (Number(p.y) || 0)) + dy,
                    outX: (p.outX !== undefined ? Number(p.outX) : (Number(p.x) || 0)) + dx,
                    outY: (p.outY !== undefined ? Number(p.outY) : (Number(p.y) || 0)) + dy
                });
            }
            out.push({
                closed: sub.closed === true,
                pts: pts
            });
        }
        return out;
    }

    function moveSelected(dx, dy) {
        var leaves = doc._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (doc.isEffectivelyLocked(leaves[i]))
                continue;
            leaves[i].x += dx;
            leaves[i].y += dy;
            if (leaves[i].shapeType === "pen")
                leaves[i].pathData = shiftPath(leaves[i], dx, dy);
        }
        doc.touch();
    }

    function snapSelection() {
        var leaves = doc._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (doc.isEffectivelyLocked(leaves[i]))
                continue;
            if (leaves[i].shapeType === "pen") {
                var src = leaves[i].pathData || [];
                var out = [];
                for (var a = 0; a < src.length; a++) {
                    var sub = src[a] || {};
                    var pts = [];
                    var arr = sub.pts || [];
                    for (var j = 0; j < arr.length; j++) {
                        var p = arr[j] || {};
                        pts.push({
                            x: Math.round(Number(p.x) || 0),
                            y: Math.round(Number(p.y) || 0),
                            smooth: p.smooth === true,
                            inX: Math.round(p.inX !== undefined ? Number(p.inX) : (Number(p.x) || 0)),
                            inY: Math.round(p.inY !== undefined ? Number(p.inY) : (Number(p.y) || 0)),
                            outX: Math.round(p.outX !== undefined ? Number(p.outX) : (Number(p.x) || 0)),
                            outY: Math.round(p.outY !== undefined ? Number(p.outY) : (Number(p.y) || 0))
                        });
                    }
                    out.push({
                        closed: sub.closed === true,
                        pts: pts
                    });
                }
                leaves[i].pathData = out;
                var box = doc.factory.penBBoxFor(out);
                leaves[i].x = box.x;
                leaves[i].y = box.y;
                leaves[i].w = box.w;
                leaves[i].h = box.h;
                continue;
            }
            leaves[i].x = Math.round(leaves[i].x);
            leaves[i].y = Math.round(leaves[i].y);
            leaves[i].w = Math.max(1, Math.round(leaves[i].w));
            leaves[i].h = Math.max(1, Math.round(leaves[i].h));
        }
        doc.touch();
    }

    // Magnitude fuse: no legitimate canvas geometry exceeds these
    // bounds (scenes are ~1e3 px, offsets ~1e3). Anything beyond is a
    // poisoned input (cleared field, drag-flip, stale snapshot); the
    // caller declines or the child keeps its box instead of writing
    // e±48 garbage.
    function saneBox(b) {
        if (!b || !isFinite(b.x + b.y + b.w + b.h))
            return false;
        if (!(b.w > 0) || !(b.h > 0))
            return false;
        return Math.abs(b.x) < 1e7 && Math.abs(b.y) < 1e7 && b.w < 1e7 && b.h < 1e7;
    }

    function scaleSelection(orig, box0, newBox) {
        // Shared-box mapping: one poisoned box would collapse every
        // child (all deltas derive from box0), so decline insane boxes
        // outright and skip insane snapshots entry-wise (see saneBox).
        // Touches only on real change so gesture transactions drop
        // no-op ticks.
        if (!box0 || !saneBox(box0))
            return;
        if (!newBox || !isFinite(newBox.x + newBox.y + newBox.w + newBox.h) || !(newBox.w > 0) || !(newBox.h > 0))
            return;
        // No-op ticks (press without move) touch nothing so gesture
        // transactions commit no entry.
        if (Math.abs(newBox.x - box0.x) < 0.001 && Math.abs(newBox.y - box0.y) < 0.001 && Math.abs(newBox.w - box0.w) < 0.001 && Math.abs(newBox.h - box0.h) < 0.001)
            return;
        var sx = newBox.w / box0.w, sy = newBox.h / box0.h;
        var mapX = v => newBox.x + (v - box0.x) * sx;
        var mapY = v => newBox.y + (v - box0.y) * sy;
        var changed = false;
        for (var k = 0; k < orig.length; k++) {
            var o = orig[k];
            if (!o || !saneBox(o))
                continue;
            var n = doc.findNode(o.uid);
            if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
                continue;
            if (n.shapeType === "pen" && o.pathData) {
                var out = [];
                for (var i = 0; i < o.pathData.length; i++) {
                    var sub = o.pathData[i] || {};
                    var pts = [];
                    var arr = sub.pts || [];
                    for (var j = 0; j < arr.length; j++) {
                        var p = arr[j] || {};
                        var px = Number(p.x) || 0, py = Number(p.y) || 0;
                        var ix = p.inX !== undefined ? Number(p.inX) : px;
                        var iy = p.inY !== undefined ? Number(p.inY) : py;
                        var ox = p.outX !== undefined ? Number(p.outX) : px;
                        var oy = p.outY !== undefined ? Number(p.outY) : py;
                        pts.push({
                            x: mapX(px),
                            y: mapY(py),
                            smooth: p.smooth === true,
                            inX: mapX(ix),
                            inY: mapY(iy),
                            outX: mapX(ox),
                            outY: mapY(oy)
                        });
                    }
                    out.push({
                        closed: sub.closed === true,
                        pts: pts
                    });
                }
                n.pathData = out;
                var box = doc.factory.penBBoxFor(out);
                n.x = box.x;
                n.y = box.y;
                n.w = box.w;
                n.h = box.h;
                changed = true;
                continue;
            }
            var ncx = newBox.x + (o.x + o.w / 2 - box0.x) * sx;
            var ncy = newBox.y + (o.y + o.h / 2 - box0.y) * sy;
            var nw = Math.max(1, o.w * sx);
            var nh = Math.max(1, o.h * sy);
            var nx = ncx - nw / 2, ny = ncy - nh / 2;
            if (Math.abs(nx - n.x) < 0.001 && Math.abs(ny - n.y) < 0.001 && Math.abs(nw - n.w) < 0.001 && Math.abs(nh - n.h) < 0.001)
                continue;
            n.x = nx;
            n.y = ny;
            n.w = nw;
            n.h = nh;
            changed = true;
        }
        if (changed)
            doc.touch();
    }

    function selectedLeafSnapshot() {
        var leaves = doc._selectedLeaves();
        var out = [];
        for (var i = 0; i < leaves.length; i++) {
            var entry = {
                uid: leaves[i].uid,
                x: leaves[i].x,
                y: leaves[i].y,
                w: leaves[i].w,
                h: leaves[i].h
            };
            if (leaves[i].shapeType === "pen")
                entry.pathData = doc.factory._copyPath(leaves[i].pathData);
            out.push(entry);
        }
        return out;
    }

    function setShapeProp(uid, role, value) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return;
        if (role === "w" || role === "h")
            value = Math.max(1, value);
        if (role === "points") {
            value = Math.min(12, Math.max(3, Math.round(value)));
            n[role] = value;
            doc.corners.adaptStarPoints(n);
            doc.touch();
            return;
        }
        if (role === "radius") {
            doc.corners.setUniform(n.uid, value);
            return;
        }
        n[role] = value;
        doc.touch();
    }

    function setPropSelected(role, value) {
        var tops = doc.selectedTops();
        var hasGroup = false;
        for (var i = 0; i < tops.length; i++) {
            if (tops[i].kind === "group") {
                hasGroup = true;
                break;
            }
        }
        if (hasGroup && (role === "x" || role === "y" || role === "w" || role === "h")) {
            _setBBoxProp(role, value);
            return;
        }
        var leaves = styleTargets();
        for (var j = 0; j < leaves.length; j++) {
            if (doc.isEffectivelyLocked(leaves[j]))
                continue;
            // Style roles apply per target; the `in` guard skips misses.
            if (role === "w" || role === "h")
                value = Math.max(1, value);
            if (role === "points") {
                var pv = Math.min(12, Math.max(3, Math.round(value)));
                leaves[j][role] = pv;
                doc.corners.adaptStarPoints(leaves[j]);
                continue;
            }
            if (role === "radius") {
                doc.corners.setUniform(leaves[j].uid, value);
                continue;
            }
            if (role in leaves[j])
                leaves[j][role] = value;
        }
        doc.touch();
    }

    function _setBBoxProp(role, value) {
        // Cleared/typed garbage commits nothing (NaN would poison every
        // solve below); panel scrubs own the transaction, so a bare
        // return stages no undo entry.
        if (!isFinite(Number(value)))
            return;
        var box = doc._selectionBBox();
        // A poisoned box (stale insane geometry) must not shift or
        // scale the selection: deltas derived from it would detonate
        // sane leaves. Delete + redraw poisoned shapes to recover.
        if (!box || !saneBox(box))
            return;
        if (!box)
            return;
        var leaves = doc._selectedLeaves();
        if (leaves.length === 0)
            return;
        if (role === "x") {
            var dx = value - box.x;
            if (Math.abs(dx) < 0.001)
                return;
            for (var i = 0; i < leaves.length; i++) {
                if (doc.isEffectivelyLocked(leaves[i]))
                    continue;
                leaves[i].x += dx;
                if (leaves[i].shapeType === "pen")
                    leaves[i].pathData = shiftPath(leaves[i], dx, 0);
            }
        } else if (role === "y") {
            var dy = value - box.y;
            if (Math.abs(dy) < 0.001)
                return;
            for (var j = 0; j < leaves.length; j++) {
                if (doc.isEffectivelyLocked(leaves[j]))
                    continue;
                leaves[j].y += dy;
                if (leaves[j].shapeType === "pen")
                    leaves[j].pathData = shiftPath(leaves[j], 0, dy);
            }
        } else if (role === "w" || role === "h") {
            var nw = Math.max(1, value);
            var newBox = {
                x: box.x,
                y: box.y,
                w: box.w,
                h: box.h
            };
            if (role === "w")
                newBox.w = nw;
            else
                newBox.h = nw;
            var orig = [];
            for (var k = 0; k < leaves.length; k++) {
                var entry = {
                    uid: leaves[k].uid,
                    x: leaves[k].x,
                    y: leaves[k].y,
                    w: leaves[k].w,
                    h: leaves[k].h
                };
                // Pens remap points (see scaleSelection); without the
                // frozen paths the box would move while points stay.
                if (leaves[k].shapeType === "pen")
                    entry.pathData = doc.factory._copyPath(leaves[k].pathData);
                orig.push(entry);
            }
            scaleSelection(orig, box, newBox);
            return;
        }
        doc.touch();
    }

    // Recolor one fill color within the selection only (compat for
    // stacked fills: every matching entry across the selection takes
    // the new color). Scoped like every other panel edit.
    function recolorSelected(oldFill, newFill) {
        var leaves = styleTargets();
        for (var i = 0; i < leaves.length; i++) {
            if (doc.isEffectivelyLocked(leaves[i]))
                continue;
            var arr = doc.factory._copyFills(leaves[i].fills, leaves[i]);
            var changed = false;
            for (var j = 0; j < arr.length; j++) {
                if (String(arr[j].color) === String(oldFill)) {
                    arr[j].color = String(newFill);
                    changed = true;
                }
            }
            if (changed)
                leaves[i].fills = arr;
        }
        doc.touch();
    }

    // Stacked paint edits. Arrays reassign wholesale so var bindings
    // fire; every entry round-trips through the factory copy so live
    // nodes never share objects with snapshots.
    // Style targets: selected leaves normally, or the single selected
    // group itself (boolean or plain frame) so panel fill/stroke/effect
    // edits land on group-owned stacks. Groups carry the same stack
    // shapes as leaves, so the _copy* round-trips below apply unchanged.
    function styleTargets() {
        var tops = doc.selectedTops();
        if (tops.length === 1 && tops[0].kind === "group" && !doc.isEffectivelyLocked(tops[0]))
            return [tops[0]];
        return _unlockedLeaves();
    }

    function _unlockedLeaves() {
        var out = [];
        var leaves = doc._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (!doc.isEffectivelyLocked(leaves[i]))
                out.push(leaves[i]);
        }
        return out;
    }

    function addFillToSelected() {
        var leaves = styleTargets();
        for (var i = 0; i < leaves.length; i++)
            leaves[i].fills = [doc.factory.defaultFill()].concat(doc.factory._copyFills(leaves[i].fills, leaves[i]));
        if (leaves.length > 0)
            doc.touch();
    }

    function addStrokeToSelected() {
        var leaves = styleTargets();
        for (var i = 0; i < leaves.length; i++)
            leaves[i].strokes = [doc.factory.defaultStroke()].concat(doc.factory._copyStrokes(leaves[i].strokes, leaves[i]));
        if (leaves.length > 0)
            doc.touch();
    }

    function removeFillAt(uid, index) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return;
        var arr = doc.factory._copyFills(n.fills, n);
        if (index < 0 || index >= arr.length)
            return;
        arr.splice(index, 1);
        n.fills = arr;
        doc.touch();
    }

    function removeStrokeAt(uid, index) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return;
        var arr = doc.factory._copyStrokes(n.strokes, n);
        if (index < 0 || index >= arr.length)
            return;
        arr.splice(index, 1);
        n.strokes = arr;
        doc.touch();
    }

    function moveFill(uid, from, to) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return;
        var arr = doc.factory._copyFills(n.fills, n);
        if (from < 0 || from >= arr.length || to < 0 || to >= arr.length || from === to)
            return;
        var entry = arr.splice(from, 1)[0];
        arr.splice(to, 0, entry);
        n.fills = arr;
        doc.touch();
    }

    function moveStroke(uid, from, to) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return;
        var arr = doc.factory._copyStrokes(n.strokes, n);
        if (from < 0 || from >= arr.length || to < 0 || to >= arr.length || from === to)
            return;
        var entry = arr.splice(from, 1)[0];
        arr.splice(to, 0, entry);
        n.strokes = arr;
        doc.touch();
    }

    function setFillEntry(uid, index, patch) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return;
        var arr = doc.factory._copyFills(n.fills, n);
        if (index < 0 || index >= arr.length)
            return;
        var p = patch ?? {};
        var cur = arr[index];
        if (p.color !== undefined)
            cur.color = String(p.color);
        if (p.type !== undefined)
            cur.type = p.type === "linear" ? "linear" : "solid";
        if (p.gradient !== undefined)
            cur.gradient = doc.factory._copyGradient(p.gradient);
        if (p.opacity !== undefined)
            cur.opacity = Math.min(1, Math.max(0, Number(p.opacity)));
        if (p.enabled !== undefined)
            cur.enabled = p.enabled !== false;
        arr[index] = doc.factory._copyFillEntry(cur);
        n.fills = arr;
        doc.touch();
    }

    function setStrokeEntry(uid, index, patch) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return;
        var arr = doc.factory._copyStrokes(n.strokes, n);
        if (index < 0 || index >= arr.length)
            return;
        var p = patch ?? {};
        var cur = arr[index];
        if (p.color !== undefined)
            cur.color = String(p.color);
        if (p.type !== undefined)
            cur.type = p.type === "linear" ? "linear" : "solid";
        if (p.gradient !== undefined)
            cur.gradient = doc.factory._copyGradient(p.gradient);
        if (p.width !== undefined)
            cur.width = Math.max(0, Number(p.width) || 0);
        if (p.dash !== undefined)
            cur.dash = doc.factory._copyDash(p.dash);
        if (p.position !== undefined)
            cur.position = (p.position === "inside" || p.position === "outside") ? p.position : "center";
        if (p.opacity !== undefined)
            cur.opacity = Math.min(1, Math.max(0, Number(p.opacity)));
        if (p.enabled !== undefined)
            cur.enabled = p.enabled !== false;
        arr[index] = doc.factory._copyStrokeEntry(cur);
        n.strokes = arr;
        doc.touch();
    }

    // Bulk per-index edits across the selection (one undo entry via
    // the Document wrapper's single checkpoint). Leaves missing the
    // index are skipped; adds/removes apply to every unlocked leaf.
    function patchFillAtSelected(at, patch) {
        var leaves = styleTargets();
        for (var i = 0; i < leaves.length; i++) {
            var arr = doc.factory._copyFills(leaves[i].fills, leaves[i]);
            if (at < 0 || at >= arr.length)
                continue;
            var cur = arr[at];
            var p = patch ?? {};
            if (p.color !== undefined)
                cur.color = String(p.color);
            if (p.type !== undefined)
                cur.type = p.type === "linear" ? "linear" : "solid";
            if (p.gradient !== undefined)
                cur.gradient = doc.factory._copyGradient(p.gradient);
            if (p.opacity !== undefined)
                cur.opacity = Math.min(1, Math.max(0, Number(p.opacity)));
            if (p.enabled !== undefined)
                cur.enabled = p.enabled !== false;
            arr[at] = doc.factory._copyFillEntry(cur);
            leaves[i].fills = arr;
        }
        if (leaves.length > 0)
            doc.touch();
    }

    function patchStrokeAtSelected(at, patch) {
        var leaves = styleTargets();
        for (var i = 0; i < leaves.length; i++) {
            var arr = doc.factory._copyStrokes(leaves[i].strokes, leaves[i]);
            if (at < 0 || at >= arr.length)
                continue;
            var cur = arr[at];
            var p = patch ?? {};
            if (p.color !== undefined)
                cur.color = String(p.color);
            if (p.type !== undefined)
                cur.type = p.type === "linear" ? "linear" : "solid";
            if (p.gradient !== undefined)
                cur.gradient = doc.factory._copyGradient(p.gradient);
            if (p.width !== undefined)
                cur.width = Math.max(0, Number(p.width) || 0);
            if (p.dash !== undefined)
                cur.dash = doc.factory._copyDash(p.dash);
            if (p.position !== undefined)
                cur.position = (p.position === "inside" || p.position === "outside") ? p.position : "center";
            if (p.opacity !== undefined)
                cur.opacity = Math.min(1, Math.max(0, Number(p.opacity)));
            if (p.enabled !== undefined)
                cur.enabled = p.enabled !== false;
            arr[at] = doc.factory._copyStrokeEntry(cur);
            leaves[i].strokes = arr;
        }
        if (leaves.length > 0)
            doc.touch();
    }

    function toggleFillAtSelected(at) {
        var leaves = styleTargets();
        var nextOn = true;
        var found = false;
        for (var i = 0; i < leaves.length; i++) {
            var arr = doc.factory._copyFills(leaves[i].fills, leaves[i]);
            if (at < 0 || at >= arr.length)
                continue;
            if (!found) {
                nextOn = !(arr[at].enabled !== false);
                found = true;
            }
        }
        for (var j = 0; j < leaves.length; j++) {
            var list = doc.factory._copyFills(leaves[j].fills, leaves[j]);
            if (at < 0 || at >= list.length)
                continue;
            list[at] = doc.factory._copyFillEntry(Object.assign({}, list[at], {
                enabled: nextOn
            }));
            leaves[j].fills = list;
        }
        if (leaves.length > 0)
            doc.touch();
    }

    function toggleStrokeAtSelected(at) {
        var leaves = styleTargets();
        var nextOn = true;
        var found = false;
        for (var i = 0; i < leaves.length; i++) {
            var arr = doc.factory._copyStrokes(leaves[i].strokes, leaves[i]);
            if (at < 0 || at >= arr.length)
                continue;
            if (!found) {
                nextOn = !(arr[at].enabled !== false);
                found = true;
            }
        }
        for (var j = 0; j < leaves.length; j++) {
            var list = doc.factory._copyStrokes(leaves[j].strokes, leaves[j]);
            if (at < 0 || at >= list.length)
                continue;
            list[at] = doc.factory._copyStrokeEntry(Object.assign({}, list[at], {
                enabled: nextOn
            }));
            leaves[j].strokes = list;
        }
        if (leaves.length > 0)
            doc.touch();
    }

    function moveFillAtSelected(at, delta) {
        var to = at + delta;
        if (to < 0)
            return;
        var leaves = styleTargets();
        for (var i = 0; i < leaves.length; i++) {
            var list = doc.factory._copyFills(leaves[i].fills, leaves[i]);
            if (at < 0 || at >= list.length || to < 0 || to >= list.length)
                continue;
            var tmp = list[at];
            list[at] = list[to];
            list[to] = tmp;
            leaves[i].fills = list;
        }
        if (leaves.length > 0)
            doc.touch();
    }

    function moveStrokeAtSelected(at, delta) {
        var to = at + delta;
        if (to < 0)
            return;
        var leaves = styleTargets();
        for (var i = 0; i < leaves.length; i++) {
            var list = doc.factory._copyStrokes(leaves[i].strokes, leaves[i]);
            if (at < 0 || at >= list.length || to < 0 || to >= list.length)
                continue;
            var tmp = list[at];
            list[at] = list[to];
            list[to] = tmp;
            leaves[i].strokes = list;
        }
        if (leaves.length > 0)
            doc.touch();
    }

    function removeFillAtSelected(at) {
        var leaves = styleTargets();
        for (var i = 0; i < leaves.length; i++) {
            var list = doc.factory._copyFills(leaves[i].fills, leaves[i]);
            if (at < 0 || at >= list.length)
                continue;
            list.splice(at, 1);
            leaves[i].fills = list;
        }
        if (leaves.length > 0)
            doc.touch();
    }

    function removeStrokeAtSelected(at) {
        var leaves = styleTargets();
        for (var i = 0; i < leaves.length; i++) {
            var list = doc.factory._copyStrokes(leaves[i].strokes, leaves[i]);
            if (at < 0 || at >= list.length)
                continue;
            list.splice(at, 1);
            leaves[i].strokes = list;
        }
        if (leaves.length > 0)
            doc.touch();
    }

    // Quarter turn clockwise per leaf, normalized to [0, 360).
    function rotateSelected90() {
        var leaves = doc._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (doc.isEffectivelyLocked(leaves[i]))
                continue;
            leaves[i].rotation = (((leaves[i].rotation + 90) % 360) + 360) % 360;
        }
        doc.touch();
    }

    function flipSelectedH() {
        var leaves = doc._selectedLeaves();
        for (var j = 0; j < leaves.length; j++) {
            if (doc.isEffectivelyLocked(leaves[j]))
                continue;
            leaves[j].flipH = !leaves[j].flipH;
        }
        doc.touch();
    }

    function flipSelectedV() {
        var leaves = doc._selectedLeaves();
        for (var k = 0; k < leaves.length; k++) {
            if (doc.isEffectivelyLocked(leaves[k]))
                continue;
            leaves[k].flipV = !leaves[k].flipV;
        }
        doc.touch();
    }

    function shiftTop(top, dx, dy) {
        if (dx === 0 && dy === 0)
            return;
        var leaves = top.kind === "group" ? doc._leavesUnder(top) : [top];
        for (var i = 0; i < leaves.length; i++) {
            if (doc.isEffectivelyLocked(leaves[i]))
                continue;
            leaves[i].x += dx;
            leaves[i].y += dy;
            if (leaves[i].shapeType === "pen")
                leaves[i].pathData = shiftPath(leaves[i], dx, dy);
        }
    }

    function unlockedTops() {
        var out = [];
        var every = doc.selectedTops();
        for (var i = 0; i < every.length; i++) {
            if (!doc.isEffectivelyLocked(every[i]))
                out.push(every[i]);
        }
        return out;
    }

    // Align unlocked tops to their union box. Single gesture: the
    // Document wrapper checkpoints once, this only moves + touches.
    function alignSelection(mode) {
        var tops = unlockedTops();
        if (tops.length < 2)
            return false;
        var ref = doc._selectionBBox();
        if (!ref)
            return false;
        var done = false;
        for (var i = 0; i < tops.length; i++) {
            var b = doc.bounds.bboxOfNode(tops[i]);
            if (!b)
                continue;
            var dx = 0, dy = 0;
            if (mode === "hLeft")
                dx = ref.x - b.x;
            else if (mode === "hCenter")
                dx = (ref.x + ref.w / 2) - (b.x + b.w / 2);
            else if (mode === "hRight")
                dx = (ref.x + ref.w) - (b.x + b.w);
            else if (mode === "vTop")
                dy = ref.y - b.y;
            else if (mode === "vMiddle")
                dy = (ref.y + ref.h / 2) - (b.y + b.h / 2);
            else if (mode === "vBottom")
                dy = (ref.y + ref.h) - (b.y + b.h);
            else
                return false;
            if (dx !== 0 || dy !== 0) {
                shiftTop(tops[i], dx, dy);
                done = true;
            }
        }
        if (done)
            doc.touch();
        return done;
    }

    // Even center spacing between the first and last tops on one axis.
    // First/last (by center) stay put, middles spread between them.
    function distributeSelection(axis) {
        var tops = unlockedTops();
        if (tops.length < 3)
            return false;
        var boxes = [];
        for (var i = 0; i < tops.length; i++) {
            var b = doc.bounds.bboxOfNode(tops[i]);
            if (b)
                boxes.push({
                    top: tops[i],
                    box: b
                });
        }
        if (boxes.length < 3)
            return false;
        var horiz = axis === "h";
        boxes.sort((a, b) => horiz ? (a.box.x + a.box.w / 2) - (b.box.x + b.box.w / 2) : (a.box.y + a.box.h / 2) - (b.box.y + b.box.h / 2));
        var first = horiz ? boxes[0].box.x + boxes[0].box.w / 2 : boxes[0].box.y + boxes[0].box.h / 2;
        var last = horiz ? boxes[boxes.length - 1].box.x + boxes[boxes.length - 1].box.w / 2 : boxes[boxes.length - 1].box.y + boxes[boxes.length - 1].box.h / 2;
        var step = (last - first) / (boxes.length - 1);
        var done = false;
        for (var j = 1; j < boxes.length - 1; j++) {
            var target = first + j * step;
            var cur = horiz ? boxes[j].box.x + boxes[j].box.w / 2 : boxes[j].box.y + boxes[j].box.h / 2;
            var d = target - cur;
            if (d !== 0) {
                shiftTop(boxes[j].top, horiz ? d : 0, horiz ? 0 : d);
                done = true;
            }
        }
        if (done)
            doc.touch();
        return done;
    }
}
