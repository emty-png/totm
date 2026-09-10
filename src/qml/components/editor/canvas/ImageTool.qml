import QtQuick
import Totm

// Image placement drags for one canvas. Picker-then-place: the canvas
// imports a blob first (pendingImage), then click stamps natural size
// and drag stretches to the box. Draft preview lives here; the shared
// size readout stays on the canvas like the shape flow.
QtObject {
    id: tool

    required property var canvas
    required property var snap

    property string pendingImage: ""
    property real pendingW: 0
    property real pendingH: 0
    property var draft: null

    property real startCX: 0
    property real startCY: 0
    property real startSX: 0
    property real startSY: 0
    property bool moved: false

    function hasPending() {
        return tool.pendingImage !== "";
    }

    function setPending(name, w, h) {
        tool.pendingImage = String(name);
        tool.pendingW = Math.max(1, Math.round(w || 400));
        tool.pendingH = Math.max(1, Math.round(h || 300));
        tool.draft = null;
        tool.moved = false;
    }

    function clearPending() {
        tool.pendingImage = "";
        tool.pendingW = 0;
        tool.pendingH = 0;
        tool.clearPreview();
    }

    function toCX(px) {
        var z = tool.canvas.zoom > 0 ? tool.canvas.zoom : 1;
        return (px - tool.canvas.offsetX) / z;
    }

    function toCY(py) {
        var z = tool.canvas.zoom > 0 ? tool.canvas.zoom : 1;
        return (py - tool.canvas.offsetY) / z;
    }

    function pressAt(sx, sy, mods) {
        var c = tool.canvas;
        if (!c.doc || !tool.hasPending())
            return;
        c.forceActiveFocus();
        c.commitTextEdit();
        c.altHeld = !!(mods & Qt.AltModifier);
        var rawCX = tool.toCX(sx);
        var rawCY = tool.toCY(sy);
        var sp = tool.snap.snapPoint(c.doc, rawCX, rawCY, c.zoom);
        tool.startCX = sp.x;
        tool.startCY = sp.y;
        tool.startSX = sx;
        tool.startSY = sy;
        tool.moved = false;
        tool.draft = null;
        c.measureBox = null;
        c.snapXGuides = [];
        c.snapYGuides = [];
    }

    function moveTo(sx, sy, mods, pressed) {
        var c = tool.canvas;
        if (!pressed || !tool.hasPending())
            return;
        var cx = tool.toCX(sx);
        var cy = tool.toCY(sy);
        if (!tool.moved && Math.hypot(sx - tool.startSX, sy - tool.startSY) < 4)
            return;
        tool.moved = true;
        if (c.doc && !c.altHeld && !(mods & Qt.AltModifier)) {
            var snapped = tool.snap.snapCreate(c.doc, tool.startCX, tool.startCY, cx, cy, c.zoom);
            cx = snapped.x;
            cy = snapped.y;
            c.snapXGuides = snapped.xGuides;
            c.snapYGuides = snapped.yGuides;
        } else {
            c.snapXGuides = [];
            c.snapYGuides = [];
        }
        var x0 = Math.min(tool.startCX, cx);
        var y0 = Math.min(tool.startCY, cy);
        var x1 = Math.max(tool.startCX, cx);
        var y1 = Math.max(tool.startCY, cy);
        tool.draft = {
            type: "image",
            x: x0,
            y: y0,
            w: Math.max(1, x1 - x0),
            h: Math.max(1, y1 - y0)
        };
        c.cursorX = sx;
        c.cursorY = sy;
        c.measureBox = {
            w: tool.draft.w,
            h: tool.draft.h
        };
    }

    function releaseAt() {
        var c = tool.canvas;
        if (!c.doc || !tool.hasPending()) {
            tool.clearPreview();
            return;
        }
        if (!tool.moved) {
            var w = tool.pendingW;
            var h = tool.pendingH;
            c.doc.addImage(tool.pendingImage, Math.round(tool.startCX - w / 2), Math.round(tool.startCY - h / 2), w, h);
        } else if (tool.draft) {
            var d = tool.draft;
            c.doc.addImage(tool.pendingImage, d.x, d.y, d.w, d.h);
        }
        tool.clearPending();
        ToolState.setActiveTool("select");
    }

    function clearPreview() {
        var c = tool.canvas;
        tool.draft = null;
        if (c) {
            c.measureBox = null;
            c.snapXGuides = [];
            c.snapYGuides = [];
        }
    }
}
