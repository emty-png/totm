import QtQuick
import Totm

// Infinite canvas. Wheel pans, Ctrl-wheel zooms to cursor, Space-drag pans.
// Select-drag marquees, shapes-drag draws, handles resize the selection.
// Moves, resizes and creations snap within 5 screen px; Alt suspends.
// Hidden skips input, locked swallows presses. See docs/canvas-interactions.md.
Item {
    id: canvas

    property real zoom: 1
    readonly property real minZoom: 0.02
    readonly property real maxZoom: 16
    property real offsetX: 0
    property real offsetY: 0
    property bool spaceHeld: false
    property bool panning: false

    property var doc: null
    property var shownDoc: null
    onDocChanged: canvas.showDocument(canvas.doc)

    property var draft: null

    property int clickArmedUid: -1
    property bool moveAllowed: false
    property bool marqueeDragged: false

    property var selBox: canvas.doc ? canvas.doc.selectionBBox() : null

    property var resizeState: null

    property var snapXGuides: []
    property var snapYGuides: []

    property bool altHeld: false

    SnapEngine {
        id: snapEngine
    }

    property var camera: CanvasCamera {
        canvas: canvas
    }
    property var selectPolicy: CanvasSelectPolicy {
        canvas: canvas
        snap: snapEngine
    }
    property var resizePolicy: CanvasResizePolicy {
        canvas: canvas
        snap: snapEngine
    }

    focus: true
    clip: true

    onWidthChanged: canvas.showDocument(canvas.doc)
    onHeightChanged: canvas.showDocument(canvas.doc)

    Rectangle {
        anchors.fill: parent
        color: AppTheme.canvas
    }

    DragSelection {
        id: marquee
        onStarted: canvas.marqueeDragged = true
        onFinished: (area, additive) => canvas.applyMarquee(area, additive)
    }

    MouseArea {
        id: marqueeMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        enabled: ToolStore.activeTool !== "shapes"

        onPressed: event => {
            canvas.forceActiveFocus();
            canvas.marqueeDragged = false;
            marquee.pressAt(event.x, event.y);
        }
        onPositionChanged: event => {
            if (pressed)
                marquee.moveTo(event.x, event.y);
        }
        onReleased: event => {
            marquee.release(!!(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.MetaModifier)));
        }
        onClicked: event => {
            if (!canvas.marqueeDragged && !(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.MetaModifier)) && canvas.doc)
                canvas.doc.clearSelection();
        }
    }

    ShapeLayer {
        doc: canvas.doc
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
        activatePolicy: () => canvas.forceActiveFocus()
        pressPolicy: (uid, mods) => canvas.shapePressed(uid, mods)
        movePolicy: (dx, dy) => canvas.shapeMoved(dx, dy)
        releasePolicy: (wasMoved, mods) => canvas.shapeReleased(wasMoved, mods)
        doublePolicy: uid => canvas.shapeDoubleClicked(uid)
    }

    SelectionHandles {
        box: canvas.selBox
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
        handlesActive: ToolStore.activeTool === "select" && canvas.doc !== null
        showFrame: canvas.selBox ? (canvas.selBox.count > 1 || canvas.selBox.rotated || canvas.selBox.singleGroup) : false
        pressPolicy: (hid, cx, cy, mods) => canvas.resizePressed(hid, cx, cy, mods)
        movePolicy: (cx, cy, mods) => canvas.resizeMoved(cx, cy, mods)
        releasePolicy: () => canvas.resizeReleased()
        doublePolicy: (hid, cx, cy, mods) => canvas.handleDoubleClicked(cx, cy, mods)
    }

    MouseArea {
        id: drawMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        enabled: ToolStore.activeTool === "shapes" && canvas.doc !== null

        property real startCX: 0
        property real startCY: 0
        property real startSX: 0
        property real startSY: 0
        property bool moved: false

        function toContentX(px) {
            return (px - canvas.offsetX) / canvas.zoom;
        }
        function toContentY(py) {
            return (py - canvas.offsetY) / canvas.zoom;
        }

        onPressed: event => {
            canvas.forceActiveFocus();
            canvas.altHeld = !!(event.modifiers & Qt.AltModifier);
            var rawCX = drawMouse.toContentX(event.x);
            var rawCY = drawMouse.toContentY(event.y);
            if (canvas.doc) {
                var sp = snapEngine.snapPoint(canvas.doc, rawCX, rawCY, canvas.zoom);
                rawCX = sp.x;
                rawCY = sp.y;
            }
            drawMouse.startCX = rawCX;
            drawMouse.startCY = rawCY;
            drawMouse.startSX = event.x;
            drawMouse.startSY = event.y;
            drawMouse.moved = false;
            canvas.draft = null;
            canvas.snapXGuides = [];
            canvas.snapYGuides = [];
        }
        onPositionChanged: event => {
            if (!pressed)
                return;
            var cx = drawMouse.toContentX(event.x);
            var cy = drawMouse.toContentY(event.y);
            if (!drawMouse.moved && Math.hypot(event.x - drawMouse.startSX, event.y - drawMouse.startSY) < 4)
                return;
            drawMouse.moved = true;
            if (canvas.doc && !canvas.altHeld && !(event.modifiers & Qt.AltModifier)) {
                var snapped = snapEngine.snapCreate(canvas.doc, drawMouse.startCX, drawMouse.startCY, cx, cy, canvas.zoom);
                cx = snapped.x;
                cy = snapped.y;
                canvas.snapXGuides = snapped.xGuides;
                canvas.snapYGuides = snapped.yGuides;
            } else {
                canvas.snapXGuides = [];
                canvas.snapYGuides = [];
            }
            var x0 = Math.min(drawMouse.startCX, cx);
            var y0 = Math.min(drawMouse.startCY, cy);
            var x1 = Math.max(drawMouse.startCX, cx);
            var y1 = Math.max(drawMouse.startCY, cy);
            canvas.draft = {
                type: ToolStore.activeShapeType,
                x: x0,
                y: y0,
                w: Math.max(1, x1 - x0),
                h: Math.max(1, y1 - y0)
            };
        }
        onReleased: event => {
            if (!canvas.doc) {
                canvas.draft = null;
                canvas.snapXGuides = [];
                canvas.snapYGuides = [];
                return;
            }
            if (!drawMouse.moved) {
                canvas.doc.addShape(ToolStore.activeShapeType, Math.round(drawMouse.startCX - 50), Math.round(drawMouse.startCY - 50), 100, 100);
            } else if (canvas.draft) {
                var d = canvas.draft;
                canvas.doc.addShape(d.type, d.x, d.y, d.w, d.h);
            }
            canvas.draft = null;
            canvas.snapXGuides = [];
            canvas.snapYGuides = [];
            ToolStore.setActiveTool("select");
        }
    }

    CanvasOverlays {
        doc: canvas.doc
        draft: canvas.draft
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
        marqueeActive: marquee.selecting
        marqueeRect: marquee.selection
        snapXGuides: canvas.snapXGuides
        snapYGuides: canvas.snapYGuides
    }

    DrillBreadcrumb {
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: 12
            topMargin: 12
        }
        doc: canvas.doc
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space && !event.isAutoRepeat) {
            canvas.spaceHeld = true;
            event.accepted = true;
        } else if (event.key === Qt.Key_Alt && !event.isAutoRepeat) {
            canvas.altHeld = true;
            canvas.snapXGuides = [];
            canvas.snapYGuides = [];
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            if (canvas.doc && canvas.doc.drillPath.length > 0) {
                canvas.doc.drillOut();
                event.accepted = true;
            } else {
                toolbar.closeMenu();
            }
        }
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Space && !event.isAutoRepeat) {
            canvas.spaceHeld = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_Alt && !event.isAutoRepeat) {
            canvas.altHeld = false;
            event.accepted = true;
        }
    }
    onActiveFocusChanged: {
        if (!canvas.activeFocus) {
            canvas.spaceHeld = false;
            canvas.altHeld = false;
        }
    }

    function clampZoom(v) {
        return camera.clampZoom(v);
    }
    function zoomAt(mx, my, dy) {
        camera.zoomAt(mx, my, dy);
    }
    function tryCenter() {
        return camera.tryCenter();
    }
    function saveCamera(d) {
        camera.saveCamera(d);
    }
    function loadCamera(d) {
        camera.loadCamera(d);
    }
    function showDocument(d) {
        camera.showDocument(d);
    }
    function applyMarquee(area, additive) {
        selectPolicy.applyMarquee(area, additive);
    }
    function shapePressed(uid, mods) {
        selectPolicy.shapePressed(uid, mods);
    }
    function shapeDoubleClicked(uid) {
        selectPolicy.shapeDoubleClicked(uid);
    }
    function shapeMoved(dx, dy) {
        selectPolicy.shapeMoved(dx, dy);
    }
    function shapeReleased(wasMoved, mods) {
        selectPolicy.shapeReleased(wasMoved, mods);
    }
    function computeSelBox() {
        return selectPolicy.computeSelBox();
    }
    function isCornerHandle(hid) {
        return resizePolicy.isCornerHandle(hid);
    }
    function resizePressed(hid, cx, cy, mods) {
        resizePolicy.resizePressed(hid, cx, cy, mods);
    }
    function resizeMoved(cx, cy, mods) {
        resizePolicy.resizeMoved(cx, cy, mods);
    }
    function resizeReleased() {
        resizePolicy.resizeReleased();
    }
    function topLeafAt(cx, cy) {
        return selectPolicy.topLeafAt(cx, cy);
    }
    function handleDoubleClicked(cx, cy, mods) {
        resizePolicy.handleDoubleClicked(cx, cy, mods);
    }
    function resizeApply(cx, cy, mods) {
        resizePolicy.resizeApply(cx, cy, mods);
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: canvas.spaceHeld ? (Qt.LeftButton | Qt.MiddleButton) : Qt.MiddleButton
        hoverEnabled: true
        cursorShape: canvas.panning ? Qt.ClosedHandCursor : canvas.spaceHeld ? Qt.OpenHandCursor : Qt.ArrowCursor

        property real lastX: 0
        property real lastY: 0

        onPressed: event => {
            canvas.forceActiveFocus();
            if (event.button === Qt.MiddleButton || (event.button === Qt.LeftButton && canvas.spaceHeld)) {
                mouse.lastX = event.x;
                mouse.lastY = event.y;
                canvas.panning = true;
            }
        }
        onPositionChanged: event => {
            if (!canvas.panning)
                return;
            canvas.offsetX += event.x - mouse.lastX;
            canvas.offsetY += event.y - mouse.lastY;
            mouse.lastX = event.x;
            mouse.lastY = event.y;
        }
        onReleased: {
            canvas.panning = false;
        }

        onWheel: wheel => {
            var usePixel = wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0;
            var dx = usePixel ? wheel.pixelDelta.x : wheel.angleDelta.x;
            var dy = usePixel ? wheel.pixelDelta.y : wheel.angleDelta.y;
            if (wheel.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) {
                canvas.zoomAt(wheel.x, wheel.y, dy);
            } else {
                if ((wheel.modifiers & Qt.ShiftModifier) && Math.abs(dy) > Math.abs(dx)) {
                    dx = dy;
                    dy = 0;
                }
                canvas.offsetX -= dx;
                canvas.offsetY -= dy;
            }
            wheel.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: toolbar.menuOpen
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onPressed: mouse => {
            toolbar.closeMenu();
            mouse.accepted = true;
        }
    }

    CanvasToolbar {
        id: toolbar
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 16
        }
    }
}
