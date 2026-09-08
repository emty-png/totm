import QtQuick
import Totm

// Small panel button: 28x28, radius 6. Filled variant matches inputs
// (surface fill plus hairline, e.g. rotate/flip trio, aspect lock);
// plain variant is icon-only for header + / row -.
// Thin glyphs (plus/minus) need strong+16 to stay visible: at 14px muted
// the bars are sub-pixel hairlines on dark.
Rectangle {
    id: button

    property string iconKind: "plus"
    property bool filled: true
    property bool active: false
    property bool strong: false
    property int iconSize: 14

    signal clicked

    width: 28
    height: 28
    radius: 6
    border.width: 1
    border.color: button.active ? AppTheme.foreground : button.filled ? AppTheme.fieldBorder : "transparent"
    color: !button.enabled ? "transparent" : button.active ? AppTheme.foreground : mouse.pressed ? AppTheme.pressed : mouse.containsMouse ? AppTheme.hover : button.filled ? AppTheme.surface : "transparent"
    opacity: button.enabled ? 1 : 0.35

    Behavior on color {
        ColorAnimation {
            duration: 100
            easing.type: Easing.OutCubic
        }
    }

    AppIcon {
        anchors.centerIn: parent
        kind: button.iconKind
        width: button.iconSize
        height: button.iconSize
        scale: mouse.pressed ? 0.88 : 1
        iconColor: button.active ? AppTheme.background : mouse.containsMouse || mouse.pressed || button.strong ? AppTheme.foreground : AppTheme.muted

        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (button.enabled)
                button.clicked();
        }
    }
}
