import QtQuick
import QtQuick.Layouts
import Totm

// First tab in the tabbar: home tab. Same 46px width and hover behavior
// as the window-control buttons. Active tab blends into the content area.
Rectangle {
    id: homeTab

    property bool active: true

    signal clicked

    Layout.preferredWidth: 46
    Layout.fillHeight: true
    // No hover/pressed feedback while active (selected).
    color: homeTab.active ? AppTheme.background : mouse.pressed ? AppTheme.pressed : mouse.containsMouse ? AppTheme.hover : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    AppIcon {
        anchors.centerIn: parent
        kind: "apps"
        width: 20
        height: 20
        iconColor: homeTab.active || mouse.containsMouse || mouse.pressed ? AppTheme.foreground : AppTheme.muted

        Behavior on iconColor {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    // Right divider.
    Rectangle {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: AppTheme.border
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: homeTab.clicked()
    }
}
