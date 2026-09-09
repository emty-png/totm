import QtQuick

// Motion-path draw + edit state for custom Path clips. Click adds
// corners, drag makes symmetric smooth points; existing points hit-test
// first: drag anchors to move (snapped), handles to bend (mirrored free),
// double-click toggles smooth, edge click inserts, Delete removes.
// Everything edits the working copy: Enter commits once, Esc discards.
// Single part only (closed loops come from the clip's closed toggle).
// Points commit as relative offsets from the path start (first point
// 0,0) so motion stays valid when nodes move.
QtObject {
    id: tool

    required property var canvas
    required property var snap

    property var active: []
    property bool dragging: false
    property int dragIndex: -1
    // Draw loop closure preview (seeded from the redraw target's clip).
    property bool showClosed: false
    // Edit state: selected anchor indices, hover hit and active edit drag
    // (creation bends reuse dragging/dragIndex above).
    property var sel: []
    property var hover: null
    property var editDrag: null
    property real pressCX: 0
    property real pressCY: 0
    property real pressSX: 0
    property real pressSY: 0
    property real cursorCX: 0
    property real cursorCY: 0
    property real snCX: 0
    property real snCY: 0
    property bool hasCursor: false

    readonly property bool hasWork: tool.active.length > 0
    readonly property bool viable: tool.active.length >= 2
    readonly property bool previewActive: tool.active.length > 0 && tool.hasCursor && !tool.dragging && !tool.editDrag

    function toCX(px) {
        var z = tool.canvas.zoom > 0 ? tool.canvas.zoom : 1;
        return (px - tool.canvas.offsetX) / z;
    }

    function toCY(py) {
        var z = tool.canvas.zoom > 0 ? tool.canvas.zoom : 1;
        return (py - tool.canvas.offsetY) / z;
    }

    function snapped(cx, cy, mods) {
        var d = tool.canvas.doc;
        if (!d)
            return {
                x: cx,
                y: cy
            };
        if (tool.canvas.altHeld || (mods & Qt.AltModifier))
            return {
                x: cx,
                y: cy
            };
        return tool.snap.snapPoint(d, cx, cy, tool.canvas.zoom);
    }

    function refreshHover(sx, sy, mods) {
        tool.updatePreview(sx, sy, mods);
    }

    function updatePreview(sx, sy, mods) {
        var rawX = tool.toCX(sx);
        var rawY = tool.toCY(sy);
        tool.cursorCX = rawX;
        tool.cursorCY = rawY;
        tool.hasCursor = true;
        var sp = tool.snapped(rawX, rawY, mods);
        tool.snCX = sp.x;
        tool.snCY = sp.y;
        var c = tool.canvas;
        if (!c)
            return;
        if (tool.active.length === 0 || tool.dragging) {
            c.snapXGuides = [];
            c.snapYGuides = [];
            return;
        }
        c.snapXGuides = (sp.x !== rawX) ? [sp.x] : [];
        c.snapYGuides = (sp.y !== rawY) ? [sp.y] : [];
    }

    function clearPreviewGuides() {
        var c = tool.canvas;
        if (c) {
            c.snapXGuides = [];
            c.snapYGuides = [];
        }
    }

    function exitHover() {
        tool.hasCursor = false;
        tool.hover = null;
        tool.clearPreviewGuides();
    }

    function pointRadius() {
        var z = tool.canvas.zoom > 0 ? tool.canvas.zoom : 1;
        return 8 / z;
    }

    function edgeRadius() {
        var z = tool.canvas.zoom > 0 ? tool.canvas.zoom : 1;
        return 6 / z;
    }

    function isSelected(idx) {
        return tool.sel.indexOf(idx) >= 0;
    }

    function hitPoint(cx, cy) {
        var best = null;
        for (var i = 0; i < tool.active.length; i++) {
            var p = tool.active[i] || {};
            var d = Math.hypot(cx - (Number(p.x) || 0), cy - (Number(p.y) || 0));
            if (d <= tool.pointRadius() && (!best || d < best.dist))
                best = {
                    kind: "point",
                    idx: i,
                    dist: d
                };
        }
        return best;
    }

    function hitHandle(cx, cy) {
        var best = null;
        for (var k = 0; k < tool.sel.length; k++) {
            var p = tool.active[tool.sel[k]] || {};
            if (p.smooth !== true)
                continue;
            var ix = p.inX !== undefined ? Number(p.inX) : (Number(p.x) || 0);
            var iy = p.inY !== undefined ? Number(p.inY) : (Number(p.y) || 0);
            var di = Math.hypot(cx - ix, cy - iy);
            if (di <= tool.edgeRadius() && (!best || di < best.dist))
                best = {
                    kind: "handle",
                    idx: tool.sel[k],
                    which: "in",
                    dist: di
                };
            var ox = p.outX !== undefined ? Number(p.outX) : (Number(p.x) || 0);
            var oy = p.outY !== undefined ? Number(p.outY) : (Number(p.y) || 0);
            var du = Math.hypot(cx - ox, cy - oy);
            if (du <= tool.edgeRadius() && (!best || du < best.dist))
                best = {
                    kind: "handle",
                    idx: tool.sel[k],
                    which: "out",
                    dist: du
                };
        }
        return best;
    }

    function bezierAt(a, b, t) {
        var ax = Number(a.x) || 0, ay = Number(a.y) || 0;
        var bx = Number(b.x) || 0, by = Number(b.y) || 0;
        var aS = a.smooth === true, bS = b.smooth === true;
        var c1x = aS ? (a.outX !== undefined ? Number(a.outX) : ax) : ax;
        var c1y = aS ? (a.outY !== undefined ? Number(a.outY) : ay) : ay;
        var c2x = bS ? (b.inX !== undefined ? Number(b.inX) : bx) : bx;
        var c2y = bS ? (b.inY !== undefined ? Number(b.inY) : by) : by;
        var u = 1 - t;
        return {
            x: u * u * u * ax + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * bx,
            y: u * u * u * ay + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * by
        };
    }

    function edgeHit(cx, cy) {
        var pts = tool.active;
        var segs = pts.length - 1;
        if (tool.showClosed && pts.length > 1)
            segs = pts.length;
        var best = null;
        for (var g = 0; g < segs; g++) {
            var a = pts[g];
            var b = pts[(g + 1) % pts.length];
            for (var k = 0; k <= 16; k++) {
                var q = tool.bezierAt(a, b, k / 16);
                var d = Math.hypot(cx - q.x, cy - q.y);
                if (d <= tool.edgeRadius() && (!best || d < best.dist)) {
                    var at = (tool.showClosed && g === pts.length - 1) ? pts.length : g + 1;
                    best = {
                        kind: "edge",
                        at: at,
                        pt: q,
                        dist: d
                    };
                }
            }
        }
        return best;
    }

    // Existing geometry hit-tests first (bend/move/insert); empty space
    // appends a fresh corner like before.
    function pressAt(sx, sy, mods) {
        var c = tool.canvas;
        if (!c.doc)
            return;
        c.forceActiveFocus();
        c.commitTextEdit();
        c.altHeld = !!(mods & Qt.AltModifier);
        var cx = tool.toCX(sx), cy = tool.toCY(sy);
        var h = tool.hitHandle(cx, cy);
        if (h) {
            if (!tool.isSelected(h.idx))
                tool.sel = [h.idx];
            tool.editDrag = {
                kind: "handle",
                idx: h.idx,
                which: h.which
            };
            return;
        }
        var p = tool.hitPoint(cx, cy);
        if (p) {
            if (mods & (Qt.ShiftModifier | Qt.ControlModifier | Qt.MetaModifier)) {
                if (tool.isSelected(p.idx))
                    tool.sel = tool.sel.filter(kept => kept !== p.idx);
                else
                    tool.sel = tool.sel.concat([p.idx]);
                return;
            }
            if (!tool.isSelected(p.idx))
                tool.sel = [p.idx];
            var sp = tool.snapped(cx, cy, mods);
            tool.editDrag = {
                kind: "point",
                lastX: sp.x,
                lastY: sp.y
            };
            return;
        }
        var e = tool.edgeHit(cx, cy);
        if (e) {
            var pts = tool.active.slice();
            pts.splice(e.at, 0, {
                x: e.pt.x,
                y: e.pt.y,
                smooth: false,
                inX: e.pt.x,
                inY: e.pt.y,
                outX: e.pt.x,
                outY: e.pt.y
            });
            tool.active = pts;
            // Insertion shifts later indices.
            tool.sel = tool.sel.map(kept => kept >= e.at ? kept + 1 : kept).concat([e.at]);
            return;
        }
        var rawCX = cx, rawCY = cy;
        var end = tool.snapped(rawCX, rawCY, mods);
        var next = tool.active.slice();
        next.push({
            x: end.x,
            y: end.y,
            smooth: false,
            inX: end.x,
            inY: end.y,
            outX: end.x,
            outY: end.y
        });
        tool.active = next;
        tool.sel = [next.length - 1];
        tool.dragging = false;
        tool.dragIndex = next.length - 1;
        tool.pressCX = end.x;
        tool.pressCY = end.y;
        tool.pressSX = sx;
        tool.pressSY = sy;
        tool.cursorCX = end.x;
        tool.cursorCY = end.y;
        tool.snCX = end.x;
        tool.snCY = end.y;
        tool.hasCursor = true;
        tool.clearPreviewGuides();
    }

    function moveTo(sx, sy, mods, pressed) {
        var rawX = tool.toCX(sx);
        var rawY = tool.toCY(sy);
        tool.cursorCX = rawX;
        tool.cursorCY = rawY;
        tool.hasCursor = true;
        if (tool.editDrag) {
            if (!pressed)
                return;
            if (tool.editDrag.kind === "handle") {
                var pts = tool.active.slice();
                var p = pts[tool.editDrag.idx] || {};
                var px = Number(p.x) || 0, py = Number(p.y) || 0;
                if (tool.editDrag.which === "in")
                    pts[tool.editDrag.idx] = tool.mirroredHandle(p, px, py, rawX, rawY, true);
                else
                    pts[tool.editDrag.idx] = tool.mirroredHandle(p, px, py, rawX, rawY, false);
                tool.active = pts;
                return;
            }
            var sp = tool.snapped(rawX, rawY, mods);
            var dx = sp.x - tool.editDrag.lastX;
            var dy = sp.y - tool.editDrag.lastY;
            if (dx === 0 && dy === 0)
                return;
            tool.editDrag.lastX = sp.x;
            tool.editDrag.lastY = sp.y;
            var moved = tool.active.slice();
            for (var i = 0; i < tool.sel.length; i++) {
                var q = moved[tool.sel[i]] || {};
                var qx = Number(q.x) || 0, qy = Number(q.y) || 0;
                moved[tool.sel[i]] = {
                    x: qx + dx,
                    y: qy + dy,
                    smooth: q.smooth === true,
                    inX: (q.inX !== undefined ? Number(q.inX) : qx) + dx,
                    inY: (q.inY !== undefined ? Number(q.inY) : qy) + dy,
                    outX: (q.outX !== undefined ? Number(q.outX) : qx) + dx,
                    outY: (q.outY !== undefined ? Number(q.outY) : qy) + dy
                };
            }
            tool.active = moved;
            return;
        }
        if (!pressed) {
            var hh = tool.hitHandle(rawX, rawY);
            tool.hover = hh ? hh : (tool.hitPoint(rawX, rawY) || tool.edgeHit(rawX, rawY));
            return;
        }
        if (tool.dragIndex < 0 || tool.dragIndex >= tool.active.length)
            return;
        if (!tool.dragging && Math.hypot(sx - tool.pressSX, sy - tool.pressSY) < 4) {
            var sp0 = tool.snapped(rawX, rawY, mods);
            tool.cursorCX = sp0.x;
            tool.cursorCY = sp0.y;
            tool.snCX = sp0.x;
            tool.snCY = sp0.y;
            tool.setDragGuides(rawX, rawY, sp0);
            return;
        }
        tool.dragging = true;
        var bp = tool.snapped(rawX, rawY, mods);
        var vx = bp.x - tool.pressCX;
        var vy = bp.y - tool.pressCY;
        var bent = tool.active.slice();
        bent[tool.dragIndex] = {
            x: tool.pressCX,
            y: tool.pressCY,
            smooth: true,
            inX: tool.pressCX - vx,
            inY: tool.pressCY - vy,
            outX: tool.pressCX + vx,
            outY: tool.pressCY + vy
        };
        tool.active = bent;
        tool.cursorCX = bp.x;
        tool.cursorCY = bp.y;
        tool.snCX = bp.x;
        tool.snCY = bp.y;
        tool.setDragGuides(rawX, rawY, bp);
    }

    // Free handle move with the opposite arm mirrored (same convention
    // as creation bends and DocPen.moveHandle).
    function mirroredHandle(p, px, py, x, y, isIn) {
        if (isIn)
            return {
                x: px,
                y: py,
                smooth: true,
                inX: x,
                inY: y,
                outX: px + (px - x),
                outY: py + (py - y)
            };
        return {
            x: px,
            y: py,
            smooth: true,
            inX: px + (px - x),
            inY: py + (py - y),
            outX: x,
            outY: y
        };
    }

    // Double-click toggles smooth (mirrors DocPen.toggleSmooth); empty
    // space reports false so the canvas falls through to commit.
    function doubleAt(sx, sy) {
        var p = tool.hitPoint(tool.toCX(sx), tool.toCY(sy));
        if (!p)
            return false;
        var pts = tool.active.slice();
        var q = pts[p.idx] || {};
        var qx = Number(q.x) || 0, qy = Number(q.y) || 0;
        if (q.smooth === true) {
            pts[p.idx] = {
                x: qx,
                y: qy,
                smooth: false,
                inX: qx,
                inY: qy,
                outX: qx,
                outY: qy
            };
        } else {
            pts[p.idx] = {
                x: qx,
                y: qy,
                smooth: true,
                inX: qx - 20,
                inY: qy,
                outX: qx + 20,
                outY: qy
            };
        }
        tool.active = pts;
        if (!tool.isSelected(p.idx))
            tool.sel = [p.idx];
        return true;
    }

    // Drops selected anchors (any count; commits still need 2+ points,
    // so wiping to scratch and redrawing in one session just works).
    function deleteSelected() {
        if (tool.sel.length === 0 || tool.active.length === 0)
            return false;
        var drop = {};
        for (var i = 0; i < tool.sel.length; i++)
            drop[tool.sel[i]] = true;
        var kept = [];
        for (var j = 0; j < tool.active.length; j++) {
            if (!drop[j])
                kept.push(tool.active[j]);
        }
        if (kept.length === tool.active.length)
            return false;
        tool.active = kept;
        tool.sel = [];
        tool.hover = null;
        tool.editDrag = null;
        return true;
    }

    function setDragGuides(rawX, rawY, sp) {
        var c = tool.canvas;
        if (!c)
            return;
        c.snapXGuides = (sp.x !== rawX) ? [sp.x] : [];
        c.snapYGuides = (sp.y !== rawY) ? [sp.y] : [];
    }

    function releaseAt() {
        tool.dragging = false;
        tool.dragIndex = -1;
        tool.editDrag = null;
        tool.clearPreviewGuides();
    }

    // Relative offsets from the path start (first point 0,0). Absolute
    // draw location never moves the shape's start; only the shape of the
    // trajectory matters.
    function relativePts() {
        if (tool.active.length < 2)
            return [];
        var f = tool.active[0] || {};
        var fx = Number(f.x) || 0, fy = Number(f.y) || 0;
        var out = [];
        for (var i = 0; i < tool.active.length; i++) {
            var p = tool.active[i] || {};
            var px = Number(p.x) || 0, py = Number(p.y) || 0;
            var ix = p.inX !== undefined ? Number(p.inX) : px;
            var iy = p.inY !== undefined ? Number(p.inY) : py;
            var ox = p.outX !== undefined ? Number(p.outX) : px;
            var oy = p.outY !== undefined ? Number(p.outY) : py;
            out.push({
                x: px - fx,
                y: py - fy,
                smooth: p.smooth === true,
                inX: ix - fx,
                inY: iy - fy,
                outX: ox - fx,
                outY: oy - fy
            });
        }
        return out;
    }

    function cancel() {
        tool.active = [];
        tool.dragging = false;
        tool.dragIndex = -1;
        tool.showClosed = false;
        tool.sel = [];
        tool.hover = null;
        tool.editDrag = null;
        tool.hasCursor = false;
        tool.clearPreviewGuides();
    }

    // Seed the session with absolute content points (e.g. an existing
    // clip's trajectory at its base) so redraws show what they replace.
    // Commits convert back to start-relative, round-tripping exactly.
    function loadAbsolute(pts) {
        var out = [];
        var list = pts || [];
        for (var i = 0; i < list.length; i++) {
            var p = list[i] || {};
            var px = Number(p.x) || 0, py = Number(p.y) || 0;
            out.push({
                x: px,
                y: py,
                smooth: p.smooth === true,
                inX: p.inX !== undefined ? Number(p.inX) : px,
                inY: p.inY !== undefined ? Number(p.inY) : py,
                outX: p.outX !== undefined ? Number(p.outX) : px,
                outY: p.outY !== undefined ? Number(p.outY) : py
            });
        }
        tool.active = out;
        tool.dragging = false;
        tool.dragIndex = -1;
        tool.sel = [];
        tool.hover = null;
        tool.editDrag = null;
        tool.hasCursor = false;
        tool.clearPreviewGuides();
    }

    function svgFor(parts, rubber) {
        var d = "";
        for (var s = 0; s < (parts || []).length; s++) {
            var sub = parts[s] || {};
            var pts = sub.pts || [];
            if (pts.length === 0)
                continue;
            var first = pts[0] || {};
            d += (d === "" ? "M " : " M ") + (Number(first.x) || 0) + "," + (Number(first.y) || 0);
            for (var i = 1; i < pts.length; i++)
                d += tool.segSvg(pts[i - 1], pts[i]);
            if (sub.closed === true && pts.length > 1)
                d += tool.segSvg(pts[pts.length - 1], pts[0]) + " Z";
        }
        if (!rubber || tool.active.length === 0 || tool.dragging || tool.editDrag)
            return d;
        if (tool.previewActive) {
            var tip = tool.active[tool.active.length - 1] || {};
            d += (d === "" ? "M " : " M ") + (Number(tip.x) || 0) + "," + (Number(tip.y) || 0);
            d += tool.segSvg(tip, {
                x: tool.snCX,
                y: tool.snCY,
                smooth: false
            });
        }
        return d;
    }

    function segSvg(a, b) {
        var ax = Number(a.x) || 0, ay = Number(a.y) || 0;
        var bx = Number(b.x) || 0, by = Number(b.y) || 0;
        var aSmooth = a.smooth === true, bSmooth = b.smooth === true;
        if (!aSmooth && !bSmooth)
            return " L " + bx + "," + by;
        var c1x = aSmooth ? (a.outX !== undefined ? Number(a.outX) : ax) : ax;
        var c1y = aSmooth ? (a.outY !== undefined ? Number(a.outY) : ay) : ay;
        var c2x = bSmooth ? (b.inX !== undefined ? Number(b.inX) : bx) : bx;
        var c2y = bSmooth ? (b.inY !== undefined ? Number(b.inY) : by) : by;
        return " C " + c1x + "," + c1y + " " + c2x + "," + c2y + " " + bx + "," + by;
    }
}
