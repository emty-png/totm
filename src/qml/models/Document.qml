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

    // Creation and clipboard.
    function _makeShapeNode(type, snap) {
        return factory._makeShapeNode(type, snap);
    }
    function _makeGroupNode(name, children) {
        return factory._makeGroupNode(name, children);
    }
    function addShape(type, x, y, w, h) {
        return factory.addShape(type, x, y, w, h);
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
        clipboard.insertCopies(items);
    }
    function duplicateSelected() {
        clipboard.duplicateSelected();
    }
    function deleteSelected() {
        clipboard.deleteSelected();
    }
    function snapshotScene() {
        return clipboard.snapshotScene();
    }
    function restoreScene(scene) {
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
        selection.toggleVisible(uid);
    }
    function toggleLocked(uid) {
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
    function groupSelected() {
        return grouper.groupSelected();
    }
    function ungroupNode(uid) {
        return grouper.ungroupNode(uid);
    }
    function ungroupSelected() {
        grouper.ungroupSelected();
    }

    // Reorder.
    function _reorderInParent(parentUid, order) {
        reorderer._reorderInParent(parentUid, order);
    }
    function bringToFront() {
        reorderer.bringToFront();
    }
    function sendToBack() {
        reorderer.sendToBack();
    }
    function moveForward() {
        reorderer.moveForward();
    }
    function moveBackward() {
        reorderer.moveBackward();
    }
    function moveWithinParent(parentUid, from, to) {
        reorderer.moveWithinParent(parentUid, from, to);
    }

    // Geometry and bounds.
    function moveSelected(dx, dy) {
        edits.moveSelected(dx, dy);
    }
    function snapSelection() {
        edits.snapSelection();
    }
    function scaleSelection(orig, box0, newBox) {
        edits.scaleSelection(orig, box0, newBox);
    }
    function rotateSelected90() {
        edits.rotateSelected90();
    }
    function flipSelectedH() {
        edits.flipSelectedH();
    }
    function flipSelectedV() {
        edits.flipSelectedV();
    }
    function selectedLeafSnapshot() {
        return edits.selectedLeafSnapshot();
    }
    function setShapeProp(uid, role, value) {
        edits.setShapeProp(uid, role, value);
    }
    function setPropSelected(role, value) {
        edits.setPropSelected(role, value);
    }
    function _selectionBBox() {
        return bounds._selectionBBox();
    }
    function _setBBoxProp(role, value) {
        edits._setBBoxProp(role, value);
    }
    function recolorSelected(oldFill, newFill) {
        edits.recolorSelected(oldFill, newFill);
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
