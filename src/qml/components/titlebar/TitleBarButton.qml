import QtQuick
import QtQuick.Layouts
import Totm

// Single 46px window-control button with hover + pressed feedback.
// Matches web CSS: 120ms bg/color transition, close hover #e81123.
Rectangle {
    id: button

    property string iconKind: "close"
    property color textColor: AppTheme.muted
    property color hoverColor: AppTheme.hover
    property color pressedColor: AppTheme.pressed
    property color hoverTextColor: AppTheme.foreground

    signal clicked

    // Exposed for containers that gate on button hover (e.g. tab close).
    readonly property alias hovered: mouse.containsMouse
    readonly property alias pressed: mouse.pressed

    Layout.preferredWidth: 46
    Layout.fillHeight: true
    color: mouse.pressed ? button.pressedColor : mouse.containsMouse ? button.hoverColor : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    TitleBarIcon {
        anchors.centerIn: parent
        kind: button.iconKind
        iconColor: mouse.containsMouse || mouse.pressed ? button.hoverTextColor : button.textColor

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
        onClicked: button.clicked()
    }
}
