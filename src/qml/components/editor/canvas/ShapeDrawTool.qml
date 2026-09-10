import QtQuick
import Totm

// Shape/text creation drags for one canvas. Drag draws (snapped unless
// Alt); release commits, click stamps a default. Text creation routes
// through the text editor (sizing + inline edit). Draft preview state
// lives here for the overlays; the shared size readout
// (measureBox/cursor) stays on the canvas like the resize flow's.
QtObject {
    id: tool

    required property var canvas
    required property var snap
    required property var textEdit

    property var draft: null

    property real startCX: 0
    property real startCY: 0
    property real startSX: 0
    property real startSY: 0
    property bool moved: false

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
        if (!c.doc)
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
        if (!pressed)
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
            type: ToolState.activeTool === "text" ? "text" : ToolState.activeShapeType,
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
        if (!c.doc) {
            tool.clearPreview();
            return;
        }
        if (!tool.moved) {
            if (ToolState.activeTool === "text")
                tool.textEdit.createText(Math.round(tool.startCX), Math.round(tool.startCY), 0, 0, true);
            else
                c.doc.addShape(ToolState.activeShapeType, Math.round(tool.startCX - 50), Math.round(tool.startCY - 50), 100, 100);
        } else if (tool.draft) {
            var d = tool.draft;
            if (ToolState.activeTool === "text")
                tool.textEdit.createText(d.x, d.y, d.w, d.h, false);
            else
                c.doc.addShape(d.type, d.x, d.y, d.w, d.h);
        }
        tool.clearPreview();
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
