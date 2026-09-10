import QtQuick
import Totm

// Canvas export button, top-right: one self-contained pill action in the
// floating-toolbar language (surface pill, hairline, 44px tall). Single
// frame on purpose: the icon lives directly in the pill, never nested.
Rectangle {
    id: exportButton

    property var doc: null
    // Sticky pressed look while the quality popup it opened is up.
    property bool active: false
    readonly property bool ready: !!exportButton.doc && !VideoExporter.rendering

    signal clicked

    implicitWidth: 36
    implicitHeight: 36
    radius: 10
    opacity: exportButton.ready ? 1 : 0.4
    border.width: 1
    border.color: exportButton.active ? AppTheme.foreground : AppTheme.border
    color: !exportButton.ready ? AppTheme.surface : exportButton.active ? AppTheme.foreground : mouse.pressed ? AppTheme.pressed : mouse.containsMouse ? AppTheme.hover : AppTheme.surface

    Behavior on color {
        ColorAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    AppIcon {
        anchors.centerIn: parent
        kind: "export"
        width: 16
        height: 16
        scale: mouse.pressed ? 0.88 : 1
        transformOrigin: Item.Center
        iconColor: exportButton.active ? AppTheme.background : exportButton.ready && (mouse.containsMouse || mouse.pressed) ? AppTheme.foreground : AppTheme.muted

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
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: exportButton.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (exportButton.ready)
                exportButton.clicked();
        }
    }
}
