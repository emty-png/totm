import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Panel dropdown: field-styled button plus popup menu in graph-editor
// menu styling. Options are [{id, name}]; picked(id) fires on choice.
// Sizing mirrors SegmentedOption so the two mix in rows. With
// searchable, the popup gains a filter field and a capped scrollable
// list (for long menus like font families); rows preview in their own
// family face in that mode.
Rectangle {
    id: drop

    property var options: []
    property string currentId: ""
    property bool searchable: false

    signal picked(string id)

    // Live filter over options; the current pick always stays visible.
    readonly property var filteredOptions: {
        if (!drop.searchable)
            return drop.options;
        var q = searchField.text.trim().toLowerCase();
        var out = [];
        var list = drop.options || [];
        for (var i = 0; i < list.length; i++) {
            var name = String(list[i].name || "");
            if (q !== "" && String(list[i].id) !== drop.currentId && name.toLowerCase().indexOf(q) < 0)
                continue;
            out.push(list[i]);
        }
        return out;
    }

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.preferredHeight: 28
    radius: AppTheme.radiusSmall
    color: menu.opened || dropMouse.containsMouse || dropMouse.pressed ? AppTheme.hover : AppTheme.surface
    border.width: 1
    border.color: AppTheme.fieldBorder

    Text {
        anchors {
            left: parent.left
            right: caretIcon.left
            verticalCenter: parent.verticalCenter
            leftMargin: 10
            rightMargin: 6
        }
        text: drop.currentName()
        font.pixelSize: 12
        elide: Text.ElideRight
        color: AppTheme.foreground
    }

    AppIcon {
        id: caretIcon

        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
            rightMargin: 8
        }
        kind: "caret"
        rotation: menu.opened ? 180 : 0
        width: 12
        height: 12
        iconColor: AppTheme.muted

        Behavior on rotation {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: dropMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (menu.opened)
                menu.close();
            else
                menu.open();
        }
    }

    Popup {
        id: menu

        x: 0
        y: drop.height + 4
        width: drop.width
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        transformOrigin: Item.Top

        onOpened: {
            searchField.text = "";
            if (drop.searchable)
                searchField.forceActiveFocus();
        }

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
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

        background: Rectangle {
            radius: AppTheme.radiusLarge
            color: AppTheme.surface
            border.width: 1
            border.color: AppTheme.border
        }

        contentItem: Column {
            spacing: 2

            TextField {
                id: searchField

                visible: drop.searchable
                width: menu.availableWidth
                implicitHeight: 28
                placeholderText: qsTr("Search...")
                placeholderTextColor: AppTheme.muted
                leftPadding: 10
                font.pixelSize: 12
                color: AppTheme.foreground
                selectByMouse: true

                background: Rectangle {
                    radius: AppTheme.radiusSmall
                    color: AppTheme.background
                    border.width: 1
                    border.color: searchField.activeFocus ? AppTheme.selection : AppTheme.fieldBorder
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        menu.close();
                        event.accepted = true;
                    }
                }
            }

            ListView {
                id: optionList

                visible: drop.searchable
                width: menu.availableWidth
                height: Math.min(320, Math.max(64, drop.filteredOptions.length * 32))
                clip: true
                spacing: 2
                model: drop.filteredOptions

                ScrollBar.vertical: ScrollBar {
                    policy: optionList.contentHeight > optionList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: AppTheme.border
                    }
                    background: Item {
                        implicitWidth: 6
                    }
                }

                delegate: Rectangle {
                    required property var modelData

                    width: optionList.width
                    height: 30
                    radius: AppTheme.radiusSmall
                    color: modelData.id === drop.currentId ? AppTheme.hover : optMouse.containsMouse || optMouse.pressed ? AppTheme.hover : "transparent"

                    Text {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 10
                            rightMargin: 10
                        }
                        text: modelData.name
                        font.pixelSize: 12
                        font.family: String(modelData.id)
                        font.weight: modelData.id === drop.currentId ? Font.DemiBold : Font.Normal
                        color: modelData.id === drop.currentId ? AppTheme.foreground : AppTheme.muted
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: optMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            menu.close();
                            drop.picked(String(modelData.id));
                        }
                    }
                }
            }

            Repeater {
                model: drop.searchable ? [] : drop.options

                Rectangle {
                    // Explicit popup width minus padding (binding
                    // contentWidth here would loop, like the graph menu).
                    width: menu.availableWidth
                    height: 30
                    radius: AppTheme.radiusSmall
                    color: modelData.id === drop.currentId ? AppTheme.hover : optMouse.containsMouse || optMouse.pressed ? AppTheme.hover : "transparent"

                    Text {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 10
                        }
                        text: modelData.name
                        font.pixelSize: 12
                        font.weight: modelData.id === drop.currentId ? Font.DemiBold : Font.Normal
                        color: modelData.id === drop.currentId ? AppTheme.foreground : AppTheme.muted
                    }

                    MouseArea {
                        id: optMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            menu.close();
                            drop.picked(String(modelData.id));
                        }
                    }
                }
            }
        }
    }

    function currentName() {
        for (var i = 0; i < drop.options.length; i++) {
            if (String(drop.options[i].id) === drop.currentId)
                return drop.options[i].name;
        }
        return drop.options.length > 0 ? drop.options[0].name : "";
    }
}
