import QtQuick
import Totm

// Cute measurement pill: themed surface fill, pop-in/out on show.
Item {
    id: pill

    property string label: ""
    property bool shown: false

    implicitWidth: textItem.implicitWidth + 12
    implicitHeight: 22
    width: implicitWidth
    height: implicitHeight

    visible: pill.fade > 0.02
    opacity: pill.fade
    scale: 0.7 + 0.3 * pill.pop
    transformOrigin: Item.Center

    property real fade: pill.shown ? 1 : 0
    property real pop: pill.shown ? 1 : 0

    Behavior on fade {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
    Behavior on pop {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border
    }

    Text {
        id: textItem

        anchors.centerIn: parent
        text: pill.label
        font.pixelSize: 11
        color: AppTheme.foreground
    }
}
