import QtCore
import QtQuick
import QtQuick.Dialogs
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

    ShapeLayer {
        doc: canvas.doc
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
        editingUid: textEditor.editingUid
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

    // Figma-style pen input: click adds corners, drag draws symmetric
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
        selectedPts: canvas.selectedPath.pts
        selectedClosed: canvas.selectedPath.closed
        showSelected: ToolState.activeTool !== "path" && canvas.selectedPath.pts.length >= 2
    }

    PenEditOverlay {
        tool: canvas.penEdit
        doc: canvas.doc
        zoom: canvas.zoom
        offsetX: canvas.offsetX
        offsetY: canvas.offsetY
        editActive: ToolState.activeTool === "select" && canvas.penEdit.editUid >= 0 && canvas.doc !== null
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
        radius: 16
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border

        Text {
            id: hintText
            anchors.centerIn: parent
            text: qsTr("Drag points/handles to edit, click to add, Del removes — Enter commits, Esc cancels")
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
        radius: 16
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border

        Text {
            id: imageHintText
            anchors.centerIn: parent
            text: qsTr("Click to place, drag for size — Esc cancels")
            font.pixelSize: 12
            color: AppTheme.foreground
        }
    }

    // Image file picker (picker-then-place). Accepts the chosen file by
    // importing a copy into the library; cancel without a pending blob
    // falls back to select so the dead tool never sticks.
    FileDialog {
        id: imagePicker

        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.webp *.gif *.svg)"), qsTr("PNG (*.png)"), qsTr("JPEG (*.jpg *.jpeg)"), qsTr("WebP (*.webp)"), qsTr("GIF (*.gif)"), qsTr("SVG (*.svg)")]
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
            if (ToolState.activeTool !== "path" && canvas.pathTool) {
                canvas.pathTool.cancel();
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
        } else if (event.key === Qt.Key_Escape) {
            if (ToolState.activeTool === "image") {
                canvas.cancelImageTool();
                event.accepted = true;
            } else if (ToolState.activeTool === "path") {
                canvas.cancelPathDraw();
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

    function computeSelectedPath() {
        var d = canvas.doc;
        var empty = {
            pts: [],
            closed: false
        };
        if (!d || ToolState.activeTool === "path")
            return empty;
        var ids = d.anim.selectedClipIds;
        if (ids.length === 0)
            return empty;
        var c = d.animClip(ids[ids.length - 1]);
        if (!c || c.preset !== "customPath")
            return empty;
        return {
            pts: canvas.pathAbsolute(c),
            closed: !!(c.options && c.options.closed)
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
        var target = d.findNode(clip.targetUid);
        if (!target)
            return [];
        var leaves = target.kind === "group" ? d._leavesUnder(target) : [target];
        if (leaves.length === 0)
            return [];
        var firstUid = leaves[0].uid;
        var ox = 0, oy = 0;
        if (d.anim && d.anim.playBase && d.anim.playBase[firstUid]) {
            ox = Number(d.anim.playBase[firstUid].x) || 0;
            oy = Number(d.anim.playBase[firstUid].y) || 0;
        } else {
            ox = Number(leaves[0].x) || 0;
            oy = Number(leaves[0].y) || 0;
        }
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
    // Image picker accept: copy into the library and arm placement at
    // natural size. Failures fall back to select so the tool never sticks.
    function acceptImageFile(file) {
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

    // Quality picker: snapshots fresh on Render so edits always export.
    ExportQualityPopup {
        id: qualityPopup

        onRenderClicked: (quality, fps, performance) => canvas.startExport(quality, fps, performance)
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
    FileDialog {
        id: saveDialog

        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("MP4 video (*.mp4)")]
        // Only the folder is preset: pointing currentFile at a
        // non-existent path warns, the typed name comes back via
        // selectedFile (saveAs appends .mp4 when missing).
        currentFolder: StandardPaths.writableLocation(StandardPaths.MoviesLocation)
        onAccepted: {
            // A failed copy must not vanish silently: the progress popup
            // is closed on this path, so reopen it to show lastError.
            if (!VideoExporter.saveAs(saveDialog.selectedFile))
                progressPopup.open();
        }
    }

    Connections {
        target: VideoExporter
        function onSucceeded() {
            progressPopup.close();
            saveDialog.open();
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
    function startExport(quality, fps, performance) {
        if (!canvas.doc)
            return;
        qualityPopup.close();
        var scene = canvas.doc.snapshotScene();
        VideoExporter.startExport(scene, quality, fps, performance, TabState.titleAt(TabState.currentIndex));
        // Opens in both cases: live bar on success, backend error text
        // on rejection (e.g. ffmpeg missing, already rendering).
        progressPopup.open();
    }
}
