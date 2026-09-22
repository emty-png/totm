import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Layers list for the active document. Fixed header (title + search) up
// top, rows in a scroller below. Click selects, Shift ranges, Ctrl
// toggles. Plain drags reorder within the same parent. Model rebuilds
// on structure only so delegates survive selection churn.
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

    // Layers search state. Owned here; the header field reports through
    // filterPolicy (clearing its field on doc switch resets this via
    // the policy). Filtering auto-expands groups (see the model) and
    // suspends drag-reorder, whose gap math assumes the full list.
    property string filter: ""
    readonly property bool filtering: layersView.filter.trim() !== ""

    spacing: 0

    LayersHeader {
        Layout.fillWidth: true
        // Stretch only for the empty-library state so the placeholder
        // centers; otherwise the row scroller takes the space.
        Layout.fillHeight: !layersView.doc || layersView.doc.totalCount() === 0
        doc: layersView.doc
        filterPolicy: text => {
            if (layersView.filter !== text)
                layersView.filter = text;
        }
    }

    ScrollView {
        id: rowScroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: layersView.doc && layersView.doc.totalCount() > 0
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: rowScroll.availableWidth
            // Stretch to the viewport so the empty filler below absorbs
            // slack and keeps empty-area click handling across the panel.
            height: Math.max(implicitHeight, rowScroll.availableHeight)
            spacing: 0

            Repeater {
                id: rows
                model: layersView.doc ? layersView.doc.visibleRowListFiltered(layersView.filter) : []

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

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 12
                visible: layersView.filtering && rows.count === 0 && layersView.doc && layersView.doc.totalCount() > 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: qsTr("No layers match the search.")
                font.pixelSize: 13
                color: AppTheme.muted
            }

            // Empty-area clicks: the scroller eats presses that used to fall
            // through to the panel, so deselect and the empty context menu
            // live here now (same behavior as the panel behind).
            Item {
                id: emptyFill

                Layout.fillWidth: true
                Layout.fillHeight: true

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        emptyFill.forceActiveFocus();
                        if (layersView.doc)
                            layersView.doc.clearSelection();
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onPressed: mouse => {
                        if (layersView.contextPolicy) {
                            var p = emptyFill.mapToItem(layersView, mouse.x, mouse.y);
                            layersView.contextPolicy(-1, p.x, p.y);
                        }
                    }
                }
            }
        }
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
