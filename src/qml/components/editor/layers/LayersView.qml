import QtQuick
import QtQuick.Layouts
import Totm

// Layers list for the active document. Header plus one row per visible
// node, top-first. Click selects, Shift ranges, Ctrl toggles. Plain
// drags reorder within the same parent. Model rebuilds on structure
// only so delegates survive selection churn.
ColumnLayout {
    id: layersView

    required property var doc
    property var contextPolicy: null

    property bool suppressClick: false
    property bool dragArming: false
    property bool dragging: false
    property int dragUid: -1
    property int dragParentUid: -2
    property real dragPressY: 0
    property real dragLiftY: 0
    property int dropIndex: -1
    property real dropY: 0
    property bool dropValid: false

    property var reorder: LayersReorder {
        view: layersView
        rows: rows
    }

    spacing: 0

    LayersHeader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        doc: layersView.doc
    }

    Repeater {
        id: rows
        model: layersView.doc ? layersView.doc.visibleRowList() : []

        onItemAdded: (index, item) => {
            item.clickPolicy = (uid, mods) => {
                if (layersView.suppressClick) {
                    layersView.suppressClick = false;
                    return;
                }
                layersView.forceActiveFocus();
                if (!layersView.doc)
                    return;
                var shift = !!(mods & Qt.ShiftModifier);
                var ctrl = !!(mods & (Qt.ControlModifier | Qt.MetaModifier));
                if (shift && ctrl)
                    layersView.doc.addRange(uid);
                else if (shift)
                    layersView.doc.selectRange(uid);
                else if (ctrl)
                    layersView.doc.toggleSelect(uid);
                else
                    layersView.doc.selectOnly(uid);
            };
            item.eyePolicy = uid => {
                layersView.forceActiveFocus();
                if (layersView.doc)
                    layersView.doc.toggleVisible(uid);
            };
            item.lockPolicy = uid => {
                layersView.forceActiveFocus();
                if (layersView.doc)
                    layersView.doc.toggleLocked(uid);
            };
            item.togglePolicy = uid => {
                layersView.forceActiveFocus();
                if (layersView.doc)
                    layersView.doc.toggleExpanded(uid);
            };
            item.commitPolicy = (uid, name) => {
                if (layersView.doc)
                    layersView.doc.commitRename(uid, name);
            };
            item.cancelPolicy = uid => {
                if (layersView.doc)
                    layersView.doc.cancelRename(uid);
            };
            item.renamePolicy = uid => {
                if (layersView.doc)
                    layersView.doc.beginRename(uid);
            };
            item.contextPolicy = (uid, lx, ly) => {
                layersView.forceActiveFocus();
                if (layersView.doc && !layersView.doc.isSelected(uid))
                    layersView.doc.selectOnly(uid);
                var p = item.mapToItem(layersView, lx, ly);
                if (layersView.contextPolicy)
                    layersView.contextPolicy(uid, p.x, p.y);
            };
            item.dragPressPolicy = (uid, lx, ly, mods) => {
                var p = item.mapToItem(layersView, lx, ly);
                layersView.dragPress(uid, p.y, mods);
            };
            item.dragMovePolicy = (uid, lx, ly) => {
                var p = item.mapToItem(layersView, lx, ly);
                layersView.dragMove(p.y);
            };
            item.dragReleasePolicy = () => layersView.dragRelease();
        }

        LayersRow {
            selected: modelData.node.selected
            rowName: modelData.node.name
            rowType: modelData.node.shapeType
            rowUid: modelData.node.uid
            rowVisible: modelData.node.visible
            rowLocked: modelData.node.locked
            editing: modelData.node.renaming
            isGroup: modelData.node.kind === "group"
            nodeExpanded: modelData.node.expanded
            indent: modelData.level
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    function dragPress(uid, y, mods) {
        reorder.dragPress(uid, y, mods);
    }
    function dragMove(y) {
        reorder.dragMove(y);
    }
    function dragRelease() {
        reorder.dragRelease();
    }
}
