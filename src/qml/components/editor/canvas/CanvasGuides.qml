import QtQuick
import Totm

// Canvas guides (Figma-style, minus the ruler chrome). Guides are the
// persistent, snappable lines; the canvas edges are their handle:
// hovering the top/left 12px shows a split cursor, dragging out pulls
// a guide onto the canvas, dragging a guide moves it, releasing home
// or double-clicking a guide removes it. Guides persist with the scene
// (doc.guideX/guideY) and feed SnapTargets, so moves, resizes and
// draws snap to them like edges.
// Drags never write the doc mid-gesture (wholesale reassigns would
// rebuild the guide delegates under the pressed MouseArea): the host
// owns dragAxis/dragIndex/dragPos, delegates render the override, and
// release commits once via moveGuide.
Item {
    id: guides

    anchors.fill: parent
    visible: guides.doc !== null

    required property var doc
    required property real zoom
    required property real offsetX
    required property real offsetY

    // Invisible grab depth along the top/left edges.
    readonly property real edge: 12

    // Active guide drag (edge creation or guide move). dragPos is
    // content px along the drag axis.
    property bool dragActive: false
    property string dragAxis: "x"
    property int dragIndex: -1
    property real dragPos: 0

    function toContentX(sx) {
        return (sx - guides.offsetX) / (guides.zoom > 0 ? guides.zoom : 1);
    }

    function toContentY(sy) {
        return (sy - guides.offsetY) / (guides.zoom > 0 ? guides.zoom : 1);
    }

    function toScreenX(cx) {
        return Math.round(guides.offsetX + cx * guides.zoom);
    }

    function toScreenY(cy) {
        return Math.round(guides.offsetY + cy * guides.zoom);
    }

    function guidePosX(i) {
        if (guides.dragActive && guides.dragAxis === "x" && guides.dragIndex === i)
            return guides.dragPos;
        return Number(guides.doc.guideX[i]) || 0;
    }

    function guidePosY(i) {
        if (guides.dragActive && guides.dragAxis === "y" && guides.dragIndex === i)
            return guides.dragPos;
        return Number(guides.doc.guideY[i]) || 0;
    }

    function beginEdgeDrag(axis, sx, sy) {
        if (!guides.doc)
            return;
        var pos = axis === "x" ? guides.toContentX(sx) : guides.toContentY(sy);
        guides.dragAxis = axis;
        guides.dragIndex = guides.doc.addGuide(axis, pos);
        guides.dragPos = Math.round(Number(pos) || 0);
        guides.dragActive = true;
    }

    function beginGuideDrag(axis, index) {
        guides.dragAxis = axis;
        guides.dragIndex = index;
        guides.dragPos = axis === "x" ? guides.guidePosX(index) : guides.guidePosY(index);
        guides.dragActive = true;
    }

    function moveDrag(sx, sy) {
        if (!guides.dragActive)
            return;
        guides.dragPos = Math.round(guides.dragAxis === "x" ? guides.toContentX(sx) : guides.toContentY(sy));
    }

    // Release commits the move — inside either edge deletes instead,
    // so dragging a guide home removes it like creation-cancel.
    function endDrag(sx, sy) {
        if (!guides.dragActive || !guides.doc)
            return;
        var d = guides.doc;
        var axis = guides.dragAxis, index = guides.dragIndex, pos = guides.dragPos;
        guides.dragActive = false;
        guides.dragIndex = -1;
        if (sx < guides.edge || sy < guides.edge)
            d.removeGuide(axis, index);
        else
            d.moveGuide(axis, index, pos);
    }

    // Guide lines.
    Repeater {
        model: guides.doc ? guides.doc.guideX : []

        Rectangle {
            x: guides.toScreenX(guides.guidePosX(index))
            y: 0
            width: 1
            height: guides.height
            color: AppTheme.selection
        }
    }

    Repeater {
        model: guides.doc ? guides.doc.guideY : []

        Rectangle {
            x: 0
            y: guides.toScreenY(guides.guidePosY(index))
            width: guides.width
            height: 1
            color: AppTheme.selection
        }
    }

    // Invisible edge grab zones, below the guide hits so a guide
    // under the cursor wins over creating a new one.
    MouseArea {
        x: 0
        y: 0
        width: parent.width
        height: guides.edge
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.SizeHorCursor
        onPressed: event => guides.beginEdgeDrag("x", event.x, event.y)
        onPositionChanged: event => {
            var p = mapToItem(guides, event.x, event.y);
            guides.moveDrag(p.x, p.y);
        }
        onReleased: event => {
            var p = mapToItem(guides, event.x, event.y);
            guides.endDrag(p.x, p.y);
        }
    }

    MouseArea {
        x: 0
        y: 0
        width: guides.edge
        height: parent.height
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.SizeVerCursor
        onPressed: event => guides.beginEdgeDrag("y", event.x, event.y)
        onPositionChanged: event => {
            var p = mapToItem(guides, event.x, event.y);
            guides.moveDrag(p.x, p.y);
        }
        onReleased: event => {
            var p = mapToItem(guides, event.x, event.y);
            guides.endDrag(p.x, p.y);
        }
    }

    // Guide hit areas: wide transparent grabs over the 1px lines.
    // Move/release ride the press owner (Qt keeps the grab there).
    Repeater {
        model: guides.doc ? guides.doc.guideX : []

        MouseArea {
            x: guides.toScreenX(guides.guidePosX(index)) - 4
            y: 0
            width: 9
            height: guides.height
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            onPressed: guides.beginGuideDrag("x", index)
            onPositionChanged: event => {
                var p = mapToItem(guides, event.x, event.y);
                guides.moveDrag(p.x, p.y);
            }
            onReleased: event => {
                var p = mapToItem(guides, event.x, event.y);
                guides.endDrag(p.x, p.y);
            }
            onDoubleClicked: {
                if (guides.doc)
                    guides.doc.removeGuide("x", index);
            }
        }
    }

    Repeater {
        model: guides.doc ? guides.doc.guideY : []

        MouseArea {
            x: 0
            y: guides.toScreenY(guides.guidePosY(index)) - 4
            width: guides.width
            height: 9
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.SizeVerCursor
            onPressed: guides.beginGuideDrag("y", index)
            onPositionChanged: event => {
                var p = mapToItem(guides, event.x, event.y);
                guides.moveDrag(p.x, p.y);
            }
            onReleased: event => {
                var p = mapToItem(guides, event.x, event.y);
                guides.endDrag(p.x, p.y);
            }
            onDoubleClicked: {
                if (guides.doc)
                    guides.doc.removeGuide("y", index);
            }
        }
    }
}
