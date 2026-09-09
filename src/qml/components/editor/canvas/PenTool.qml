import QtQuick

// Pen drawing state for one canvas. Click adds corners, drag makes
// symmetric smooth points, click-first closes, Enter commits a part,
// Esc/double-click finishes the node. Single dots never become shapes:
// subpaths under 2 points are dropped on commit. Snaps via SnapEngine;
// Alt frees. Session holds finished parts so one node can carry
// holes/multi-paths.
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
    // Snapped preview endpoint (content coords). Raw cursor stays in
    // cursorCX/CY for handle math; rubber + ghost read snCX/snCY so the
    // preview is WYSIWYG with the next click.
    property real snCX: 0
    property real snCY: 0

    readonly property bool hasWork: tool.session.length > 0 || tool.active.length > 0
    // Figma-style rubber visible once a first anchor exists, hidden
    // while dragging handles and over the close target.
    readonly property bool previewActive: tool.active.length > 0 && tool.hasCursor && !tool.dragging && !tool.hoverClose
    // Closing preview: hovering the first anchor shows last-to-first so
    // the close click reads before committing. Ghost stays off — the
    // cursor already sits on the swollen first point.
    readonly property bool closePreview: tool.hoverClose && tool.active.length > 1 && !tool.dragging

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
        tool.updatePreview(sx, sy, mods);
    }

    // Shared hover/preview update: raw cursor in, snapped endpoint out,
    // snap guides pushed to the canvas so CanvasOverlays paints them.
    // Stays silent before the first anchor (no rubber, no guides).
    function updatePreview(sx, sy, mods) {
        var rawX = tool.toCX(sx);
        var rawY = tool.toCY(sy);
        tool.cursorCX = rawX;
        tool.cursorCY = rawY;
        tool.hasCursor = true;
        var sp = tool.snapped(rawX, rawY, mods);
        tool.snCX = sp.x;
        tool.snCY = sp.y;
        tool.hoverClose = tool.isCloseHit(sp.x, sp.y);
        var c = tool.canvas;
        if (!c)
            return;
        if (tool.active.length === 0 || tool.dragging || tool.hoverClose) {
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

    // Cursor left the canvas: hide rubber + ghost, drop stale guides.
    // Session/active stay so re-entering resumes the sketch.
    function exitHover() {
        tool.hasCursor = false;
        tool.hoverClose = false;
        tool.clearPreviewGuides();
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
            tool.clearPreviewGuides();
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
        tool.snCX = sp.x;
        tool.snCY = sp.y;
        tool.hasCursor = true;
        tool.hoverClose = false;
        tool.clearPreviewGuides();
    }

    function moveTo(sx, sy, mods, pressed) {
        var c = tool.canvas;
        var rawX = tool.toCX(sx);
        var rawY = tool.toCY(sy);
        tool.cursorCX = rawX;
        tool.cursorCY = rawY;
        tool.hasCursor = true;
        if (!pressed || tool.dragIndex < 0 || tool.dragIndex >= tool.active.length)
            return;
        // Arm smooth once the drag leaves a 4px screen deadband.
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
        var sp = tool.snapped(rawX, rawY, mods);
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
        tool.snCX = sp.x;
        tool.snCY = sp.y;
        tool.setDragGuides(rawX, rawY, sp);
    }

    // Handle-tip snap guides mirror the hover preview so the drag reads
    // WYSIWYG; silent while free (Alt) or unsnapped.
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
        tool.clearPreviewGuides();
    }

    // Subpaths under 2 points paint nothing, so they never reach the
    // document (single click + Esc/Enter simply exits).
    function viableParts(parts) {
        var out = [];
        for (var i = 0; i < (parts || []).length; i++) {
            var sub = parts[i] || {};
            if ((sub.pts || []).length >= 2)
                out.push(sub);
        }
        return out;
    }

    function commitActive() {
        if (tool.active.length === 0)
            return false;
        if (tool.active.length < 2) {
            tool.active = [];
            tool.dragging = false;
            tool.dragIndex = -1;
            tool.hoverClose = false;
            tool.clearPreviewGuides();
            return false;
        }
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
        tool.clearPreviewGuides();
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
        parts = tool.viableParts(parts);
        if (parts.length === 0) {
            tool.session = [];
            tool.active = [];
            tool.dragging = false;
            tool.dragIndex = -1;
            tool.hoverClose = false;
            tool.clearPreviewGuides();
            return -1;
        }
        var uid = c.doc.addPen(parts);
        tool.session = [];
        tool.active = [];
        tool.dragging = false;
        tool.dragIndex = -1;
        tool.hoverClose = false;
        tool.clearPreviewGuides();
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
        tool.clearPreviewGuides();
    }

    // SVG for overlay preview in absolute content coords. Rubber reads
    // the snapped endpoint and stays off while dragging handles so the
    // live curve never grows a stray tail to the handle tip. Over the
    // close target the rubber yields to the closing segment (last anchor
    // back to first) so the click's result reads before committing.
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
        if (!rubber || tool.active.length === 0 || tool.dragging)
            return d;
        if (tool.hoverClose && tool.active.length > 1) {
            var last = tool.active[tool.active.length - 1] || {};
            var close = tool.active[0] || {};
            d += (d === "" ? "M " : " M ") + (Number(last.x) || 0) + "," + (Number(last.y) || 0);
            d += tool.segSvg(last, close);
            return d;
        }
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
