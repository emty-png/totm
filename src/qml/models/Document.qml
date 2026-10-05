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

    // Persistent ruler guides in content px (vertical x positions and
    // horizontal y positions). Plain session chrome like the camera:
    // saved with the scene, but never in undo history.
    property var guideX: []
    property var guideY: []

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
    property var booleaner: DocBoolean {
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
    property var propCopy: DocPropCopy {
        doc: root
    }
    property var assets: DocAssets {
        doc: root
    }

    readonly property bool canUndo: root.history.canUndo
    readonly property bool canRedo: root.history.canRedo

    function touch() {
        root.rev++;
    }

    // Ruler guides: wholesale reassigns so bindings fire (same rule as
    // the node tree). Positions round to whole content px; duplicates
    // within half a px collapse onto the existing index. No history
    // entries by design. addGuide returns the guide index for drags.
    function addGuide(axis, pos) {
        var p = Math.round(Number(pos) || 0);
        if (axis === "x") {
            for (var i = 0; i < root.guideX.length; i++) {
                if (Math.abs(root.guideX[i] - p) < 0.5)
                    return i;
            }
            root.guideX = root.guideX.concat([p]);
            return root.guideX.length - 1;
        }
        for (var j = 0; j < root.guideY.length; j++) {
            if (Math.abs(root.guideY[j] - p) < 0.5)
                return j;
        }
        root.guideY = root.guideY.concat([p]);
        return root.guideY.length - 1;
    }

    function moveGuide(axis, index, pos) {
        var p = Math.round(Number(pos) || 0);
        if (axis === "x") {
            if (index < 0 || index >= root.guideX.length)
                return;
            var xs = root.guideX.slice();
            xs[index] = p;
            root.guideX = xs;
        } else {
            if (index < 0 || index >= root.guideY.length)
                return;
            var ys = root.guideY.slice();
            ys[index] = p;
            root.guideY = ys;
        }
    }

    function removeGuide(axis, index) {
        if (axis === "x") {
            if (index < 0 || index >= root.guideX.length)
                return;
            var xs = root.guideX.slice();
            xs.splice(index, 1);
            root.guideX = xs;
        } else {
            if (index < 0 || index >= root.guideY.length)
                return;
            var ys = root.guideY.slice();
            ys.splice(index, 1);
            root.guideY = ys;
        }
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
        case "video":
            return "Video";
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
    function applyPreset(presetId, targetUids, t0, duration, mode, options, easing, stagger) {
        return anim.applyPreset(presetId, targetUids, t0, duration, mode, options, easing, stagger);
    }
    function setClipOptions(id, patch) {
        return anim.setClipOptions(id, patch);
    }
    function convertClipPreset(id, newPreset) {
        return anim.convertClipPreset(id, newPreset);
    }
    function retimeClip(id, t0, duration) {
        return anim.retimeClip(id, t0, duration);
    }
    function nudgeClip(id, t0, duration) {
        return anim.nudgeClip(id, t0, duration);
    }
    function nudgeKey(id, keyIndex, t) {
        return anim.nudgeKey(id, keyIndex, t);
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
    function duplicateClips(ids) {
        return anim.duplicateClips(ids);
    }
    function copyClips(ids) {
        return anim.copyClips(ids);
    }
    function copySelectedClips() {
        return anim.copySelectedClips();
    }
    function pasteClips(templates, targetUids, baseTime) {
        return anim.pasteClips(templates, targetUids, baseTime);
    }
    // Panel three-dot copy/paste (DocPropCopy checkpoints internally
    // after validating, so these stay thin pass-throughs).
    function canCopyDesign() {
        return propCopy.canCopyDesign();
    }
    function copyDesignProps(mode) {
        return propCopy.copyDesign(mode);
    }
    function canPasteDesign() {
        return propCopy.canPasteDesign();
    }
    function pasteDesignProps(mode) {
        return propCopy.pasteDesign(mode);
    }
    function canCopyAnimClips(ids) {
        return propCopy.canCopyAnim(ids);
    }
    function copyAnimClips(mode, ids) {
        return propCopy.copyAnim(mode, ids);
    }
    function canPasteAnimClips(targetUids) {
        return propCopy.canPasteAnim(targetUids);
    }
    function pasteAnimClips(mode, targetUids) {
        return propCopy.pasteAnim(mode, targetUids);
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
    function nudgeAudioTrim(id, t0, offset, duration) {
        return audio.nudgeTrim(id, t0, offset, duration);
    }
    // Silent in-place timeline-start nudge for video lane drags: no
    // checkpoint, no touch; release touches once for the single entry.
    // Mirrors audio.nudge (clamped to the composition start). Refreshes
    // the open preview base so seeks after a paused drag read the new
    // start instead of the stale pre-drag one.
    function nudgeVideoStart(uid, t) {
        var n = findNode(uid);
        if (!n || n.kind !== "shape" || n.shapeType !== "video")
            return false;
        var nt = Math.max(0, Number(t) || 0);
        if (isNaN(nt) || n.videoStart === nt)
            return false;
        n.videoStart = nt;
        if (root.anim.playBase && root.anim.playBase[uid])
            root.anim.playBase[uid].videoStart = nt;
        return true;
    }
    function deleteAudioClips(ids) {
        return audio.deleteClips(ids);
    }
    function deleteSelectedAudio() {
        return audio.deleteSelected();
    }
    function duplicateAudioClips(ids) {
        return audio.duplicateClips(ids);
    }
    function duplicateSelectedAudio() {
        return audio.duplicateSelected();
    }
    function copyAudioClips(ids) {
        return audio.copyClips(ids);
    }
    function copySelectedAudio() {
        return audio.copySelectedClips();
    }
    function pasteAudioClips(templates, baseTime) {
        return audio.pasteClips(templates, baseTime);
    }
    function splitAudioClip(id, t) {
        return audio.splitClip(id, t);
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
    function visibleRowListFiltered(filter) {
        return layers.visibleRowListFiltered(filter);
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
    function _makeGroupNode(name, children, snap) {
        return factory._makeGroupNode(name, children, snap);
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
    function importSvgPaths(entries, groupName, baseX, baseY, scaleX, scaleY) {
        history.checkpoint();
        return factory.importSvgPaths(entries, groupName, baseX, baseY, scaleX, scaleY);
    }
    function addImage(imageSource, x, y, w, h) {
        history.checkpoint();
        return factory.addImage(imageSource, x, y, w, h);
    }
    function addVideo(videoSource, x, y, w, h, videoDuration, videoFit, videoName) {
        history.checkpoint();
        return factory.addVideo(videoSource, x, y, w, h, videoDuration, videoFit, videoName);
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
    function assetPayload(includeAnims) {
        return assets.assetPayload(includeAnims);
    }
    function suggestedAssetName() {
        return assets.suggestedName();
    }
    function insertAsset(payload, atX, atY) {
        history.checkpoint();
        return assets.insertAsset(payload, atX, atY);
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
    function canUseAsMask() {
        return grouper.canUseAsMask();
    }
    function canReleaseMask() {
        return grouper.canReleaseMask();
    }
    function useAsMask() {
        return grouper.useAsMask();
    }
    function releaseMask() {
        grouper.releaseMask();
    }
    function maskUidsForLeaf(uid) {
        return tree.maskUidsForLeaf(uid);
    }
    function isMaskedLeaf(uid) {
        return tree.isMaskedLeaf(uid);
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

    // Live boolean groups.
    function canCombine() {
        return booleaner.canCombine();
    }
    function canReleaseBoolean() {
        return booleaner.canReleaseBoolean();
    }
    function isBooleanGroup(node) {
        return booleaner.isBooleanGroup(node);
    }
    function combineSelected(op) {
        if (!booleaner.canCombine())
            return -1;
        history.checkpoint();
        return booleaner.combineSelected(op);
    }
    function setBoolOp(uid, op) {
        var n = findNode(uid);
        if (!n || n.kind !== "group")
            return false;
        // No-op clicks (e.g. the active op) skip the checkpoint so no
        // empty undo entry lands on the stack.
        if (String(n.boolOp ?? "none").toLowerCase() === String(op ?? "").toLowerCase())
            return true;
        history.checkpoint();
        return booleaner.setBoolOp(uid, op);
    }
    function releaseBoolean() {
        if (!booleaner.canReleaseBoolean())
            return;
        history.checkpoint();
        booleaner.releaseSelected();
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
    function canBringToFront() {
        return reorderer.canBringToFront();
    }
    function canSendToBack() {
        return reorderer.canSendToBack();
    }
    function canMoveForward() {
        return reorderer.canMoveForward();
    }
    function canMoveBackward() {
        return reorderer.canMoveBackward();
    }
    function moveWithinParent(parentUid, from, to) {
        history.checkpoint();
        reorderer.moveWithinParent(parentUid, from, to);
    }

    // Geometry and bounds. Selection edits auto-capture keys at the
    // playhead while record is armed (one undo entry: the pre-checkpoint
    // or the outer gesture owns it, autocapture stays silent).
    function moveSelected(dx, dy) {
        history.checkpoint();
        edits.moveSelected(dx, dy);
        anim.autocapture();
    }
    function snapSelection() {
        edits.snapSelection();
    }
    function scaleSelection(orig, box0, newBox) {
        history.checkpoint();
        edits.scaleSelection(orig, box0, newBox);
        anim.autocapture();
    }
    function rotateSelected90() {
        history.checkpoint();
        edits.rotateSelected90();
        anim.autocapture();
    }
    function flipSelectedH() {
        history.checkpoint();
        edits.flipSelectedH();
        anim.autocapture();
    }
    function flipSelectedV() {
        history.checkpoint();
        edits.flipSelectedV();
        anim.autocapture();
    }
    function alignSelected(mode) {
        // Pre-check before checkpoint so single selections never stage
        // an empty undo entry; edits re-validates locks/bounds.
        if (selectedTops().length < 2)
            return false;
        if (["hLeft", "hCenter", "hRight", "vTop", "vMiddle", "vBottom"].indexOf(mode) < 0)
            return false;
        history.checkpoint();
        var aligned = edits.alignSelection(mode);
        anim.autocapture();
        return aligned;
    }
    function distributeSelected(axis) {
        if (selectedTops().length < 3)
            return false;
        if (axis !== "h" && axis !== "v")
            return false;
        history.checkpoint();
        var spread = edits.distributeSelected(axis);
        anim.autocapture();
        return spread;
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
        anim.autocapture();
    }
    // Style targets for panel effect edits: selected leaves, or the
    // single selected group itself (see DocEdits.styleTargets).
    function styleTargets() {
        return edits.styleTargets();
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
    function addFillToSelected() {
        history.checkpoint();
        edits.addFillToSelected();
    }
    function addStrokeToSelected() {
        history.checkpoint();
        edits.addStrokeToSelected();
    }
    function removeFillAt(uid, index) {
        history.checkpoint();
        edits.removeFillAt(uid, index);
    }
    function removeStrokeAt(uid, index) {
        history.checkpoint();
        edits.removeStrokeAt(uid, index);
    }
    function moveFill(uid, from, to) {
        history.checkpoint();
        edits.moveFill(uid, from, to);
    }
    function moveStroke(uid, from, to) {
        history.checkpoint();
        edits.moveStroke(uid, from, to);
    }
    function setFillEntry(uid, index, patch) {
        history.checkpoint();
        edits.setFillEntry(uid, index, patch);
    }
    function setStrokeEntry(uid, index, patch) {
        history.checkpoint();
        edits.setStrokeEntry(uid, index, patch);
    }
    function patchFillAtSelected(at, patch) {
        history.checkpoint();
        edits.patchFillAtSelected(at, patch);
    }
    function patchStrokeAtSelected(at, patch) {
        history.checkpoint();
        edits.patchStrokeAtSelected(at, patch);
    }
    function toggleFillAtSelected(at) {
        history.checkpoint();
        edits.toggleFillAtSelected(at);
    }
    function toggleStrokeAtSelected(at) {
        history.checkpoint();
        edits.toggleStrokeAtSelected(at);
    }
    function moveFillAtSelected(at, delta) {
        history.checkpoint();
        edits.moveFillAtSelected(at, delta);
    }
    function moveStrokeAtSelected(at, delta) {
        history.checkpoint();
        edits.moveStrokeAtSelected(at, delta);
    }
    function removeFillAtSelected(at) {
        history.checkpoint();
        edits.removeFillAtSelected(at);
    }
    function removeStrokeAtSelected(at) {
        history.checkpoint();
        edits.removeStrokeAtSelected(at);
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
    function setPenClosed(closed) {
        history.checkpoint();
        return penOps.setClosedSelected(closed);
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
