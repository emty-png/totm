import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Totm

// Design card context menu: Rename / Star-Unstar / Move-to / Export /
// Delete. Rows hide when their action can't apply (instead of showing
// disabled) so the popup stays compact; its height derives from the
// visible row count. Same card language as the layers context menu.
// Delete and Move cover the whole card selection when the menu opened
// inside it.
Item {
    id: menu

    property string contextId: ""
    property string contextWorkspaceId: ""
    property bool contextStarred: false
    property int contextCount: 1

    property var renamePolicy: null
    property var starPolicy: null
    property var movePolicy: null
    property var exportPolicy: null
    property var deletePolicy: null

    // Move targets: workspaces other than the card's own. The own row
    // hides instead of sitting disabled, and the whole Move section
    // hides when nothing else exists.
    function moveTargetCount() {
        var n = 0;
        try {
            var list = LibraryStore.workspaceList;
            for (var i = 0; i < list.length; i++) {
                if (list[i].workspaceId !== menu.contextWorkspaceId)
                    n++;
            }
        } catch (e) {
            n = 0;
        }
        return n;
    }

    function openFor(designId, starred, selectedCount, px, py, workspaceId) {
        menu.contextId = designId;
        menu.contextStarred = starred;
        menu.contextCount = Math.max(1, selectedCount);
        menu.contextWorkspaceId = workspaceId || "";
        // Base rows (Rename, Star, Export, Delete) plus one row per
        // move target plus the section header/separators when shown.
        // 34px per row (32px MenuItem + 2px spacing) like the layers
        // menu; +30 covers the popup padding.
        var targets = menu.moveTargetCount();
        var rows = 4 + targets + (targets > 0 ? 1 : 0);
        var w = 200, h = rows * 34 + 30;
        main.x = Math.min(Math.max(0, px), Math.max(0, menu.parent.width - w));
        main.y = Math.min(Math.max(0, py), Math.max(0, menu.parent.height - h));
        main.open();
    }

    function closeAll() {
        main.close();
    }

    component MenuBackground: Item {
        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: 10
            radius: AppTheme.radiusLarge
            color: AppTheme.surface
            border.width: 1
            border.color: AppTheme.fieldBorder
        }
        MultiEffect {
            source: card
            anchors.fill: card
            shadowEnabled: true
            shadowColor: "#4d000000"
            shadowBlur: 0.45
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 4
        }
    }

    Popup {
        id: main
        implicitWidth: 200
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        transformOrigin: Item.TopLeft

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: 120
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                property: "scale"
                from: 0.97
                to: 1
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: 100
                easing.type: Easing.InCubic
            }
        }

        background: MenuBackground {}

        contentItem: ColumnLayout {
            spacing: 2

            MenuItem {
                label: qsTr("Rename")
                onClicked: {
                    if (menu.renamePolicy)
                        menu.renamePolicy(menu.contextId);
                    menu.closeAll();
                }
            }
            MenuItem {
                label: menu.contextStarred ? qsTr("Unstar") : qsTr("Star")
                onClicked: {
                    if (menu.starPolicy)
                        menu.starPolicy(menu.contextId);
                    menu.closeAll();
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 6
                Layout.bottomMargin: 2
                visible: menu.moveTargetCount() > 0
                color: AppTheme.border
            }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                visible: menu.moveTargetCount() > 0
                text: menu.contextCount > 1 ? qsTr("Move %1 to").arg(menu.contextCount) : qsTr("Move to")
                font.pixelSize: 11
                color: AppTheme.muted
            }
            Repeater {
                model: LibraryStore.workspaceList
                MenuItem {
                    label: modelData.name
                    hint: modelData.designCount !== undefined ? String(modelData.designCount) : ""
                    visible: modelData.workspaceId !== menu.contextWorkspaceId
                    enabled: modelData.workspaceId !== menu.contextWorkspaceId
                    onClicked: {
                        if (menu.movePolicy)
                            menu.movePolicy(modelData.workspaceId);
                        menu.closeAll();
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 2
                Layout.bottomMargin: 6
                visible: menu.moveTargetCount() > 0
                color: AppTheme.border
            }
            MenuItem {
                label: qsTr("Export .totm")
                onClicked: {
                    if (menu.exportPolicy)
                        menu.exportPolicy(menu.contextId);
                    menu.closeAll();
                }
            }
            MenuItem {
                label: qsTr("Delete")
                hint: menu.contextCount > 1 ? String(menu.contextCount) : ""
                onClicked: {
                    if (menu.deletePolicy)
                        menu.deletePolicy(menu.contextId);
                    menu.closeAll();
                }
            }
        }
    }
}
