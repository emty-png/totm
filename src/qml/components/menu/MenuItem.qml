import QtQuick
import QtQuick.Layouts
import Totm

// One context-menu row: text label plus optional trailing hint or check
// tick. No icons otherwise; hover fill, dimmed when disabled. Disabled
// rides the standard `enabled` prop (inherited by the MouseArea);
// visuals dim manually.
Rectangle {
    id: menuItem

    property string label: ""
    property string hint: ""
    property bool checked: false

    signal clicked

    Layout.fillWidth: true
    Layout.preferredHeight: 32
    radius: AppTheme.radiusSmall
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
        visible: !menuItem.checked && menuItem.hint !== ""
        text: menuItem.hint
        font.pixelSize: 12
        color: AppTheme.muted
    }

    AppIcon {
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
            rightMargin: 10
        }
        width: 12
        height: 12
        visible: menuItem.checked
        kind: "check"
        iconColor: AppTheme.muted
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: menuItem.clicked()
    }
}
