import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Totm

// Design card context menu: Rename / Star-Unstar / Delete. Same card
// language as the layers context menu. Delete covers the whole card
// selection when the menu opened inside it.
Item {
    id: menu

    property string contextId: ""
    property bool contextStarred: false
    property int contextCount: 1

    property var renamePolicy: null
    property var starPolicy: null
    property var deletePolicy: null

    function openFor(designId, starred, selectedCount, px, py) {
        menu.contextId = designId;
        menu.contextStarred = starred;
        menu.contextCount = Math.max(1, selectedCount);
        var w = 170, h = 134;
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
            radius: 10
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
        implicitWidth: 170
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
