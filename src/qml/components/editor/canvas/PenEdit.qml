import QtQuick

// Point editing for one canvas. Double-click a pen node to enter;
// Esc/Enter or empty click exits. Drag anchors to move (snapped),
// drag handles for symmetric curves (free), click edge to insert,
// Delete drops points, double-click toggles smooth. Moves coalesce
// into one undo entry via begin/end; discrete ops checkpoint once.
QtObject {
    id: edit

    required property var canvas
    required property var snap

    // Point evaluation (single source shared with the pen/path tools).
    property var bezier: BezierMath {}

    property int editUid: -1
    property var sel: []
    property var hover: null
    property var drag: null

    function node() {
        var d = edit.canvas.doc;
        if (!d || edit.editUid < 0)
            return null;
        var n = d.findNode(edit.editUid);
        if (!n || n.kind !== "shape" || n.shapeType !== "pen")
            return null;
        return n;
    }

    function enter(uid) {
        var d = edit.canvas.doc;
        if (!d)
            return;
        var n = d.findNode(uid);
        if (!n || n.shapeType !== "pen")
            return;
        edit.editUid = uid;
        edit.sel = [];
        edit.drag = null;
        edit.hover = null;
    }

    function exit() {
        edit.editUid = -1;
        edit.sel = [];
        edit.drag = null;
        edit.hover = null;
    }

    function toCX(px) {
        var z = edit.canvas.zoom > 0 ? edit.canvas.zoom : 1;
        return (px - edit.canvas.offsetX) / z;
    }

    function toCY(py) {
        var z = edit.canvas.zoom > 0 ? edit.canvas.zoom : 1;
        return (py - edit.canvas.offsetY) / z;
    }

    function pointRadius() {
        var z = edit.canvas.zoom > 0 ? edit.canvas.zoom : 1;
        return 8 / z;
    }

    function edgeRadius() {
        var z = edit.canvas.zoom > 0 ? edit.canvas.zoom : 1;
        return 6 / z;
    }

    function snapped(cx, cy, mods) {
        var d = edit.canvas.doc;
        if (!d)
            return {
                x: cx,
                y: cy
            };
        if (edit.canvas.altHeld || (mods & Qt.AltModifier))
            return {
                x: cx,
                y: cy
            };
        return edit.snap.snapPoint(d, cx, cy, edit.canvas.zoom);
    }

    function hitPoint(cx, cy) {
        var n = edit.node();
        if (!n)
            return null;
        var best = null;
        var path = n.pathData || [];
        for (var s = 0; s < path.length; s++) {
            var pts = (path[s] || {}).pts || [];
            for (var i = 0; i < pts.length; i++) {
                var p = pts[i] || {};
                var d = Math.hypot(cx - (Number(p.x) || 0), cy - (Number(p.y) || 0));
                if (d <= edit.pointRadius() && (!best || d < best.dist))
                    best = {
                        kind: "point",
                        sub: s,
                        idx: i,
                        dist: d
                    };
            }
        }
        return best;
    }

    function hitHandle(cx, cy) {
        var n = edit.node();
        if (!n)
            return null;
        var best = null;
        for (var k = 0; k < edit.sel.length; k++) {
            var s = edit.sel[k].sub, i = edit.sel[k].idx;
            var path = n.pathData || [];
            if (!path[s] || !path[s].pts[i])
                continue;
            var p = path[s].pts[i] || {};
            if (p.smooth !== true)
                continue;
            var ix = p.inX !== undefined ? Number(p.inX) : (Number(p.x) || 0);
            var iy = p.inY !== undefined ? Number(p.inY) : (Number(p.y) || 0);
            var di = Math.hypot(cx - ix, cy - iy);
            if (di <= edit.edgeRadius() && (!best || di < best.dist))
                best = {
                    kind: "handle",
                    sub: s,
                    idx: i,
                    which: "in",
                    dist: di
                };
            var ox = p.outX !== undefined ? Number(p.outX) : (Number(p.x) || 0);
            var oy = p.outY !== undefined ? Number(p.outY) : (Number(p.y) || 0);
            var du = Math.hypot(cx - ox, cy - oy);
            if (du <= edit.edgeRadius() && (!best || du < best.dist))
                best = {
                    kind: "handle",
                    sub: s,
                    idx: i,
                    which: "out",
                    dist: du
                };
        }
        return best;
    }

    function bezierAt(a, b, t) {
        return edit.bezier.bezierPoint(a, b, t);
    }

    function edgeHit(cx, cy) {
        var n = edit.node();
        if (!n)
            return null;
        var best = null;
        var path = n.pathData || [];
        for (var s = 0; s < path.length; s++) {
            var sub = path[s] || {};
            var pts = sub.pts || [];
            var segs = pts.length - 1;
            if (sub.closed === true && pts.length > 1)
                segs = pts.length;
            for (var g = 0; g < segs; g++) {
                var a = pts[g];
                var b = pts[(g + 1) % pts.length];
                for (var k = 0; k <= 16; k++) {
                    var q = edit.bezierAt(a, b, k / 16);
                    var d = Math.hypot(cx - q.x, cy - q.y);
                    if (d <= edit.edgeRadius() && (!best || d < best.dist)) {
                        var at = (sub.closed === true && g === pts.length - 1) ? pts.length : g + 1;
                        best = {
                            kind: "edge",
                            sub: s,
                            at: at,
                            pt: q,
                            dist: d
                        };
                    }
                }
            }
        }
        return best;
    }

    function isSelected(sub, idx) {
        for (var i = 0; i < edit.sel.length; i++) {
            if (edit.sel[i].sub === sub && edit.sel[i].idx === idx)
                return true;
        }
        return false;
    }

    // Returns true when the press is consumed (point/handle/edge).
    function pressAt(sx, sy, mods) {
        var c = edit.canvas;
        if (!c.doc || edit.editUid < 0)
            return false;
        var n = edit.node();
        if (!n) {
            edit.exit();
            return false;
        }
        c.forceActiveFocus();
        var cx = edit.toCX(sx), cy = edit.toCY(sy);
        var h = edit.hitHandle(cx, cy);
        if (h) {
            if (!edit.isSelected(h.sub, h.idx))
                edit.sel = [
                    {
                        sub: h.sub,
                        idx: h.idx
                    }
                ];
            c.doc.beginTransaction();
            edit.drag = {
                kind: "handle",
                sub: h.sub,
                idx: h.idx,
                which: h.which
            };
            return true;
        }
        var p = edit.hitPoint(cx, cy);
        if (p) {
            if (mods & (Qt.ShiftModifier | Qt.ControlModifier | Qt.MetaModifier)) {
                if (edit.isSelected(p.sub, p.idx)) {
                    var out = [];
                    for (var i = 0; i < edit.sel.length; i++) {
                        if (!(edit.sel[i].sub === p.sub && edit.sel[i].idx === p.idx))
                            out.push(edit.sel[i]);
                    }
                    edit.sel = out;
                    return true;
                }
                var next = edit.sel.slice();
                next.push({
                    sub: p.sub,
                    idx: p.idx
                });
                edit.sel = next;
            } else if (!edit.isSelected(p.sub, p.idx)) {
                edit.sel = [
                    {
                        sub: p.sub,
                        idx: p.idx
                    }
                ];
            }
            var sp = edit.snapped(cx, cy, mods);
            c.doc.beginTransaction();
            edit.drag = {
                kind: "point",
                lastX: sp.x,
                lastY: sp.y
            };
            return true;
        }
        var e = edit.edgeHit(cx, cy);
        if (e) {
            if (c.doc.penInsertPoint(edit.editUid, e.sub, e.at, e.pt)) {
                // Insertion shifts later indices in the same sub.
                var shifted = [];
                for (var j = 0; j < edit.sel.length; j++) {
                    var s = edit.sel[j];
                    if (s.sub === e.sub && s.idx >= e.at)
                        shifted.push({
                            sub: s.sub,
                            idx: s.idx + 1
                        });
                    else
                        shifted.push(s);
                }
                shifted.push({
                    sub: e.sub,
                    idx: e.at
                });
                edit.sel = shifted;
            }
            return true;
        }
        edit.exit();
        return false;
    }

    function moveTo(sx, sy, mods) {
        var c = edit.canvas;
        if (edit.editUid < 0)
            return;
        var cx = edit.toCX(sx), cy = edit.toCY(sy);
        if (!edit.drag) {
            var h = edit.hitHandle(cx, cy);
            var p = h ? null : edit.hitPoint(cx, cy);
            edit.hover = h || p || edit.edgeHit(cx, cy);
            return;
        }
        if (edit.drag.kind === "handle") {
            c.doc.penOps.moveHandle(edit.editUid, edit.drag.sub, edit.drag.idx, edit.drag.which, cx, cy);
            return;
        }
        var sp = edit.snapped(cx, cy, mods);
        var dx = sp.x - edit.drag.lastX;
        var dy = sp.y - edit.drag.lastY;
        if (dx === 0 && dy === 0)
            return;
        edit.drag.lastX = sp.x;
        edit.drag.lastY = sp.y;
        // Multi-move joins one entry: later indices first per sub.
        var order = edit.sel.slice().sort((a, b) => (a.sub !== b.sub ? a.sub - b.sub : b.idx - a.idx));
        for (var i = 0; i < order.length; i++)
            c.doc.penOps.movePoint(edit.editUid, order[i].sub, order[i].idx, dx, dy);
    }

    function releaseAt() {
        var c = edit.canvas;
        if (edit.drag && c.doc)
            c.doc.endTransaction();
        edit.drag = null;
    }

    function doubleAt(sx, sy) {
        if (edit.editUid < 0)
            return false;
        var p = edit.hitPoint(edit.toCX(sx), edit.toCY(sy));
        if (!p)
            return false;
        edit.canvas.doc.penToggleSmooth(edit.editUid, p.sub, p.idx);
        if (!edit.isSelected(p.sub, p.idx))
            edit.sel = [
                {
                    sub: p.sub,
                    idx: p.idx
                }
            ];
        return true;
    }

    function deleteSelected() {
        var c = edit.canvas;
        if (edit.editUid < 0 || edit.sel.length === 0 || !c.doc)
            return false;
        var uid = edit.editUid;
        var order = edit.sel.slice().sort((a, b) => (a.sub !== b.sub ? a.sub - b.sub : b.idx - a.idx));
        c.doc.beginTransaction();
        for (var i = 0; i < order.length; i++)
            c.doc.penOps.deletePoint(uid, order[i].sub, order[i].idx);
        c.doc.endTransaction();
        edit.sel = [];
        if (!c.doc.findNode(uid))
            edit.exit();
        return true;
    }
}
