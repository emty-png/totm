import QtQuick
import Totm

// Asset placement for one canvas. Gallery-then-place: the toolbar
// gallery arms a pending asset id, then click stamps the detached copy
// centered on the cursor. No stretch (assets keep intrinsic bbox size;
// move/scale after with the select tool). Draft preview stays empty;
// the shared size readout is untouched.
QtObject {
    id: tool

    required property var canvas
    required property var snap

    property string pendingAssetId: ""
    property real startCX: 0
    property real startCY: 0

    function hasPending() {
        return tool.pendingAssetId !== "";
    }

    function setPending(assetId) {
        tool.pendingAssetId = String(assetId);
        tool.startCX = 0;
        tool.startCY = 0;
    }

    function clearPending() {
        tool.pendingAssetId = "";
        tool.startCX = 0;
        tool.startCY = 0;
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
        var rawCX = tool.toCX(sx);
        var rawCY = tool.toCY(sy);
        var sp = tool.snap.snapPoint(c.doc, rawCX, rawCY, c.zoom);
        tool.startCX = sp.x;
        tool.startCY = sp.y;
    }

    function releaseAt() {
        var c = tool.canvas;
        if (!c.doc || !tool.hasPending())
            return;
        var payload = LibraryStore.loadAsset(tool.pendingAssetId);
        if (payload && (payload.nodes || []).length > 0)
            c.doc.insertAsset(payload, Math.round(tool.startCX), Math.round(tool.startCY));
        tool.clearPending();
        ToolState.setActiveTool("select");
    }
}
