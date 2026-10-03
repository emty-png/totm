import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Asset gallery popup content for the canvas toolbar: saved components
// with thumbnails. Emits assetPicked; the toolbar arms the pending
// asset tool and the next canvas click stamps it. Rename inline,
// delete asks for confirmation first.
Item {
    id: gallery

    required property var doc

    signal assetPicked(string assetId)

    property string filter: ""
    property string editingId: ""
    property string pendingDeleteId: ""
    property string pendingDeleteName: ""
    property int thumbSize: 300

    function askDelete(assetId, assetName) {
        gallery.pendingDeleteId = assetId;
        gallery.pendingDeleteName = assetName;
        deleteConfirm.ask(qsTr("Delete asset"), qsTr("Delete \"%1\" permanently?").arg(assetName), qsTr("Delete"));
    }

    implicitWidth: 392
    implicitHeight: 320

    function thumbScene(payload) {
        var d = gallery.doc;
        return {
            sceneWidth: d ? (Number(d.sceneWidth) || 1920) : 1920,
            sceneHeight: d ? (Number(d.sceneHeight) || 1080) : 1080,
            nodes: (payload || {}).nodes || []
        };
    }

    function filteredAssets() {
        var list = LibraryStore.assetList || [];
        var q = gallery.filter.trim().toLowerCase();
        if (q === "")
            return list;
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var nm = String(list[i].name || "").toLowerCase();
            if (nm.indexOf(q) >= 0)
                out.push(list[i]);
        }
        return out;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        TextField {
            id: searchField

            Layout.fillWidth: true
            implicitHeight: 30
            placeholderText: qsTr("Search assets")
            placeholderTextColor: AppTheme.muted
            font.pixelSize: 12
            color: AppTheme.foreground
            selectByMouse: true
            leftPadding: 10
            rightPadding: 10
            onTextChanged: {
                if (gallery.filter !== text)
                    gallery.filter = text;
            }

            background: Rectangle {
                radius: AppTheme.radiusSmall
                color: AppTheme.background
                border.width: 1
                border.color: searchField.activeFocus ? AppTheme.selection : AppTheme.fieldBorder
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    searchField.text = "";
                    gallery.forceActiveFocus();
                    event.accepted = true;
                }
            }
        }

        // Empty state.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: gallery.filteredAssets().length === 0

            Text {
                anchors.centerIn: parent
                width: parent.width - 32
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: gallery.filter !== "" ? qsTr("No assets match.") : qsTr("Nothing to see here...")
                font.pixelSize: 12
                color: AppTheme.muted
            }
        }

        GridView {
            id: grid

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: gallery.filteredAssets().length > 0
            clip: true
            cellWidth: Math.floor(width / 3)
            cellHeight: 128
            model: gallery.filteredAssets()

            delegate: Item {
                id: cell

                required property var modelData
                required property int index

                width: grid.cellWidth
                height: grid.cellHeight

                property string assetId: String((cell.modelData || {}).assetId || "")
                property string assetName: String((cell.modelData || {}).name || qsTr("Untitled"))
                property string stamp: String((cell.modelData || {}).updatedAt || "")
                property var payload: (cell.modelData || {}).payload || {}
                property bool editing: gallery.editingId !== "" && gallery.editingId === cell.assetId
                property bool hovered: cellMouse.containsMouse

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 5
                    }
                    spacing: 4

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 86
                        radius: AppTheme.radiusSmall
                        color: AppTheme.background
                        border.width: 1
                        border.color: cell.hovered ? AppTheme.selection : AppTheme.fieldBorder

                        Image {
                            id: thumb

                            anchors.fill: parent
                            anchors.margins: 4
                            fillMode: Image.PreserveAspectFit
                            source: {
                                var sc = gallery.thumbScene(cell.payload);
                                if ((sc.nodes || []).length === 0)
                                    return "";
                                return ComponentExporter.thumbnailFile(sc, "asset-" + cell.assetId, cell.stamp, gallery.thumbSize, true);
                            }
                            onStatusChanged: {
                                if (thumb.status === Image.Error)
                                    thumb.source = "";
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: thumb.status !== Image.Ready
                            text: qsTr("Empty")
                            font.pixelSize: 11
                            color: AppTheme.muted
                        }

                        // Delete on hover. Above the pick catcher so
                        // clicks land here instead of arming placement.
                        Rectangle {
                            anchors {
                                top: parent.top
                                right: parent.right
                                margins: 4
                            }
                            width: 20
                            height: 20
                            radius: 10
                            z: 2
                            color: delMouse.containsMouse ? AppTheme.closeHover : AppTheme.surface
                            border.width: 1
                            border.color: AppTheme.fieldBorder
                            visible: cell.hovered && !cell.editing

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                font.pixelSize: 13
                                color: delMouse.containsMouse ? "white" : AppTheme.muted
                            }

                            MouseArea {
                                id: delMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    mouse.accepted = true;
                                    gallery.askDelete(cell.assetId, cell.assetName);
                                }
                            }
                        }

                        MouseArea {
                            id: cellMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: gallery.assetPicked(cell.assetId)
                        }
                    }

                    // Name: double-click to rename inline.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20

                        Text {
                            anchors.fill: parent
                            visible: !cell.editing
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: cell.assetName
                            font.pixelSize: 11
                            color: AppTheme.foreground

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onDoubleClicked: gallery.editingId = cell.assetId
                            }
                        }

                        TextField {
                            anchors.fill: parent
                            visible: cell.editing
                            horizontalAlignment: TextInput.AlignHCenter
                            font.pixelSize: 11
                            text: cell.assetName
                            selectByMouse: true
                            Component.onCompleted: {
                                if (cell.editing) {
                                    forceActiveFocus();
                                    selectAll();
                                }
                            }
                            onVisibleChanged: {
                                if (visible) {
                                    forceActiveFocus();
                                    selectAll();
                                }
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    LibraryStore.renameAsset(cell.assetId, text);
                                    gallery.editingId = "";
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    gallery.editingId = "";
                                    event.accepted = true;
                                }
                            }
                            onEditingFinished: {
                                if (cell.editing) {
                                    LibraryStore.renameAsset(cell.assetId, text);
                                    gallery.editingId = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Destructive-action confirm for the × button. Modal over the
    // gallery; dismissals do nothing.
    ConfirmPopup {
        id: deleteConfirm

        onConfirmed: {
            if (gallery.pendingDeleteId !== "")
                LibraryStore.deleteAsset(gallery.pendingDeleteId);
            gallery.pendingDeleteId = "";
            gallery.pendingDeleteName = "";
        }
    }
}
