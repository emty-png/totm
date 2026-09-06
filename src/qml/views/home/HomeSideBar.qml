import QtQuick
import QtQuick.Layouts
import Totm

// Home sidebar: workspace list plus pinned starred designs. Starred
// rows open on click; starring itself happens on the card.
Item {
    id: sideBar

    required property string selectedWorkspaceId
    property string editingWorkspaceId: ""

    property var selectPolicy: null
    property var movePolicy: null
    property var openPolicy: null

    // Starred designs, newest first. Cached stable for the Repeater
    // (fresh arrays every read churn delegates).
    property var starredDesigns: []

    function refreshStarred() {
        var out = [];
        var all = LibraryStore.designList;
        for (var i = 0; i < all.length; i++) {
            if (all[i].starred)
                out.push(all[i]);
        }
        sideBar.starredDesigns = out;
    }

    Component.onCompleted: sideBar.refreshStarred()

    Connections {
        target: LibraryStore
        function onLibraryChanged() {
            sideBar.refreshStarred();
        }
    }

    implicitWidth: 230
    implicitHeight: 200

    Rectangle {
        anchors.fill: parent
        color: AppTheme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 8
            Layout.topMargin: 10
            Layout.bottomMargin: 6
            text: qsTr("Workspaces")
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: AppTheme.foreground
        }

        Repeater {
            model: LibraryStore.workspaceList

            WorkspaceRow {
                workspaceId: modelData.workspaceId
                workspaceName: modelData.name
                isDefault: modelData.isDefault
                selected: modelData.workspaceId === sideBar.selectedWorkspaceId
                editing: modelData.workspaceId === sideBar.editingWorkspaceId
                selectPolicy: id => {
                    if (sideBar.selectPolicy)
                        sideBar.selectPolicy(id);
                }
                beginRenamePolicy: id => {
                    sideBar.editingWorkspaceId = id;
                }
                commitPolicy: (id, text) => {
                    LibraryStore.renameWorkspace(id, text);
                    sideBar.editingWorkspaceId = "";
                }
                cancelPolicy: () => {
                    sideBar.editingWorkspaceId = "";
                }
                deletePolicy: id => {
                    if (id === sideBar.selectedWorkspaceId && sideBar.selectPolicy)
                        sideBar.selectPolicy(LibraryStore.defaultWorkspaceId);
                    LibraryStore.deleteWorkspace(id);
                }
                movePolicy: (idsJson, wsId) => {
                    if (sideBar.movePolicy)
                        sideBar.movePolicy(idsJson, wsId);
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 8
            Layout.topMargin: 10
            Layout.bottomMargin: 6
            visible: sideBar.starredDesigns.length > 0
            text: qsTr("Starred")
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: AppTheme.foreground
        }

        // Inline rows (not a separate component): Repeater delegates in
        // their own file cannot see modelData, so the pinned rows live
        // here where the model context attaches.
        Repeater {
            model: sideBar.starredDesigns

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 32

                readonly property bool hovered: starRowMouse.containsMouse

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.topMargin: 2
                    anchors.bottomMargin: 2
                    radius: 6
                    color: parent.hovered ? AppTheme.hover : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 100
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    id: starRowMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        if (sideBar.openPolicy)
                            sideBar.openPolicy(modelData.designId);
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 8
                    spacing: 8

                    TitleBarIcon {
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                        Layout.alignment: Qt.AlignVCenter
                        kind: "starFill"
                        iconColor: AppTheme.foreground
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: modelData.name
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        color: starRowMouse.containsMouse ? AppTheme.foreground : AppTheme.muted

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    Rectangle {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: AppTheme.border
    }
}
