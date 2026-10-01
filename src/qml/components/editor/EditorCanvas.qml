import QtCore
import QtQuick
import QtQuick.Layouts
import Totm

// Canvas. Wheel pans, Ctrl-wheel zooms to cursor, Space-drag pans.
// Select-drag marquees, shapes-drag draws, pen clicks/drags vectors,
// handles resize the selection. Moves, resizes and creations snap
// within 5 screen px; Alt suspends. Hidden skips input, locked swallows
// presses.
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
        canvas.exitPathEdit();
        if (canvas.pen)
            canvas.pen.cancel();
        if (canvas.penEdit)
            canvas.penEdit.exit();
        if (canvas.pathTool)
            canvas.pathTool.cancel();
        if (ToolState.pathDrawing)
            ToolState.cancelPathDraw();
        if (canvas.imageTool)
            canvas.imageTool.clearPending();
        canvas.showDocument(canvas.doc);
    }

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

    // True when any leaf has background blur enabled: gates the
    // backdrop duplicate so non-frosted scenes skip the 2x CPU tax.
    readonly property bool hasFrosted: {
        var d = canvas.doc;
        if (!d)
            return false;
        d.rev;
        d.structRev;
        var leaves = d.leafList || [];
        for (var i = 0; i < leaves.length; i++) {
            var n = leaves[i];
            if (!n)
                continue;
            var bb = n.backgroundBlur;
            if (bb && bb.enabled === true && Number(bb.radius) > 0)
                return true;
        }
        return false;
    }

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
    property var pen: PenTool {
        canvas: canvas
        snap: snapEngine
    }
    property var penEdit: PenEdit {
        canvas: canvas
        snap: snapEngine
    }
    property var pathTool: PathTool {
        canvas: canvas
        snap: snapEngine
    }
    property var drawTool: ShapeDrawTool {
        canvas: canvas
        snap: snapEngine
        textEdit: textEditor
    }
    property var imageTool: ImageTool {
        canvas: canvas
        snap: snapEngine
    }

    // Direct on-canvas path editing (select tool): when a custom Path
    // clip is last-selected, its trajectory loads into pathTool and
    // anchors/handles edit live with per-gesture undo. Empty-space
    // presses fall through to marquee/shapes and exit the session.
    property var pathEdit: ({
            active: false,
            clipId: -1,
            txOpen: false,
            txDoc: null
        })

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
        enabled: ToolState.activeTool !== "shapes" && ToolState.activeTool !== "pen" && ToolState.activeTool !== "path" && ToolState.activeTool !== "image"

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

    // Backdrop duplicate without frosted panels: live source for
    // background-blur sampling (no recursion, same transform). Always
    // rendered below the main layer with identical pixels, so sampling
    // can never observe an empty source; blurred shapes hide here so
    // each frosted panel samples only the content behind it.
    ShapeLayer {
        id: backdropLayer

        doc: canvas.doc
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
        editingUid: -1
        hideBlurShapes: true
        enabled: false
        visible: canvas.hasFrosted
    }

    ShapeLayer {
        id: mainLayer

        doc: canvas.doc
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
        editingUid: textEditor.editingUid
        backdropItem: backdropLayer
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
        handlesActive: ToolState.activeTool === "select" && canvas.doc !== null && canvas.penEdit.editUid < 0
        showFrame: canvas.selBox ? (canvas.selBox.count > 1 || canvas.selBox.rotated || canvas.selBox.singleGroup) : false
        pressPolicy: (hid, cx, cy, mods) => canvas.resizePressed(hid, cx, cy, mods)
        movePolicy: (cx, cy, mods) => canvas.resizeMoved(cx, cy, mods)
        releasePolicy: () => canvas.resizeReleased()
        doublePolicy: (hid, cx, cy, mods) => canvas.handleDoubleClicked(cx, cy, mods)
    }

    // Inline text editing session (editor visual + measure + commit).
    TextEditor {
        id: textEditor
        canvas: canvas
    }

    // Shape/text creation drags. State and commit live in the tool;
    // this area only routes input.
    MouseArea {
        id: drawMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        enabled: (ToolState.activeTool === "shapes" || ToolState.activeTool === "text") && canvas.doc !== null

        onPressed: event => {
            canvas.drawTool.pressAt(event.x, event.y, event.modifiers);
        }
        onPositionChanged: event => {
            if (pressed)
                canvas.drawTool.moveTo(event.x, event.y, event.modifiers, true);
        }
        onReleased: {
            canvas.drawTool.releaseAt();
        }
    }

    // Image placement drags. Only armed once a blob is pending (picker
    // accepted); click stamps natural size, drag stretches to the box.
    MouseArea {
        id: imageMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        enabled: ToolState.activeTool === "image" && canvas.doc !== null && canvas.imageTool.hasPending()

        onPressed: event => {
            canvas.imageTool.pressAt(event.x, event.y, event.modifiers);
        }
        onPositionChanged: event => {
            if (pressed)
                canvas.imageTool.moveTo(event.x, event.y, event.modifiers, true);
        }
        onReleased: {
            canvas.imageTool.releaseAt();
        }
    }

    // Pen input: click adds corners, drag draws symmetric
    // curves, first-point click closes. Double-click/Enter parts,
    // Esc finishes the node. Placed before the pan catcher so Space
    // still pans above the pen.
    MouseArea {
        id: penMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        enabled: ToolState.activeTool === "pen" && canvas.doc !== null

        onPressed: event => {
            canvas.pen.pressAt(event.x, event.y, event.modifiers);
            event.accepted = true;
        }
        onPositionChanged: event => {
            if (pressed)
                canvas.pen.moveTo(event.x, event.y, event.modifiers, true);
            else
                canvas.pen.refreshHover(event.x, event.y, event.modifiers);
        }
        onExited: canvas.pen.exitHover()
        onReleased: {
            canvas.pen.releaseAt();
        }
        onDoubleClicked: event => {
            canvas.pen.doubleAt();
            event.accepted = true;
        }
    }

    // Point editing input: handles/anchors first, edge click inserts,
    // empty click exits and falls through to marquee/shapes below.
    MouseArea {
        id: penEditMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
        enabled: ToolState.activeTool === "select" && canvas.penEdit.editUid >= 0 && canvas.doc !== null

        onPressed: event => {
            var handled = canvas.penEdit.pressAt(event.x, event.y, event.modifiers);
            event.accepted = handled;
        }
        onPositionChanged: event => {
            canvas.penEdit.moveTo(event.x, event.y, event.modifiers);
        }
        onExited: canvas.penEdit.hover = null
        onReleased: {
            canvas.penEdit.releaseAt();
        }
        onDoubleClicked: event => {
            var done = canvas.penEdit.doubleAt(event.x, event.y);
            event.accepted = done;
        }
    }

    // In-select motion-path editing: anchors/handles/edges of the
    // selected Path clip drag live (one undo entry per gesture).
    // Empty presses fall through to marquee/shapes and exit the
    // session, mirroring pen point-edit routing above.
    MouseArea {
        id: pathEditMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
        enabled: ToolState.activeTool === "select" && canvas.doc !== null && canvas.pathEdit && canvas.pathEdit.active

        onPressed: event => {
            var hit = canvas.pathTool.hitTestScreen(event.x, event.y);
            if (!hit) {
                canvas.exitPathEdit();
                event.accepted = false;
                return;
            }
            canvas.beginPathEditTx();
            canvas.pathTool.pressAt(event.x, event.y, event.modifiers);
            // Edge clicks insert immediately; anchor/handle presses
            // arm a drag that commits on move.
            if (!canvas.pathTool.editDrag)
                canvas.commitPathEdit();
            event.accepted = true;
        }
        onPositionChanged: event => {
            if (pressed) {
                canvas.pathTool.moveTo(event.x, event.y, event.modifiers, true);
                if (canvas.pathTool.dragging || canvas.pathTool.editDrag)
                    canvas.commitPathEdit();
            } else {
                canvas.pathTool.refreshHover(event.x, event.y, event.modifiers);
            }
        }
        onExited: {
            if (!pressed)
                canvas.pathTool.exitHover();
        }
        onReleased: {
            canvas.pathTool.releaseAt();
            canvas.commitPathEdit();
            canvas.endPathEditTx();
        }
        onDoubleClicked: event => {
            if (canvas.pathTool.hitTestScreen(event.x, event.y) && canvas.pathTool.doubleAt(event.x, event.y)) {
                if (canvas.doc)
                    canvas.doc.beginTransaction();
                canvas.commitPathEdit();
                if (canvas.doc)
                    canvas.doc.endTransaction();
                event.accepted = true;
            } else {
                event.accepted = false;
            }
        }
    }

    // Motion-path input: click adds corners, drag draws symmetric curves.
    // Enter/double-click commits to a Path clip, Esc cancels. Placed with
    // the pen areas so Space still pans above the path.
    MouseArea {
        id: pathMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        enabled: ToolState.activeTool === "path" && canvas.doc !== null

        onPressed: event => {
            canvas.pathTool.pressAt(event.x, event.y, event.modifiers);
            event.accepted = true;
        }
        onPositionChanged: event => {
            if (pressed)
                canvas.pathTool.moveTo(event.x, event.y, event.modifiers, true);
            else
                canvas.pathTool.refreshHover(event.x, event.y, event.modifiers);
        }
        onExited: canvas.pathTool.exitHover()
        onReleased: {
            canvas.pathTool.releaseAt();
        }
        onDoubleClicked: event => {
            if (canvas.pathTool.doubleAt(event.x, event.y))
                event.accepted = true;
            else if (canvas.commitPathDraw())
                event.accepted = true;
        }
    }

    CanvasOverlays {
        doc: canvas.doc
        draft: canvas.imageTool.draft ?? canvas.drawTool.draft
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

    PenOverlay {
        tool: canvas.pen
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
        penActive: ToolState.activeTool === "pen" && canvas.doc !== null
    }

    PathOverlay {
        tool: canvas.pathTool
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
        pathActive: ToolState.activeTool === "path" && canvas.doc !== null
        editActive: ToolState.activeTool === "select" && canvas.doc !== null && canvas.pathEdit && canvas.pathEdit.active
        selectedPts: canvas.selectedPath.pts
        selectedClosed: canvas.selectedPath.closed
        showSelected: ToolState.activeTool !== "path" && !(canvas.pathEdit && canvas.pathEdit.active) && canvas.selectedPath.pts.length >= 2
        pivotX: canvas.selectedPath.pivotX || 0
        pivotY: canvas.selectedPath.pivotY || 0
        showPivot: (ToolState.activeTool !== "path" && canvas.selectedPath.showPivot === true) && (canvas.selectedPath.pts.length >= 1)
    }

    PenEditOverlay {
        tool: canvas.penEdit
        doc: canvas.doc
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
        editActive: ToolState.activeTool === "select" && canvas.penEdit.editUid >= 0 && canvas.doc !== null
    }

    // Plugin canvas overlays (ui.slots). Plain Items under the chrome so
    // they can annotate the scene; each entry gets doc/zoom/offset when
    // it declares them. The host itself takes no input, so canvas tools
    // keep working unless an overlay adds its own MouseArea.
    Item {
        id: pluginOverlayHost

        anchors.fill: parent

        property var entries: []

        function refreshPlugins() {
            pluginOverlayHost.entries = PluginStore.canvasOverlays();
        }

        Component.onCompleted: pluginOverlayHost.refreshPlugins()

        Connections {
            target: PluginStore
            function onPluginsChanged() {
                pluginOverlayHost.refreshPlugins();
            }
        }

        Repeater {
            model: pluginOverlayHost.entries

            delegate: Loader {
                property var entry: modelData

                anchors.fill: parent
                active: true
                asynchronous: true
                source: entry.url

                onLoaded: {
                    if (item) {
                        if ("pluginId" in item)
                            item.pluginId = entry.pluginId;
                        if ("doc" in item)
                            item.doc = canvas.doc;
                        if ("zoom" in item)
                            item.zoom = canvas.zoom;
                        if ("offsetX" in item)
                            item.offsetX = canvas.offsetX;
                        if ("offsetY" in item)
                            item.offsetY = canvas.offsetY;
                    }
                }
            }
        }
    }

    // Guides above the tools (edges only) but below the export pill,
    // so it keeps its input.
    CanvasGuides {
        doc: canvas.doc
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
    }

    // Video export entry, top-right. Opens the quality picker; the
    // render itself snapshots fresh so later edits export next time.
    ExportButton {
        id: exportButton

        anchors {
            right: parent.right
            top: parent.top
            rightMargin: 12
            topMargin: 12
        }
        doc: canvas.doc
        active: qualityPopup.opened
        onClicked: {
            VideoExporter.clearError();
            qualityPopup.open();
        }
    }

    // Motion-path draw hint, top-centered while pathDrawing.
    Rectangle {
        visible: ToolState.activeTool === "path"
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: 12
        }
        width: hintText.implicitWidth + 24
        height: 32
        radius: AppTheme.radiusLarge
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border

        Text {
            id: hintText
            anchors.centerIn: parent
            text: qsTr("Click to add points, Enter to commit")
            font.pixelSize: 12
            color: AppTheme.foreground
        }
    }

    // Image placement hint, top-centered while a blob is pending.
    Rectangle {
        visible: ToolState.activeTool === "image" && canvas.imageTool.hasPending()
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: 12
        }
        width: imageHintText.implicitWidth + 24
        height: 32
        radius: AppTheme.radiusLarge
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border

        Text {
            id: imageHintText
            anchors.centerIn: parent
            text: qsTr("Click to place, drag to size")
            font.pixelSize: 12
            color: AppTheme.foreground
        }
    }

    // Image file picker (picker-then-place). Accepts the chosen file by
    // importing a copy into the library; cancel without a pending blob
    // falls back to select so the dead tool never sticks.
    FilePicker {
        id: imagePicker

        suffixes: ["png", "jpg", "jpeg", "webp", "gif", "svg"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: canvas.acceptImageFile(selectedFile)
        onRejected: {
            if (!canvas.imageTool.hasPending())
                ToolState.setActiveTool("select");
        }
    }

    // Leaving the pen drops the in-progress sketch so a stale draft
    // never leaks into the next tool or tab. Entering path redraw seeds
    // the existing trajectory so redraws show what they replace.
    // Entering image opens the picker; leaving it drops the pending blob.
    Connections {
        target: ToolState
        function onActiveToolChanged() {
            if (ToolState.activeTool !== "pen" && canvas.pen)
                canvas.pen.cancel();
            if (ToolState.activeTool !== "image" && canvas.imageTool)
                canvas.imageTool.clearPending();
            if (ToolState.activeTool === "image" && canvas.doc && !canvas.imageTool.hasPending())
                imagePicker.open();
            if (ToolState.activeTool !== "path") {
                if (canvas.pathEdit && canvas.pathEdit.active && ToolState.activeTool !== "select")
                    canvas.exitPathEdit();
                else if (canvas.pathTool)
                    canvas.pathTool.cancel();
                if (ToolState.activeTool === "select")
                    canvas.syncPathEdit();
            } else if (ToolState.activeTool === "path" && canvas.pathTool && ToolState.pathClipId >= 0) {
                var redraw = canvas.doc ? canvas.doc.animClip(ToolState.pathClipId) : null;
                if (redraw && redraw.preset === "customPath") {
                    canvas.pathTool.loadAbsolute(canvas.pathAbsolute(redraw));
                    canvas.pathTool.showClosed = !!(redraw.options && redraw.options.closed);
                }
            }
        }
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
        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return) && ToolState.activeTool === "pen") {
            if (canvas.pen.enterCommit())
                event.accepted = true;
        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return) && ToolState.activeTool === "path") {
            if (canvas.commitPathDraw())
                event.accepted = true;
        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return) && canvas.penEdit.editUid >= 0) {
            canvas.penEdit.exit();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return) && canvas.pathEdit && canvas.pathEdit.active) {
            canvas.exitPathEdit();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            if (ToolState.activeTool === "image") {
                canvas.cancelImageTool();
                event.accepted = true;
            } else if (ToolState.activeTool === "path") {
                canvas.cancelPathDraw();
                event.accepted = true;
            } else if (canvas.pathEdit && canvas.pathEdit.active) {
                canvas.exitPathEdit();
                event.accepted = true;
            } else if (canvas.penEdit.editUid >= 0) {
                canvas.penEdit.exit();
                event.accepted = true;
            } else if (ToolState.activeTool === "pen" && canvas.pen.hasWork) {
                canvas.pen.escapeFinish();
                ToolState.setActiveTool("select");
                event.accepted = true;
            } else if (canvas.doc && canvas.doc.drillPath.length > 0) {
                canvas.doc.drillOut();
                event.accepted = true;
            } else {
                toolbar.closeMenu();
            }
        } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && ToolState.activeTool === "path") {
            if (canvas.pathTool.deleteSelected())
                event.accepted = true;
        } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && canvas.pathEdit && canvas.pathEdit.active) {
            // Edit mode keeps a committable trajectory: refuse drops
            // below 2 points so the buffer never diverges from the clip.
            var dropCount = canvas.pathTool.sel.length;
            if (dropCount > 0 && canvas.pathTool.active.length - dropCount >= 2) {
                if (canvas.doc)
                    canvas.doc.beginTransaction();
                canvas.pathTool.deleteSelected();
                canvas.commitPathEdit();
                if (canvas.doc)
                    canvas.doc.endTransaction();
                event.accepted = true;
            } else if (dropCount > 0) {
                event.accepted = true;
            }
        } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && canvas.penEdit.editUid >= 0) {
            if (canvas.penEdit.deleteSelected())
                event.accepted = true;
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
    function fitView() {
        return camera.fitView();
    }
    // Keyboard zoom around the viewport center (same exponential feel
    // as the wheel path).
    function zoomStep(dy) {
        camera.zoomAt(canvas.width / 2, canvas.height / 2, dy);
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
    // Selected Path clip's trajectory in absolute content coords for the
    // overlay (base of the first leaf plus stored start-relative offsets;
    // groups ride rigidly, so the first leaf represents the motion).
    readonly property var selectedPath: canvas.computeSelectedPath()
    onSelectedPathChanged: canvas.syncPathEdit()

    function computeSelectedPath() {
        var d = canvas.doc;
        var empty = {
            pts: [],
            closed: false,
            pivotX: 0,
            pivotY: 0,
            showPivot: false
        };
        if (!d || ToolState.activeTool === "path")
            return empty;
        var ids = d.anim.selectedClipIds;
        if (ids.length === 0)
            return empty;
        var c = d.animClip(ids[ids.length - 1]);
        if (!c || c.preset !== "customPath")
            return empty;
        var pts = canvas.pathAbsolute(c);
        var out = {
            pts: pts,
            closed: !!(c.options && c.options.closed),
            pivotX: 0,
            pivotY: 0,
            showPivot: false
        };
        // Follow-pivot marker: the selected pivot rides the path, so the
        // marker sits on the trajectory's time-0 anchor (first anchor
        // normally, stored end for reversed open paths). Top-left needs
        // no marker (it is the trajectory's first anchor when follow
        // is topLeft).
        var o = (c.options) || {};
        var pv = canvas.pathPivotLocal(o, canvas.pathBaseOf(c));
        if (pv && pts.length > 0) {
            var s0 = pts[0] || {};
            if (!out.closed && canvas.pathStartsAtEnd(o))
                s0 = pts[pts.length - 1] || {};
            out.pivotX = Number(s0.x) || 0;
            out.pivotY = Number(s0.y) || 0;
            out.showPivot = true;
        }
        return out;
    }

    // Time-0 trajectory end for the pivot marker: reversed open paths
    // begin at the stored end, except even-count alternate (ping-pong
    // returns to 0). Closed loops coincide at the first point either
    // way. Mirrors Anims::remapPathProgress end mapping in samplePathEx.
    function pathStartsAtEnd(o) {
        if (!o || o.reverse !== true)
            return false;
        if (o.closed === true)
            return false;
        var mode = o.repeatMode;
        if (mode !== "times" && mode !== "alternate")
            return true;
        var count = Math.min(8, Math.max(1, Math.round(Number(o.repeatCount) || 1)));
        if (count <= 1)
            return true;
        if (mode === "alternate" && count % 2 === 0)
            return false;
        return true;
    }

    // Base frame a clip's trajectory displays in: playBase while
    // previewing, else live. Groups resolve to their first leaf.
    function pathBaseOf(clip) {
        var d = canvas.doc;
        if (!d || !clip)
            return null;
        var target = d.findNode(clip.targetUid);
        if (!target)
            return null;
        var leaves = target.kind === "group" ? d._leavesUnder(target) : [target];
        if (leaves.length === 0)
            return null;
        var firstUid = leaves[0].uid;
        if (d.anim && d.anim.playBase && d.anim.playBase[firstUid]) {
            var pb = d.anim.playBase[firstUid];
            return {
                ox: Number(pb.x) || 0,
                oy: Number(pb.y) || 0,
                w: Math.max(0, Number(pb.w) || 0),
                h: Math.max(0, Number(pb.h) || 0),
                rotation: Number(pb.rotation) || 0
            };
        }
        return {
            ox: Number(leaves[0].x) || 0,
            oy: Number(leaves[0].y) || 0,
            w: Math.max(0, Number(leaves[0].w) || 0),
            h: Math.max(0, Number(leaves[0].h) || 0),
            rotation: Number(leaves[0].rotation) || 0
        };
    }

    // Follow pivot in base-frame coords, rotated by the base rotation
    // (mirrors Anims::pathFollowComp's pivot selection). Null for
    // legacy top-left; non-null means the pivot rides the path and the
    // marker sits on the time-0 anchor (see pathStartsAtEnd).
    function pathPivotLocal(o, base) {
        if (!base)
            return null;
        var f = (o && o.follow) || "topLeft";
        var w = base.w, h = base.h, px = 0, py = 0;
        if (f === "center") {
            px = w / 2;
            py = h / 2;
        } else if (f === "top") {
            px = w / 2;
        } else if (f === "topRight") {
            px = w;
        } else if (f === "right") {
            px = w;
            py = h / 2;
        } else if (f === "bottomRight") {
            px = w;
            py = h;
        } else if (f === "bottom") {
            px = w / 2;
            py = h;
        } else if (f === "bottomLeft") {
            py = h;
        } else if (f === "left") {
            py = h / 2;
        } else if (f === "custom") {
            px = Math.min(4000, Math.max(-4000, Number(o.followX) || 0));
            py = Math.min(4000, Math.max(-4000, Number(o.followY) || 0));
        } else {
            return null;
        }
        if (px === 0 && py === 0)
            return null;
        var rad = (base.rotation || 0) * Math.PI / 180;
        return {
            x: px * Math.cos(rad) - py * Math.sin(rad),
            y: px * Math.sin(rad) + py * Math.cos(rad)
        };
    }

    // Stored points are start-relative offsets; display them at the base
    // position (playBase while previewing, else live) so the trajectory
    // draws where the shape actually travels.
    function pathAbsolute(clip) {
        var d = canvas.doc;
        if (!d || !clip)
            return [];
        var rel = (clip.options && clip.options.pts) || [];
        if (rel.length === 0)
            return [];
        var base = canvas.pathBaseOf(clip);
        if (!base)
            return [];
        var ox = base.ox, oy = base.oy;
        var out = [];
        for (var i = 0; i < rel.length; i++) {
            var p = rel[i] || {};
            var px = Number(p.x) || 0, py = Number(p.y) || 0;
            out.push({
                x: ox + px,
                y: oy + py,
                smooth: p.smooth === true,
                inX: ox + (p.inX !== undefined ? Number(p.inX) : px),
                inY: oy + (p.inY !== undefined ? Number(p.inY) : py),
                outX: ox + (p.outX !== undefined ? Number(p.outX) : px),
                outY: oy + (p.outY !== undefined ? Number(p.outY) : py)
            });
        }
        return out;
    }

    // Direct path editing: the selected clip's trajectory rides in
    // pathTool (absolute coords) while pathEdit is active. Commits
    // convert back to start-relative, so edits stay valid when the
    // shape later moves. Drags coalesce to one undo entry via the
    // doc transaction opened on press and closed on release.
    function pathEditClip() {
        var d = canvas.doc;
        if (!d || ToolState.activeTool !== "select")
            return null;
        var ids = d.anim.selectedClipIds;
        if (ids.length === 0)
            return null;
        var c = d.animClip(ids[ids.length - 1]);
        return c && c.preset === "customPath" ? c : null;
    }

    function enterPathEdit(clipId) {
        var d = canvas.doc;
        var c = d ? d.animClip(clipId) : null;
        if (!c || c.preset !== "customPath" || !canvas.pathTool)
            return false;
        // Mutual exclusion with pen point-edit: both MouseAreas cover
        // select tool, pathEdit sits on top and would steal presses.
        if (canvas.penEdit && canvas.penEdit.editUid >= 0)
            canvas.penEdit.exit();
        canvas.pathTool.loadAbsolute(canvas.pathAbsolute(c));
        canvas.pathTool.showClosed = !!(c.options && c.options.closed);
        canvas.pathEdit = {
            active: true,
            clipId: clipId,
            txOpen: false,
            txDoc: null
        };
        return true;
    }

    function exitPathEdit() {
        var exitPe = canvas.pathEdit;
        if (exitPe && exitPe.txOpen) {
            var exitDoc = exitPe.txDoc || canvas.doc;
            if (exitDoc)
                exitDoc.endTransaction();
        }
        canvas.pathEdit = {
            active: false,
            clipId: -1,
            txOpen: false,
            txDoc: null
        };
        if (canvas.pathTool && ToolState.activeTool !== "path")
            canvas.pathTool.cancel();
    }

    // Keeps the edit session glued to clip selection: entering when a
    // path clip becomes last-selected, exiting when it doesn't, and
    // reloading idle sessions when the stored points change elsewhere
    // (inspector toggles, undo). Never reloads mid-drag: live commits
    // rewrite the clip under us and would clobber the gesture.
    function syncPathEdit() {
        if (ToolState.activeTool !== "select" || !canvas.doc) {
            if (canvas.pathEdit && canvas.pathEdit.active)
                canvas.exitPathEdit();
            return;
        }
        var c = canvas.pathEditClip();
        if (!c) {
            if (canvas.pathEdit && canvas.pathEdit.active)
                canvas.exitPathEdit();
            return;
        }
        var pe = canvas.pathEdit;
        if (!pe || !pe.active || pe.clipId !== c.id) {
            if (pe && pe.txOpen) {
                var switchDoc = pe.txDoc || canvas.doc;
                if (switchDoc)
                    switchDoc.endTransaction();
            }
            canvas.enterPathEdit(c.id);
            return;
        }
        if (pe.txOpen || (canvas.pathTool && (canvas.pathTool.dragging || canvas.pathTool.editDrag)))
            return;
        var fresh = canvas.pathAbsolute(c);
        var cur = canvas.pathTool ? canvas.pathTool.active : [];
        if (fresh.length !== cur.length) {
            canvas.pathTool.loadAbsolute(fresh);
        } else if (!canvas.pathPtsEqual(fresh, cur)) {
            canvas.pathTool.loadAbsolute(fresh);
        }
        if (canvas.pathTool)
            canvas.pathTool.showClosed = !!(c.options && c.options.closed);
    }

    // Absolute-point equality including handles/smooth: anchors-only
    // compares miss handle-only undos and leave a stale buffer.
    function pathPtsEqual(a, b) {
        if (!a || !b || a.length !== b.length)
            return false;
        for (var i = 0; i < a.length; i++) {
            var pa = a[i] || {}, pb = b[i] || {};
            if ((Number(pa.x) || 0) !== (Number(pb.x) || 0) || (Number(pa.y) || 0) !== (Number(pb.y) || 0))
                return false;
            if ((pa.smooth === true) !== (pb.smooth === true))
                return false;
            var aix = pa.inX !== undefined ? Number(pa.inX) : (Number(pa.x) || 0);
            var bix = pb.inX !== undefined ? Number(pb.inX) : (Number(pb.x) || 0);
            var aiy = pa.inY !== undefined ? Number(pa.inY) : (Number(pa.y) || 0);
            var biy = pb.inY !== undefined ? Number(pb.inY) : (Number(pb.y) || 0);
            var aox = pa.outX !== undefined ? Number(pa.outX) : (Number(pa.x) || 0);
            var box = pb.outX !== undefined ? Number(pb.outX) : (Number(pb.x) || 0);
            var aoy = pa.outY !== undefined ? Number(pa.outY) : (Number(pa.y) || 0);
            var boy = pb.outY !== undefined ? Number(pb.outY) : (Number(pb.y) || 0);
            if (aix !== bix || aiy !== biy || aox !== box || aoy !== boy)
                return false;
        }
        return true;
    }

    function commitPathEdit() {
        var pe = canvas.pathEdit;
        var d = canvas.doc;
        if (!pe || !pe.active || pe.clipId < 0 || !d || !canvas.pathTool)
            return false;
        var clip = d.animClip(pe.clipId);
        if (!clip)
            return false;
        var pts = canvas.pathTool.relativePts();
        if (pts.length < 2)
            return false;
        // Skip no-op writes (e.g. shift-toggle selection, click without
        // move): setClipOptions always checkpoints+touches, so writing
        // identical points would pollute undo and bump rev.
        var old = (clip.options && clip.options.pts) || [];
        if (canvas.pathPtsEqual(pts, old))
            return true;
        d.setClipOptions(pe.clipId, {
            pts: pts
        });
        if (d.anim.playBase)
            d.anim.seek(d.anim.currentTime);
        return true;
    }

    function beginPathEditTx() {
        var pe = canvas.pathEdit;
        if (!pe || !pe.active || pe.txOpen || !canvas.doc)
            return;
        canvas.doc.beginTransaction();
        pe.txOpen = true;
        pe.txDoc = canvas.doc;
        canvas.pathEdit = pe;
    }

    function endPathEditTx() {
        var pe = canvas.pathEdit;
        if (!pe || !pe.txOpen)
            return;
        var txDoc = pe.txDoc || canvas.doc;
        pe.txOpen = false;
        pe.txDoc = null;
        canvas.pathEdit = pe;
        if (txDoc)
            txDoc.endTransaction();
    }

    // Motion-path commit: relative points become a new Path clip at the
    // playhead (2s, easeOut) or replace a redraw target's points.
    // Empty draws (< 2 points) exit without a clip.
    function commitPathDraw() {
        if (ToolState.activeTool !== "path" || !canvas.pathTool)
            return false;
        var pts = canvas.pathTool.relativePts();
        var targetUid = ToolState.pathTargetUid;
        var clipId = ToolState.pathClipId;
        var d = canvas.doc;
        if (pts.length < 2 || !d || !d.findNode(targetUid)) {
            canvas.cancelPathDraw();
            return true;
        }
        if (clipId >= 0 && d.animClip(clipId)) {
            d.setClipOptions(clipId, {
                pts: pts
            });
            d.selectClip(clipId, false);
            // Refresh the preview frame when one is up so the canvas
            // follows the new trajectory immediately.
            if (d.anim.playBase)
                d.anim.seek(d.anim.currentTime);
        } else {
            var t0 = d.anim.currentTime;
            var made = d.applyPreset("customPath", [targetUid], t0, 2.0, "in", {
                pts: pts,
                closed: false,
                orient: false
            }, null);
            if (made.length > 0) {
                d.anim.currentTime = t0;
                d.anim.play();
            }
        }
        canvas.pathTool.cancel();
        ToolState.cancelPathDraw();
        return true;
    }
    function cancelPathDraw() {
        if (canvas.pathTool)
            canvas.pathTool.cancel();
        ToolState.cancelPathDraw();
    }
    // Image picker accept: SVGs vectorize into editable pen shapes when
    // convertible, otherwise (and all rasters) copy into the library and
    // arm placement at natural size. Failures fall back to select so the
    // tool never sticks.
    function acceptImageFile(file) {
        var flat = String(file).split("?")[0];
        if (/\.svg$/i.test(flat)) {
            var vec = LibraryStore.importSvgVectors(file);
            if (vec && vec.ok && vec.paths && vec.paths.length > 0) {
                var base = String(flat.split("/").pop() || "SVG").replace(/\.svg$/i, "");
                canvas.imageTool.setPendingVectors({
                    paths: vec.paths,
                    w: Math.max(1, Number(vec.width) || 0),
                    h: Math.max(1, Number(vec.height) || 0),
                    name: base
                });
                return;
            }
        }
        var name = LibraryStore.importImage(file);
        if (!name) {
            canvas.cancelImageTool();
            return;
        }
        var info = LibraryStore.imageInfo(name);
        var w = Number(info.width) || 400;
        var h = Number(info.height) || 300;
        // Oversized rasters stamp clamped so a 4k photo never covers the
        // scene; drags can still stretch larger.
        if (w > 800 || h > 800) {
            var k = Math.min(800 / w, 800 / h);
            w = Math.max(1, Math.round(w * k));
            h = Math.max(1, Math.round(h * k));
        }
        canvas.imageTool.setPending(name, w, h);
    }
    function cancelImageTool() {
        if (canvas.imageTool)
            canvas.imageTool.clearPending();
        ToolState.setActiveTool("select");
    }
    // Text editing pass-throughs (session lives in TextEditor).
    function beginTextEdit(uid) {
        textEditor.beginTextEdit(uid);
    }
    function commitTextEdit() {
        textEditor.commitTextEdit();
    }
    // Static-text writeback from ShapeItem paint. Editing items report
    // nothing (hidden glyphs paint zero); the editor measures instead.
    function textMeasured(uid, w, h) {
        textEditor.applyMeasured(uid, w, h);
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
            if (!canvas.panning) {
                // Hover forwarding: this catcher sits above the tool areas
                // and can own hover, so pen previews update here too.
                // Same enabled gates as penMouse/penEditMouse; both updates
                // are idempotent when the lower area already handled them.
                if (ToolState.activeTool === "pen" && canvas.doc)
                    canvas.pen.refreshHover(event.x, event.y, event.modifiers);
                else if (ToolState.activeTool === "path" && canvas.doc)
                    canvas.pathTool.refreshHover(event.x, event.y, event.modifiers);
                else if (ToolState.activeTool === "select" && canvas.penEdit.editUid >= 0 && canvas.doc)
                    canvas.penEdit.moveTo(event.x, event.y, event.modifiers);
                else if (ToolState.activeTool === "select" && canvas.pathEdit && canvas.pathEdit.active && canvas.doc)
                    canvas.pathTool.refreshHover(event.x, event.y, event.modifiers);
                return;
            }
            canvas.offsetX += event.x - mouse.lastX;
            canvas.offsetY += event.y - mouse.lastY;
            mouse.lastX = event.x;
            mouse.lastY = event.y;
        }
        onExited: {
            // Cursor left the canvas: drop previews the tool areas may
            // never see an exit for.
            if (canvas.pen)
                canvas.pen.exitHover();
            if (canvas.pathTool)
                canvas.pathTool.exitHover();
            if (canvas.penEdit)
                canvas.penEdit.hover = null;
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

    // Zoom pill, bottom-right: out, percent, in, fit. Mirrors the
    // toolbar pill language; wheel zoom stays the fine control.
    // Hiding lives in the Appearance tab (showZoomPill).
    Rectangle {
        visible: SettingsStore.showZoomPill
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: 12
            bottomMargin: 16
        }
        implicitWidth: zoomRow.implicitWidth + 16
        implicitHeight: 44
        radius: AppTheme.radiusXLarge
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        }

        RowLayout {
            id: zoomRow

            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 8
                rightMargin: 8
            }
            spacing: 4

            ToolbarButton {
                iconKind: "minimize"
                onClicked: canvas.zoomStep(-120)
            }

            Text {
                Layout.preferredWidth: 52
                horizontalAlignment: Text.AlignHCenter
                text: Math.round(canvas.zoom * 100) + "%"
                font.pixelSize: 12
                color: AppTheme.muted
            }

            ToolbarButton {
                iconKind: "plus"
                onClicked: canvas.zoomStep(120)
            }

            ToolbarButton {
                iconKind: "fit"
                onClicked: canvas.fitView()
            }
        }
    }

    // Quality picker: snapshots fresh on Render so edits always export.
    ExportQualityPopup {
        id: qualityPopup

        onRenderClicked: (quality, fps, performance, format) => canvas.startExport(quality, fps, performance, format)
    }

    // Live render progress with Cancel. Stays open on failure to show
    // the backend error; closing an idle popup just dismisses it.
    ExportProgressPopup {
        id: progressPopup

        onCancelClicked: {
            if (VideoExporter.rendering)
                VideoExporter.cancel();
            else
                progressPopup.close();
        }
    }

    // Save destination picked after a successful render (temp-then-save
    // so a dismissed dialog never leaves a stray file behind).
    // Existing destinations confirm through the shared popup before
    // saveAs runs with overwrite set.
    property url pendingSaveUrl

    FilePicker {
        id: savePicker

        saveMode: true
        suffixes: [VideoExporter.format]
        currentFolder: StandardPaths.writableLocation(StandardPaths.MoviesLocation)
        onAccepted: {
            var dest = savePicker.selectedFile;
            if (VideoExporter.destinationExists(dest)) {
                canvas.pendingSaveUrl = dest;
                overwritePopup.ask(canvas.overwriteTitle(), qsTr("“%1” already exists. Overwriting replaces it.").arg(canvas.fileName(dest)), qsTr("Overwrite"));
            } else if (!VideoExporter.saveAs(dest, false)) {
                // A failed copy must not vanish silently: the progress
                // popup is closed on this path, so reopen it to show
                // lastError.
                progressPopup.open();
            }
        }
    }

    ConfirmPopup {
        id: overwritePopup
        onConfirmed: {
            if (!VideoExporter.saveAs(canvas.pendingSaveUrl, true))
                progressPopup.open();
        }
    }

    Connections {
        target: VideoExporter
        function onSucceeded() {
            progressPopup.close();
            savePicker.currentFolder = StandardPaths.writableLocation(StandardPaths.MoviesLocation);
            savePicker.fileName = "";
            savePicker.open();
        }
        function onFailed() {
            // Progress popup stays open showing lastError with Close.
        }
        function onCancelled() {
            progressPopup.close();
        }
    }

    // Snapshot fresh and hand to the backend; the progress modal opens
    // only when the worker actually accepted the job.
    function startExport(quality, fps, performance, format) {
        if (!canvas.doc)
            return;
        qualityPopup.close();
        var scene = canvas.doc.snapshotScene();
        if (format === undefined || format === null)
            format = "mp4";
        VideoExporter.startExport(scene, quality, fps, performance, TabState.titleAt(TabState.currentIndex), format);
        // Opens in both cases: live bar on success, backend error text
        // on rejection (e.g. ffmpeg missing, already rendering).
        progressPopup.open();
    }

    function overwriteTitle() {
        if (VideoExporter.format === "gif")
            return qsTr("Overwrite image?");
        return qsTr("Overwrite video?");
    }

    function fileName(url) {
        return String(url).split("/").pop();
    }
}
