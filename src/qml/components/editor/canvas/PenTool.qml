import QtQuick

// Pen drawing state for one canvas. Click adds corners, drag makes
// symmetric smooth points, click-first closes, Enter commits a part,
// Esc/double-click finishes the node. Snaps via SnapEngine; Alt frees.
// Session holds finished parts so one node can carry holes/multi-paths.
QtObject {
    id: tool

    required property var canvas
    required property var snap

    property var session: []
    property var active: []
    property bool dragging: false
    property int dragIndex: -1
    property real pressCX: 0
    property real pressCY: 0
    property real pressSX: 0
    property real pressSY: 0
    property real cursorCX: 0
    property real cursorCY: 0
    property bool hoverClose: false
    property bool hasCursor: false

    readonly property bool hasWork: tool.session.length > 0 || tool.active.length > 0

    function toCX(px) {
        var z = tool.canvas.zoom > 0 ? tool.canvas.zoom : 1;
        return (px - tool.canvas.offsetX) / z;
    }

    function toCY(py) {
        var z = tool.canvas.zoom > 0 ? tool.canvas.zoom : 1;
        return (py - tool.canvas.offsetY) / z;
    }

    function closeRadius() {
        var z = tool.canvas.zoom > 0 ? tool.canvas.zoom : 1;
        return 8 / z;
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

    function isCloseHit(cx, cy) {
        if (tool.active.length < 2)
            return false;
        var f = tool.active[0] || {};
        return Math.hypot(cx - (Number(f.x) || 0), cy - (Number(f.y) || 0)) <= tool.closeRadius();
    }

    function refreshHover(sx, sy, mods) {
        tool.cursorCX = tool.toCX(sx);
        tool.cursorCY = tool.toCY(sy);
        tool.hasCursor = true;
        var sp = tool.snapped(tool.cursorCX, tool.cursorCY, mods);
        tool.hoverClose = tool.isCloseHit(sp.x, sp.y);
    }

    function pressAt(sx, sy, mods) {
        var c = tool.canvas;
        if (!c.doc)
            return;
        c.forceActiveFocus();
        c.commitTextEdit();
        c.altHeld = !!(mods & Qt.AltModifier);
        var rawCX = tool.toCX(sx);
        var rawCY = tool.toCY(sy);
        var sp = tool.snapped(rawCX, rawCY, mods);
        // Close click finishes the part without adding a point.
        if (tool.isCloseHit(sp.x, sp.y)) {
            var closed = {
                closed: true,
                pts: tool.active.slice()
            };
            var next = tool.session.slice();
            next.push(closed);
            tool.session = next;
            tool.active = [];
            tool.dragging = false;
            tool.dragIndex = -1;
            tool.hoverClose = false;
            return;
        }
        var pts = tool.active.slice();
        pts.push({
            x: sp.x,
            y: sp.y,
            smooth: false,
            inX: sp.x,
            inY: sp.y,
            outX: sp.x,
            outY: sp.y
        });
        tool.active = pts;
        tool.dragging = false;
        tool.dragIndex = pts.length - 1;
        tool.pressCX = sp.x;
        tool.pressCY = sp.y;
        tool.pressSX = sx;
        tool.pressSY = sy;
        tool.cursorCX = sp.x;
        tool.cursorCY = sp.y;
        tool.hasCursor = true;
        tool.hoverClose = false;
    }

    function moveTo(sx, sy, mods, pressed) {
        var c = tool.canvas;
        tool.cursorCX = tool.toCX(sx);
        tool.cursorCY = tool.toCY(sy);
        tool.hasCursor = true;
        if (!pressed || tool.dragIndex < 0 || tool.dragIndex >= tool.active.length)
            return;
        // Arm smooth once the drag leaves a 4px screen deadband.
        if (!tool.dragging && Math.hypot(sx - tool.pressSX, sy - tool.pressSY) < 4) {
            var sp0 = tool.snapped(tool.cursorCX, tool.cursorCY, mods);
            tool.cursorCX = sp0.x;
            tool.cursorCY = sp0.y;
            return;
        }
        tool.dragging = true;
        var sp = tool.snapped(tool.cursorCX, tool.cursorCY, mods);
        var vx = sp.x - tool.pressCX;
        var vy = sp.y - tool.pressCY;
        var pts = tool.active.slice();
        var p = pts[tool.dragIndex] || {};
        pts[tool.dragIndex] = {
            x: tool.pressCX,
            y: tool.pressCY,
            smooth: true,
            inX: tool.pressCX - vx,
            inY: tool.pressCY - vy,
            outX: tool.pressCX + vx,
            outY: tool.pressCY + vy
        };
        tool.active = pts;
        tool.cursorCX = sp.x;
        tool.cursorCY = sp.y;
    }

    function releaseAt() {
        tool.dragging = false;
        tool.dragIndex = -1;
    }

    function commitActive() {
        if (tool.active.length === 0)
            return false;
        var next = tool.session.slice();
        next.push({
            closed: false,
            pts: tool.active.slice()
        });
        tool.session = next;
        tool.active = [];
        tool.dragging = false;
        tool.dragIndex = -1;
        tool.hoverClose = false;
        return true;
    }

    function createNode() {
        var c = tool.canvas;
        if (!c.doc)
            return -1;
        var parts = tool.session.slice();
        if (tool.active.length > 0) {
            parts.push({
                closed: false,
                pts: tool.active.slice()
            });
        }
        if (parts.length === 0)
            return -1;
        var uid = c.doc.addPen(parts);
        tool.session = [];
        tool.active = [];
        tool.dragging = false;
        tool.dragIndex = -1;
        tool.hoverClose = false;
        return uid;
    }

    // Enter finishes one part so the next click starts a new subpath
    // in the same node; with no active part it finishes the node.
    function enterCommit() {
        if (tool.active.length > 0)
            return tool.commitActive();
        if (tool.session.length > 0) {
            tool.createNode();
            return true;
        }
        return false;
    }

    // Double-click finishes the whole node for fast single paths.
    function doubleAt() {
        if (tool.active.length > 0 || tool.session.length > 0) {
            tool.createNode();
            return true;
        }
        return false;
    }

    // Esc finishes the node and leaves the tool; empty session just exits.
    function escapeFinish() {
        if (!tool.hasWork)
            return false;
        tool.createNode();
        return true;
    }

    function cancel() {
        tool.session = [];
        tool.active = [];
        tool.dragging = false;
        tool.dragIndex = -1;
        tool.hoverClose = false;
        tool.hasCursor = false;
    }

    // SVG for overlay preview in absolute content coords.
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
        if (rubber && tool.active.length > 0 && tool.hasCursor && !tool.hoverClose) {
            var last = tool.active[tool.active.length - 1] || {};
            d += (d === "" ? "M " : " M ") + (Number(last.x) || 0) + "," + (Number(last.y) || 0);
            d += tool.segSvg(last, {
                x: tool.cursorCX,
                y: tool.cursorCY,
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
