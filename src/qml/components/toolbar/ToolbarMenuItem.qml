import QtQuick
import QtQuick.Layouts
import Totm

// Shapes-dropdown row: 14px icon + label, inverted when active.
Rectangle {
    id: menuItem

    property string iconKind: "square"
    property string label: ""
    property bool active: false

    signal clicked

    Layout.fillWidth: true
    Layout.preferredHeight: 34
    radius: 6
    color: menuItem.active ? AppTheme.foreground : mouse.containsMouse || mouse.pressed ? AppTheme.hover : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 100
            easing.type: Easing.OutCubic
        }
    }

    RowLayout {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 10
            rightMargin: 10
        }
        spacing: 8

        AppIcon {
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
            kind: menuItem.iconKind
            iconColor: menuItem.active ? AppTheme.background : AppTheme.foreground
        }

        Text {
            Layout.fillWidth: true
            text: menuItem.label
            font.pixelSize: 12
            font.weight: menuItem.active ? Font.DemiBold : Font.Normal
            color: menuItem.active ? AppTheme.background : AppTheme.foreground
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: menuItem.clicked()
    }
}
