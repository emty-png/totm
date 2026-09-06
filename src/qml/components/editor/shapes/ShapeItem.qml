import QtQuick
import QtQuick.Shapes
import Totm

// One shape on the canvas. Root geometry IS the shape geometry
// (x/y/width/height/rotation bound from model roles by the repeater).
// Reports press/move/release; the canvas owns selection policy.
// Hidden shapes vanish entirely (no input); locked shapes render but
// swallow canvas presses without acting, so the marquee below never
// starts and selection policy stays untouched.
// Drag deltas are measured in window-stable global coords and forwarded
// in whole screen pixels (via zoom), so motion stays 1:1 smooth at any
// zoom - measuring in local coords would feed back as the item moves
// under the cursor and judder. Whole-pixel model snapping happens on
// release (see Document.snapSelection), never mid-gesture.
Item {
    id: shape

    // Model-bound props (set explicitly from roles, avoiding Item clashes).
    // NOTE: no `required` declarations for Repeater-injected names here —
    // they silently break sibling initializer bindings (verified).
    // Paint follows the sidebar order via depth (renumbered by the
    // document after every reorder); uid order must never drive paint.
    property int uid: -1
    property string shapeType: "rectangle"
    property real sx: 0
    property real sy: 0
    property real sw: 10
    property real sh: 10
    property real shapeRotation: 0
    property color fill: "#d9d9d9"
    property color strokeColor: "#000000"
    property real strokeWidth: 0
    property real shapeOpacity: 1
    property real radius: 0
    property bool selected: false
    property bool shapeVisible: true
    property bool shapeLocked: false
    property int paintDepth: 0
    property real zoom: 1

    // Selection policy callbacks, assigned by the canvas in onItemAdded
    // (calling item.customSignal() there would fail lint: onItemAdded's
    // item is statically QQuickItem, while plain assignments stay dynamic).
    property var activatePolicy: null
    property var pressPolicy: null
    property var movePolicy: null
    property var releasePolicy: null
    property var doublePolicy: null

    x: shape.sx
    y: shape.sy
    width: shape.sw
    height: shape.sh
    z: shape.paintDepth
    rotation: shape.shapeRotation
    transformOrigin: Item.Center
    visible: shape.shapeVisible

    // Rectangle: native item (radius + stroke border built in).
    Rectangle {
        anchors.fill: parent
        visible: shape.shapeType === "rectangle"
        color: shape.fill
        radius: shape.radius
        border.width: shape.strokeWidth
        border.color: shape.strokeWidth > 0 ? shape.strokeColor : "transparent"
        opacity: shape.shapeOpacity
    }

    // Other types: stroked/filled vector path (round joins, cute).
    Shape {
        anchors.fill: parent
        visible: shape.shapeType !== "rectangle"
        antialiasing: true
        opacity: shape.shapeOpacity
        ShapePath {
            fillColor: shape.fill
            strokeColor: shape.strokeWidth > 0 ? shape.strokeColor : "transparent"
            strokeWidth: shape.strokeWidth
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathSvg {
                path: shape.vectorPath()
            }
        }
    }

    // Selection outline: constant screen size at any zoom (Figma bbox).
    Rectangle {
        visible: shape.selected
        x: -3 / shape.zoom
        y: -3 / shape.zoom
        width: parent.width + 6 / shape.zoom
        height: parent.height + 6 / shape.zoom
        color: "transparent"
        border.width: 1.5 / shape.zoom
        border.color: AppTheme.selection
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: shape.shapeLocked ? Qt.ForbiddenCursor : shape.moving ? Qt.ClosedHandCursor : Qt.ArrowCursor

        onPressed: event => shape.pressAt(event.x, event.y, event.modifiers)
        onPositionChanged: event => shape.moveAt(event.x, event.y)
        onReleased: event => shape.releaseAt(event.modifiers)
        onDoubleClicked: {
            if (shape.doublePolicy)
                shape.doublePolicy(shape.uid);
        }
    }

    // Move state lives here so press/move/release stay consistent.
    // lastGX/lastGY anchor the drag in global coords (stable while the
    // item moves); remCX/remCY bank sub-screen-pixel motion in content
    // units so not a pixel of travel is ever lost and only whole screen
    // pixels move shapes (smooth at any zoom; the document snaps the
    // resting values to whole pixels on release).
    // `refused` marks a press on a locked shape: claimed (so the marquee
    // below never starts) but never touching selection policy.
    property bool moving: false
    property bool dragged: false
    property bool refused: false
    property real lastGX: 0
    property real lastGY: 0
    property real startGX: 0
    property real startGY: 0
    property real remCX: 0
    property real remCY: 0

    function vectorPath() {
        var w = shape.sw, h = shape.sh;
        switch (shape.shapeType) {
        case "ellipse":
            {
                var rx = w / 2, ry = h / 2;
                return "M " + w + "," + h / 2 + " A " + rx + "," + ry + " 0 1,0 0," + h / 2 + " A " + rx + "," + ry + " 0 1,0 " + w + "," + h / 2 + " Z";
            }
        case "triangle":
            return "M " + w / 2 + ",0 L " + w + "," + h + " L 0," + h + " Z";
        case "diamond":
            return "M " + w / 2 + ",0 L " + w + "," + h / 2 + " L " + w / 2 + "," + h + " L 0," + h / 2 + " Z";
        case "polygon":
            {
                var cx = w / 2, cy = h / 2, d = "";
                for (var i = 0; i < 6; i++) {
                    var a = -Math.PI / 2 + i * Math.PI / 3;
                    var px = cx + cx * Math.cos(a), py = cy + cy * Math.sin(a);
                    d += (i === 0 ? "M " : " L ") + px + "," + py;
                }
                return d + " Z";
            }
        default:
            return "";
        }
    }

    // Press/move/release entry points for the MouseArea above.
    function pressAt(x, y, modifiers) {
        var g = mouse.mapToGlobal(x, y);
        shape.moving = true;
        shape.dragged = false;
        shape.refused = shape.shapeLocked;
        shape.lastGX = g.x;
        shape.lastGY = g.y;
        shape.startGX = g.x;
        shape.startGY = g.y;
        shape.remCX = 0;
        shape.remCY = 0;
        if (shape.refused) {
            if (shape.activatePolicy)
                shape.activatePolicy();
            return;
        }
        if (shape.activatePolicy)
            shape.activatePolicy();
        if (shape.pressPolicy)
            shape.pressPolicy(shape.uid, modifiers);
    }

    function moveAt(x, y) {
        if (!shape.moving || shape.refused)
            return;
        var g = mouse.mapToGlobal(x, y);
        var z = shape.zoom > 0 ? shape.zoom : 1;
        var rawX = (g.x - shape.lastGX) / z, rawY = (g.y - shape.lastGY) / z;
        if (rawX === 0 && rawY === 0)
            return;
        shape.lastGX = g.x;
        shape.lastGY = g.y;
        if (Math.hypot(g.x - shape.startGX, g.y - shape.startGY) >= 4)
            shape.dragged = true;
        // Bank the fractional travel, forward only whole screen pixels.
        shape.remCX += rawX;
        shape.remCY += rawY;
        var scrX = shape.remCX * z, scrY = shape.remCY * z;
        var stepSX = scrX > 0 ? Math.floor(scrX) : Math.ceil(scrX);
        var stepSY = scrY > 0 ? Math.floor(scrY) : Math.ceil(scrY);
        if (stepSX === 0 && stepSY === 0)
            return;
        shape.remCX -= stepSX / z;
        shape.remCY -= stepSY / z;
        shape.dragged = true;
        if (shape.movePolicy)
            shape.movePolicy(stepSX / z, stepSY / z);
    }

    function releaseAt(modifiers) {
        if (!shape.moving)
            return;
        shape.moving = false;
        if (shape.refused) {
            shape.refused = false;
            return;
        }
        if (shape.releasePolicy)
            shape.releasePolicy(shape.dragged, modifiers);
    }
}
