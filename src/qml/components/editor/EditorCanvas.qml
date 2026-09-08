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
    onDocChanged: {
        canvas.commitTextEdit();
        canvas.showDocument(canvas.doc);
    }

    property var draft: null

    property int clickArmedUid: -1
    property bool moveAllowed: false
    property bool marqueeDragged: false

    property var selBox: canvas.doc ? canvas.doc.selectionBBox() : null

    property var resizeState: null
    // Unsnapped move travel for the active drag (base box at press plus
    // accumulated raw deltas). Snapping reads this, never the live box.
    property var moveState: null

    property var snapXGuides: []
    property var snapYGuides: []
    // Winning equal-gap segments (content coords) for measurement.
    property var snapXGap: null
    property var snapYGap: null
    // Live size readout (content {w,h}) plus cursor in screen px.
    property var measureBox: null
    property real cursorX: 0
    property real cursorY: 0

    property bool altHeld: false

    // Inline text editing (Figma): double-click or fresh creation opens
    // a TextInput over the shape. Keystrokes stream into one undo
    // transaction; Enter or focus loss commits, Esc restores + cancels.
    property int editingUid: -1
    property string editStart: ""
    // Document owning the open edit transaction. Tracked separately so
    // tab switches end the gesture on the old doc, never the new one.
    property var editDoc: null

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
            canvas.commitTextEdit();
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
        editingUid: canvas.editingUid
        activatePolicy: () => canvas.forceActiveFocus()
        pressPolicy: (uid, mods) => canvas.shapePressed(uid, mods)
        movePolicy: (dx, dy) => canvas.shapeMoved(dx, dy)
        releasePolicy: (wasMoved, mods) => canvas.shapeReleased(wasMoved, mods)
        doublePolicy: uid => canvas.shapeDoubleClicked(uid)
        measurePolicy: (uid, w, h) => canvas.textMeasured(uid, w, h)
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

    // Render-free measurer for text boxes (creation sizing and edit
    // growth). Bindings re-evaluate on read, so setting font/text then
    // reading boundingRect in one call always measures fresh values.
    TextMetrics {
        id: textMeasure

        elide: Text.ElideNone
    }

    // Inline text editor, floating over the shape in screen coords.
    // Rotation rides along (same angle about the same center) so it
    // tracks rotated text; the box itself stays axis-aligned math.
    TextInput {
        id: editor

        property var node: canvas.editNode()

        visible: canvas.editingUid >= 0 && !!editor.node
        x: canvas.offsetX + (editor.node ? editor.node.x * canvas.zoom : 0)
        y: canvas.offsetY + (editor.node ? editor.node.y * canvas.zoom : 0)
        width: Math.max(24, (editor.node ? editor.node.w * canvas.zoom : 0) + 8)
        height: Math.max(16, (editor.node ? editor.node.h * canvas.zoom : 0) + 8)
        rotation: editor.node ? editor.node.rotation : 0
        transformOrigin: Item.Center
        z: 50
        focus: visible
        selectByMouse: true
        clip: true
        color: editor.node ? editor.node.fill : AppTheme.foreground
        selectionColor: AppTheme.selection
        font.family: editor.node ? editor.node.fontFamily : "Inter"
        font.pixelSize: Math.max(1, (editor.node ? editor.node.fontSize : 16) * canvas.zoom)
        font.weight: editor.node ? editor.node.fontWeight : 400
        font.letterSpacing: editor.node ? editor.node.fontSize * editor.node.letterSpacing / 100 * canvas.zoom : 0
        horizontalAlignment: canvas.editAlignH()
        verticalAlignment: canvas.editAlignV()
        wrapMode: editor.node && !editor.node.autoSize ? TextInput.WordWrap : TextInput.NoWrap

        onTextChanged: {
            if (canvas.editingUid < 0 || !canvas.editDoc)
                return;
            var cur = canvas.editNode();
            // Seeding assignment (beginTextEdit copies node text in)
            // echoes back here with identical content: skip it so merely
            // opening the editor never dirties the document.
            if (cur && editor.text === cur.textContent)
                return;
            canvas.editDoc.setShapeProp(canvas.editingUid, "textContent", editor.text);
            var n = canvas.editNode();
            if (n && n.autoSize) {
                var m = canvas.measureText(editor.text, n.fontFamily, n.fontWeight, n.fontSize, n.letterSpacing);
                canvas.applyMeasured(canvas.editingUid, m.w, m.h);
            }
        }
        onEditingFinished: canvas.commitTextEdit()
        Keys.onEscapePressed: event => {
            canvas.cancelTextEdit();
            event.accepted = true;
        }
    }

    MouseArea {
        id: drawMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        enabled: (ToolStore.activeTool === "shapes" || ToolStore.activeTool === "text") && canvas.doc !== null

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
            canvas.commitTextEdit();
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
            canvas.measureBox = null;
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
                type: ToolStore.activeTool === "text" ? "text" : ToolStore.activeShapeType,
                x: x0,
                y: y0,
                w: Math.max(1, x1 - x0),
                h: Math.max(1, y1 - y0)
            };
            canvas.cursorX = event.x;
            canvas.cursorY = event.y;
            canvas.measureBox = {
                w: canvas.draft.w,
                h: canvas.draft.h
            };
        }
        onReleased: event => {
            if (!canvas.doc) {
                canvas.draft = null;
                canvas.measureBox = null;
                canvas.snapXGuides = [];
                canvas.snapYGuides = [];
                return;
            }
            if (!drawMouse.moved) {
                if (ToolStore.activeTool === "text")
                    canvas.createText(Math.round(drawMouse.startCX), Math.round(drawMouse.startCY), 0, 0, true);
                else
                    canvas.doc.addShape(ToolStore.activeShapeType, Math.round(drawMouse.startCX - 50), Math.round(drawMouse.startCY - 50), 100, 100);
            } else if (canvas.draft) {
                var d = canvas.draft;
                if (ToolStore.activeTool === "text")
                    canvas.createText(d.x, d.y, d.w, d.h, false);
                else
                    canvas.doc.addShape(d.type, d.x, d.y, d.w, d.h);
            }
            canvas.draft = null;
            canvas.measureBox = null;
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
        snapXGap: canvas.snapXGap
        snapYGap: canvas.snapYGap
        measureBox: canvas.measureBox
        cursorX: canvas.cursorX
        cursorY: canvas.cursorY
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
    // Node under the inline editor (null when closed or deleted).
    function editNode() {
        if (!canvas.doc || canvas.editingUid < 0)
            return null;
        return canvas.doc.findNode(canvas.editingUid);
    }
    function editAlignH() {
        var n = canvas.editNode();
        if (!n)
            return TextInput.AlignLeft;
        switch (n.hAlign) {
        case "center":
            return TextInput.AlignHCenter;
        case "right":
            return TextInput.AlignRight;
        case "justify":
            return TextInput.AlignJustify;
        default:
            return TextInput.AlignLeft;
        }
    }
    function editAlignV() {
        var n = canvas.editNode();
        if (!n)
            return TextInput.AlignTop;
        switch (n.vAlign) {
        case "middle":
            return TextInput.AlignVCenter;
        case "bottom":
            return TextInput.AlignBottom;
        default:
            return TextInput.AlignTop;
        }
    }
    // Render-free box measure for content at a font. Empty content
    // measures one line ("Ag") with a 40px floor so fresh texts stay a
    // visible click target; letter spacing adds per glyph.
    function measureText(content, family, weight, size, spacingPct) {
        textMeasure.font.family = family;
        textMeasure.font.weight = weight;
        textMeasure.font.pixelSize = Math.max(1, size);
        textMeasure.font.letterSpacing = 0;
        var t = content === "" ? "Ag" : content;
        textMeasure.text = t;
        var r = textMeasure.boundingRect;
        var extra = t.length * size * (spacingPct || 0) / 100;
        return {
            w: content === "" ? Math.max(40, r.width + extra) : Math.max(1, r.width + extra),
            h: Math.max(size * 1.2, r.height)
        };
    }
    // Text creation: auto boxes size from the (empty) content, fixed
    // boxes keep the drag rect. Both land selected and editing.
    function createText(cx, cy, w, h, auto) {
        if (!canvas.doc)
            return;
        var bw = w, bh = h;
        if (auto) {
            var m = canvas.measureText("", "Inter", 400, 16, 0);
            bw = m.w;
            bh = m.h;
        }
        var uid = canvas.doc.addText(cx, cy, Math.max(1, bw), Math.max(1, bh), auto);
        canvas.beginTextEdit(uid);
    }
    function beginTextEdit(uid) {
        var d = canvas.doc;
        if (!d || canvas.editingUid === uid)
            return;
        canvas.commitTextEdit();
        var n = d.findNode(uid);
        if (!n || n.kind !== "shape" || n.shapeType !== "text")
            return;
        if (d.isEffectivelyLocked(n) || !d.isEffectivelyVisible(n))
            return;
        canvas.editingUid = uid;
        canvas.editDoc = d;
        canvas.editStart = n.textContent;
        editor.text = n.textContent;
        d.beginTransaction();
        editor.forceActiveFocus();
        editor.selectAll();
    }
    function commitTextEdit() {
        if (canvas.editingUid < 0)
            return;
        canvas.editingUid = -1;
        // editDoc may belong to a closed tab (destroyed): ending there
        // must never throw, the edit is simply already gone.
        try {
            if (canvas.editDoc)
                canvas.editDoc.endTransaction();
        } catch (e) {}
        canvas.editDoc = null;
        canvas.forceActiveFocus();
    }
    function cancelTextEdit() {
        if (canvas.editingUid < 0)
            return;
        var uid = canvas.editingUid;
        var back = canvas.editStart;
        canvas.editingUid = -1;
        try {
            if (canvas.editDoc) {
                var n = canvas.editDoc.findNode(uid);
                if (n && n.textContent !== back) {
                    canvas.editDoc.setShapeProp(uid, "textContent", back);
                    var m = canvas.measureText(back, n.fontFamily, n.fontWeight, n.fontSize, n.letterSpacing);
                    canvas.applyMeasuredOn(canvas.editDoc, uid, m.w, m.h);
                }
                canvas.editDoc.endTransaction();
            }
        } catch (e) {}
        canvas.editDoc = null;
        canvas.forceActiveFocus();
    }
    // Measured writeback for auto-size boxes. Joins the ambient gesture
    // when one is open (typing, font edits), else commits a single entry
    // via begin/end. The 1px deadband keeps renders convergent.
    function applyMeasured(uid, w, h) {
        if (canvas.doc)
            canvas.applyMeasuredOn(canvas.doc, uid, w, h);
    }
    function applyMeasuredOn(d, uid, w, h) {
        var n = d.findNode(uid);
        if (!n || n.shapeType !== "text" || !n.autoSize)
            return;
        if (d.isEffectivelyLocked(n))
            return;
        var nw = Math.max(20, Math.round(w));
        var nh = Math.max(1, Math.round(Math.max(n.fontSize * 1.2, h)));
        if (Math.abs(nw - n.w) < 1 && Math.abs(nh - n.h) < 1)
            return;
        d.beginTransaction();
        d.setShapeProp(uid, "w", nw);
        d.setShapeProp(uid, "h", nh);
        d.endTransaction();
    }
    // Static-text writeback from ShapeItem paint. Editing items report
    // nothing (hidden glyphs paint zero); the editor measures instead.
    function textMeasured(uid, w, h) {
        canvas.applyMeasured(uid, w, h);
    }
    function applyMarquee(area, additive) {
        selectPolicy.applyMarquee(area, additive);
    }
    function shapePressed(uid, mods) {
        canvas.commitTextEdit();
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
        doc: canvas.doc
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 16
        }
    }
}
