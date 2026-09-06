import QtQuick
import QtQuick.Layouts
import Totm

// One context-menu row: text label, optional trailing hint (used for the
// submenu parent). Figma-style: no icons, hover fill, dimmed when off.
// Disabled state rides the standard `enabled` prop (inherited by the
// MouseArea), visuals dim manually to match the theme.
Rectangle {
    id: menuItem

    property string label: ""
    property string hint: ""

    signal clicked

    Layout.fillWidth: true
    Layout.preferredHeight: 32
    radius: 6
    opacity: menuItem.enabled ? 1 : 0.4
    color: !menuItem.enabled ? "transparent" : mouse.containsMouse || mouse.pressed ? AppTheme.hover : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 100
            easing.type: Easing.OutCubic
        }
    }

    Text {
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: 10
        }
        text: menuItem.label
        font.pixelSize: 12
        color: AppTheme.foreground
    }

    Text {
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
            rightMargin: 10
        }
        visible: menuItem.hint !== ""
        text: menuItem.hint
        font.pixelSize: 12
        color: AppTheme.muted
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: menuItem.clicked()
    }
}
