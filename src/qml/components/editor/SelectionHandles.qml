import QtQuick
import Totm

// Resize handles for the selection bounding box (corners + side
// midpoints, Figma style). Screen-space overlay: fills the canvas
// viewport and draws everything in whole screen pixels, so the frame
// and handles stay razor sharp and glide smoothly at any zoom or pan.
// (Positioning through the scaled content transform would leave them
// on fractional screen pixels, swimming and shimmering.)
// Pointer positions are mapped back to content coords before reaching
// the canvas resize policy (absolute-from-press, whole-pixel results).
// Static handle items (no Repeater) so member access stays statically
// resolvable for qmllint.
Item {
    id: handles

    anchors.fill: parent

    property var box: null
    property real zoom: 1
    property real offsetX: 0
    property real offsetY: 0
    property bool handlesActive: false
    // Bbox frame is redundant for a single unrotated shape (its own
    // selection outline already shows); the canvas hides it there.
    property bool showFrame: true

    // Snapped bbox edges in canvas coords: each edge rounded on screen
    // (not the size), so both sides land on whole screen pixels.
    readonly property real sbx: handles.box ? Math.round(handles.offsetX + handles.box.x * handles.zoom) : 0
    readonly property real sby: handles.box ? Math.round(handles.offsetY + handles.box.y * handles.zoom) : 0
    readonly property real sbr: handles.box ? Math.round(handles.offsetX + (handles.box.x + handles.box.w) * handles.zoom) : 0
    readonly property real sbb: handles.box ? Math.round(handles.offsetY + (handles.box.y + handles.box.h) * handles.zoom) : 0
    readonly property real smx: Math.round((handles.sbx + handles.sbr) / 2)
    readonly property real smy: Math.round((handles.sby + handles.sbb) / 2)

    // Resize policy callbacks, assigned by the canvas (same pattern as
    // ShapeItem: plain assignments wired outside, never outer ids in
    // the Handle component below).
    property var pressPolicy: null
    property var movePolicy: null
    property var releasePolicy: null
    property var doublePolicy: null

    visible: handles.box !== null && handles.handlesActive

    component Handle: Item {
        id: h

        property string hid: ""
        property real cx: 0
        property real cy: 0
        property real hzoom: 1
        property real hox: 0
        property real hoy: 0
        property int cursor: Qt.ArrowCursor
        property var hpress: null
        property var hmove: null
        property var hrelease: null
        // Double-click on a handle (the second press of a shape
        // double-click often lands here once handles pop up around the
        // fresh selection): the canvas cancels the accidental resize and
        // drills into the leaf under the point instead.
        property var hdouble: null

        // Fixed screen sizes: 8px dot, generous 18px grab area.
        readonly property real hit: 18
        readonly property real dot: 8

        function toCX(px) {
            var z = h.hzoom > 0 ? h.hzoom : 1;
            return (px - h.hox) / z;
        }
        function toCY(py) {
            var z = h.hzoom > 0 ? h.hzoom : 1;
            return (py - h.hoy) / z;
        }

        x: h.cx - h.hit / 2
        y: h.cy - h.hit / 2
        width: h.hit
        height: h.hit

        Rectangle {
            x: (h.hit - h.dot) / 2
            y: (h.hit - h.dot) / 2
            width: h.dot
            height: h.dot
            color: "#ffffff"
            border.width: 1
            border.color: AppTheme.selection
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: h.cursor
            onPressed: event => {
                if (h.hpress)
                    h.hpress(h.hid, h.toCX(h.x + event.x), h.toCY(h.y + event.y), event.modifiers);
                event.accepted = true;
            }
            onPositionChanged: event => {
                if (pressed && h.hmove)
                    h.hmove(h.toCX(h.x + event.x), h.toCY(h.y + event.y), event.modifiers);
            }
            onReleased: {
                if (h.hrelease)
                    h.hrelease();
            }
            onDoubleClicked: event => {
                if (h.hdouble)
                    h.hdouble(h.hid, h.toCX(h.x + event.x), h.toCY(h.y + event.y), event.modifiers);
            }
        }
    }

    // Selection bbox frame (per-shape outlines still show underneath).
    Rectangle {
        x: handles.sbx
        y: handles.sby
        width: handles.sbr - handles.sbx
        height: handles.sbb - handles.sby
        visible: handles.showFrame
        color: "transparent"
        border.width: 1
        border.color: AppTheme.selection
    }

    Handle {
        hid: "nw"
        cursor: Qt.SizeFDiagCursor
        cx: handles.sbx
        cy: handles.sby
        hzoom: handles.zoom
        hox: handles.offsetX
        hoy: handles.offsetY
        hpress: handles.pressPolicy
        hmove: handles.movePolicy
        hrelease: handles.releasePolicy
        hdouble: handles.doublePolicy
    }
    Handle {
        hid: "n"
        cursor: Qt.SizeVerCursor
        cx: handles.smx
        cy: handles.sby
        hzoom: handles.zoom
        hox: handles.offsetX
        hoy: handles.offsetY
        hpress: handles.pressPolicy
        hmove: handles.movePolicy
        hrelease: handles.releasePolicy
        hdouble: handles.doublePolicy
    }
    Handle {
        hid: "ne"
        cursor: Qt.SizeBDiagCursor
        cx: handles.sbr
        cy: handles.sby
        hzoom: handles.zoom
        hox: handles.offsetX
        hoy: handles.offsetY
        hpress: handles.pressPolicy
        hmove: handles.movePolicy
        hrelease: handles.releasePolicy
        hdouble: handles.doublePolicy
    }
    Handle {
        hid: "e"
        cursor: Qt.SizeHorCursor
        cx: handles.sbr
        cy: handles.smy
        hzoom: handles.zoom
        hox: handles.offsetX
        hoy: handles.offsetY
        hpress: handles.pressPolicy
        hmove: handles.movePolicy
        hrelease: handles.releasePolicy
        hdouble: handles.doublePolicy
    }
    Handle {
        hid: "se"
        cursor: Qt.SizeFDiagCursor
        cx: handles.sbr
        cy: handles.sbb
        hzoom: handles.zoom
        hox: handles.offsetX
        hoy: handles.offsetY
        hpress: handles.pressPolicy
        hmove: handles.movePolicy
        hrelease: handles.releasePolicy
        hdouble: handles.doublePolicy
    }
    Handle {
        hid: "s"
        cursor: Qt.SizeVerCursor
        cx: handles.smx
        cy: handles.sbb
        hzoom: handles.zoom
        hox: handles.offsetX
        hoy: handles.offsetY
        hpress: handles.pressPolicy
        hmove: handles.movePolicy
        hrelease: handles.releasePolicy
        hdouble: handles.doublePolicy
    }
    Handle {
        hid: "sw"
        cursor: Qt.SizeBDiagCursor
        cx: handles.sbx
        cy: handles.sbb
        hzoom: handles.zoom
        hox: handles.offsetX
        hoy: handles.offsetY
        hpress: handles.pressPolicy
        hmove: handles.movePolicy
        hrelease: handles.releasePolicy
        hdouble: handles.doublePolicy
    }
    Handle {
        hid: "w"
        cursor: Qt.SizeHorCursor
        cx: handles.sbx
        cy: handles.smy
        hzoom: handles.zoom
        hox: handles.offsetX
        hoy: handles.offsetY
        hpress: handles.pressPolicy
        hmove: handles.movePolicy
        hrelease: handles.releasePolicy
        hdouble: handles.doublePolicy
    }
}
