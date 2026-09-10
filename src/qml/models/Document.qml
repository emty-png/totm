import QtQuick
import Totm

// One tab's document. Owns the node tree and per-tab camera, delegates
// work to focused helpers under models/document/. Root children stay
// top-first (index 0 paints highest); geometry mutates in place while
// structural ops reassign arrays wholesale so bindings fire.
QtObject {
    id: root

    property int uid: -1
    property real sceneWidth: 1920
    property real sceneHeight: 1080
    property color sceneColor: "#ffffff"
    property bool centered: false

    property real camZoom: 1
    property real camX: 0
    property real camY: 0

    property int rev: 0
    property int nextNodeUid: 1
    property int structRev: 0
    property int anchorUid: -1
    property var drillPath: []
    property var rootChildren: []
    property var leafList: []

    readonly property Component nodeFactory: Component {
        DocNode {}
    }

    property var tree: DocTree {
        doc: root
    }
    property var effective: DocEffective {
        doc: root
    }
    property var layers: DocLayersModel {
        doc: root
    }
    property var drill: DocDrill {
        doc: root
    }
    property var clipboard: DocClipboard {
        doc: root
    }
    property var factory: DocFactory {
        doc: root
    }
    property var selection: DocSelection {
        doc: root
    }
    property var renamer: DocRename {
        doc: root
    }
    property var grouper: DocGroup {
        doc: root
    }
    property var reorderer: DocReorder {
        doc: root
    }
    property var bounds: DocBounds {
        doc: root
    }
    property var edits: DocEdits {
        doc: root
    }
    property var penOps: DocPen {
        doc: root
    }
    property var corners: DocCorners {
        doc: root
    }
    property var history: DocHistory {
        doc: root
    }
    property var anim: DocAnim {
        doc: root
    }
    property var audio: DocAudio {
        doc: root
    }

    readonly property bool canUndo: root.history.canUndo
    readonly property bool canRedo: root.history.canRedo

    function touch() {
        root.rev++;
    }

    function shapeLabel(type) {
        switch (type) {
        case "ellipse":
            return "Ellipse";
        case "triangle":
            return "Triangle";
        case "star":
            return "Star";
        case "text":
            return "Text";
        case "pen":
            return "Path";
        case "image":
            return "Image";
        case "group":
            return "Group";
        default:
            return "Rectangle";
        }
    }

    function _refreshStructural() {
        layers.renumberZ();
        root.leafList = tree.allLeaves();
        root.structRev++;
        touch();
    }

    // History (undo/redo). Checkpoint before mutations; gestures
    // use begin/end to coalesce into one entry.
    function beginTransaction() {
        history.begin();
    }
    function beginPassiveTransaction() {
        history.beginPassive();
    }
    function endTransaction() {
        history.end();
    }
    function undo() {
        history.undo();
    }
    function redo() {
        history.redo();
    }
    function clearHistory() {
        history.clear();
    }

    // Animation. DocAnim checkpoints internally after validating, so
    // these stay thin pass-throughs (never double-checkpoint here).
    function applyPreset(presetId, targetUids, t0, duration, mode, options, easing) {
        return anim.applyPreset(presetId, targetUids, t0, duration, mode, options, easing);
    }
    function setClipOptions(id, patch) {
        return anim.setClipOptions(id, patch);
    }
    function retimeClip(id, t0, duration) {
        return anim.retimeClip(id, t0, duration);
    }
    function nudgeClip(id, t0, duration) {
        return anim.nudgeClip(id, t0, duration);
    }
    function setClipEasing(id, easing) {
        return anim.setClipEasing(id, easing);
    }
    function setClipMode(id, mode) {
        return anim.setClipMode(id, mode);
    }
    function deleteClips(ids) {
        return anim.deleteClips(ids);
    }
    function deleteSelectedClips() {
        return anim.deleteSelectedClips();
    }
    function setAnimDuration(v) {
        return anim.setDuration(v);
    }
    function selectClip(id, additive) {
        anim.selectClip(id, additive);
    }
    function clearClipSelection() {
        anim.clearClipSelection();
    }
    function animClip(id) {
        return anim.clipById(id);
    }
    function seekPlayhead(t) {
        anim.seek(t);
    }

    // Audio. DocAudio checkpoints internally after validating, so these
    // stay thin pass-throughs (never double-checkpoint here).
    function addAudioClip(source, t0, fileDuration) {
        return audio.addClip(source, t0, fileDuration);
    }
    function moveAudioClip(id, t0) {
        return audio.moveClip(id, t0);
    }
    function nudgeAudioClip(id, t0) {
        return audio.nudge(id, t0);
    }
    function deleteAudioClips(ids) {
        return audio.deleteClips(ids);
    }
    function deleteSelectedAudio() {
        return audio.deleteSelected();
    }
    function selectAudioClip(id, additive) {
        audio.selectClip(id, additive);
    }
    function addAudioSelection(id) {
        audio.addToSelection(id);
    }
    function clearAudioSelection() {
        audio.clearSelection();
    }
    function setAudioProp(role, value) {
        return audio.setProp(role, value);
    }
    function toggleAudioMuted() {
        return audio.toggleMuted();
    }
    function replaceAudioSource(source, fileDuration) {
        return audio.replaceSource(source, fileDuration);
    }
    function audioCommon(role) {
        return audio.commonOf(role);
    }
    function selectedAudioClips() {
        return audio.selectedList();
    }
    function audioClip(id) {
        return audio.clipById(id);
    }

    // Tree navigation.
    function _find(uid, nodes, parent, parentUid, ancestors) {
        return tree._find(uid, nodes, parent, parentUid, ancestors);
    }
    function findNode(uid) {
        return tree.findNode(uid);
    }
    function _childrenOf(parentUid) {
        return tree._childrenOf(parentUid);
    }
    function _setChildren(parentUid, arr) {
        tree._setChildren(parentUid, arr);
    }
    function _allNodes() {
        return tree._allNodes();
    }
    function _leavesUnder(node) {
        return tree._leavesUnder(node);
    }
    function allLeaves() {
        return tree.allLeaves();
    }
    function selectedTops() {
        return tree.selectedTops();
    }
    function _selectedLeaves() {
        return tree._selectedLeaves();
    }
    function _isDirectChildOf(uid, containerUid) {
        return tree._isDirectChildOf(uid, containerUid);
    }
    function _isDescendantOf(uid, containerUid) {
        return tree._isDescendantOf(uid, containerUid);
    }

    // Visibility and locks inherit down the tree.
    function isEffectivelyVisible(node) {
        return effective.isEffectivelyVisible(node);
    }
    function isEffectivelyLocked(node) {
        return effective.isEffectivelyLocked(node);
    }

    // Layers model and paint order.
    function renumberZ() {
        layers.renumberZ();
    }
    function totalCount() {
        return layers.totalCount();
    }
    function visibleRows() {
        return layers.visibleRows();
    }
    function visibleRowList() {
        return layers.visibleRowList();
    }
    function dropTargetForGap(gap) {
        return layers.dropTargetForGap(gap);
    }

    // Drill path.
    function _activeContainerUid() {
        return drill._activeContainerUid();
    }
    function activeContainerNode() {
        return drill.activeContainerNode();
    }
    function resolvePress(uid) {
        return drill.resolvePress(uid);
    }
    function drillInto(uid) {
        drill.drillInto(uid);
    }
    function drillOut() {
        return drill.drillOut();
    }
    function drillTo(uid) {
        drill.drillTo(uid);
    }
    function pruneDrillPath() {
        drill.pruneDrillPath();
    }

    // Creation and clipboard.
    function _makeShapeNode(type, snap) {
        return factory._makeShapeNode(type, snap);
    }
    function _makeGroupNode(name, children) {
        return factory._makeGroupNode(name, children);
    }
    function addShape(type, x, y, w, h) {
        history.checkpoint();
        return factory.addShape(type, x, y, w, h);
    }
    function addText(x, y, w, h, auto) {
        history.checkpoint();
        return factory.addText(x, y, w, h, auto);
    }
    function addPen(pathData) {
        history.checkpoint();
        return factory.addPen(pathData);
    }
    function addImage(imageSource, x, y, w, h) {
        history.checkpoint();
        return factory.addImage(imageSource, x, y, w, h);
    }
    function snapshotNode(node) {
        return clipboard.snapshotNode(node);
    }
    function _instantiateSnapshot(snap, select) {
        return clipboard._instantiateSnapshot(snap, select);
    }
    function copySelected() {
        return clipboard.copySelected();
    }
    function insertCopies(items) {
        history.checkpoint();
        clipboard.insertCopies(items);
    }
    function duplicateSelected() {
        history.checkpoint();
        clipboard.duplicateSelected();
    }
    function deleteSelected() {
        history.checkpoint();
        clipboard.deleteSelected();
        anim.pruneTargets();
    }
    function snapshotScene() {
        return clipboard.snapshotScene();
    }
    function restoreScene(scene) {
        // Fresh loads clear history; undo/redo restores bypass this
        // wrapper and call the clipboard directly.
        if (!history.applying)
            history.clear();
        clipboard.restoreScene(scene);
    }

    // Selection and flags.
    function isSelected(uid) {
        return selection.isSelected(uid);
    }
    function clearSelection() {
        selection.clearSelection();
    }
    function clearSelectionSilent() {
        selection.clearSelectionSilent();
    }
    function selectOnly(uid) {
        selection.selectOnly(uid);
    }
    function addToSelection(uid) {
        selection.addToSelection(uid);
    }
    function toggleSelect(uid) {
        selection.toggleSelect(uid);
    }
    function selectRange(uid) {
        selection.selectRange(uid);
    }
    function addRange(uid) {
        selection.addRange(uid);
    }
    function toggleVisible(uid) {
        history.checkpoint();
        selection.toggleVisible(uid);
    }
    function toggleLocked(uid) {
        history.checkpoint();
        selection.toggleLocked(uid);
    }
    function toggleExpanded(uid) {
        selection.toggleExpanded(uid);
    }
    function selectInRect(rx, ry, rw, rh, additive) {
        selection.selectInRect(rx, ry, rw, rh, additive);
    }

    // Rename.
    function beginRename(uid) {
        renamer.beginRename(uid);
    }
    function commitRename(uid, name) {
        history.checkpoint();
        renamer.commitRename(uid, name);
    }
    function cancelRename(uid) {
        renamer.cancelRename(uid);
    }

    // Grouping.
    function canGroup() {
        return grouper.canGroup();
    }
    function canUngroup() {
        return grouper.canUngroup();
    }
    function groupSelected() {
        history.checkpoint();
        return grouper.groupSelected();
    }
    function ungroupNode(uid) {
        history.checkpoint();
        var done = grouper.ungroupNode(uid);
        anim.pruneTargets();
        return done;
    }
    function ungroupSelected() {
        history.checkpoint();
        grouper.ungroupSelected();
        anim.pruneTargets();
    }

    // Reorder.
    function _reorderInParent(parentUid, order) {
        reorderer._reorderInParent(parentUid, order);
    }
    function bringToFront() {
        history.checkpoint();
        reorderer.bringToFront();
    }
    function sendToBack() {
        history.checkpoint();
        reorderer.sendToBack();
    }
    function moveForward() {
        history.checkpoint();
        reorderer.moveForward();
    }
    function moveBackward() {
        history.checkpoint();
        reorderer.moveBackward();
    }
    function moveWithinParent(parentUid, from, to) {
        history.checkpoint();
        reorderer.moveWithinParent(parentUid, from, to);
    }

    // Geometry and bounds.
    function moveSelected(dx, dy) {
        history.checkpoint();
        edits.moveSelected(dx, dy);
    }
    function snapSelection() {
        edits.snapSelection();
    }
    function scaleSelection(orig, box0, newBox) {
        history.checkpoint();
        edits.scaleSelection(orig, box0, newBox);
    }
    function rotateSelected90() {
        history.checkpoint();
        edits.rotateSelected90();
    }
    function flipSelectedH() {
        history.checkpoint();
        edits.flipSelectedH();
    }
    function flipSelectedV() {
        history.checkpoint();
        edits.flipSelectedV();
    }
    function selectedLeafSnapshot() {
        return edits.selectedLeafSnapshot();
    }
    function setShapeProp(uid, role, value) {
        history.checkpoint();
        edits.setShapeProp(uid, role, value);
    }
    function setPropSelected(role, value) {
        history.checkpoint();
        edits.setPropSelected(role, value);
    }
    function _selectionBBox() {
        return bounds._selectionBBox();
    }
    function _setBBoxProp(role, value) {
        edits._setBBoxProp(role, value);
    }
    function recolorSelected(oldFill, newFill) {
        history.checkpoint();
        edits.recolorSelected(oldFill, newFill);
    }
    function penMovePoint(uid, sub, idx, dx, dy) {
        history.checkpoint();
        return penOps.movePoint(uid, sub, idx, dx, dy);
    }
    function penMoveHandle(uid, sub, idx, which, x, y) {
        history.checkpoint();
        return penOps.moveHandle(uid, sub, idx, which, x, y);
    }
    function penToggleSmooth(uid, sub, idx) {
        history.checkpoint();
        return penOps.toggleSmooth(uid, sub, idx);
    }
    function penInsertPoint(uid, sub, at, pt) {
        history.checkpoint();
        return penOps.insertPoint(uid, sub, at, pt);
    }
    function penDeletePoint(uid, sub, idx) {
        history.checkpoint();
        return penOps.deletePoint(uid, sub, idx);
    }
    function toggleIndependentCorners(on) {
        history.checkpoint();
        var tops = selectedTops();
        for (var i = 0; i < tops.length; i++) {
            var leaves = _leavesUnder(tops[i]);
            for (var j = 0; j < leaves.length; j++) {
                if (!isEffectivelyLocked(leaves[j]))
                    corners.toggle(leaves[j].uid, on);
            }
        }
    }
    function setUniformRadius(value) {
        history.checkpoint();
        var tops = selectedTops();
        for (var i = 0; i < tops.length; i++) {
            var leaves = _leavesUnder(tops[i]);
            for (var j = 0; j < leaves.length; j++) {
                if (!isEffectivelyLocked(leaves[j]))
                    corners.setUniform(leaves[j].uid, value);
            }
        }
    }
    function setCornerRadius(index, value) {
        history.checkpoint();
        var tops = selectedTops();
        for (var i = 0; i < tops.length; i++) {
            var leaves = _leavesUnder(tops[i]);
            for (var j = 0; j < leaves.length; j++) {
                if (!isEffectivelyLocked(leaves[j]))
                    corners.setCorner(leaves[j].uid, index, value);
            }
        }
    }
    function rotatedBounds(s) {
        return bounds.rotatedBounds(s);
    }
    function bboxOfNode(node) {
        return bounds.bboxOfNode(node);
    }
    function selectionBBox() {
        return bounds.selectionBBox();
    }
    function unselectedSnapBoxes() {
        return bounds.unselectedSnapBoxes();
    }
}
