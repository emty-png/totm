import QtQuick
import QtQuick.Layouts
import Totm

// Floating-toolbar button: 36x32, rounded, muted icon.
// Active state is inverted (foreground fill, background icon), like web.
Rectangle {
    id: toolButton

    property string iconKind: "pen"
    property bool active: false

    signal clicked

    Layout.preferredWidth: 36
    Layout.preferredHeight: 32
    radius: 8
    border.width: 1
    border.color: toolButton.active ? AppTheme.foreground : "transparent"
    color: toolButton.active ? AppTheme.foreground : mouse.pressed ? AppTheme.pressed : mouse.containsMouse ? AppTheme.hover : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    TitleBarIcon {
        anchors.centerIn: parent
        kind: toolButton.iconKind
        scale: mouse.pressed ? 0.88 : 1
        transformOrigin: Item.Center
        iconColor: toolButton.active ? AppTheme.background : mouse.containsMouse || mouse.pressed ? AppTheme.foreground : AppTheme.muted

        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }
        Behavior on iconColor {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: toolButton.clicked()
    }
}
