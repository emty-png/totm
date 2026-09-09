import QtQuick
import QtQuick.Layouts
import Totm

// Small segmented option button for the clip editor: surface fill plus
// input hairline at rest, inverted foreground fill when active.
Rectangle {
    id: seg

    property string label: ""
    property bool active: false

    signal clicked

    Layout.fillWidth: true
    Layout.preferredHeight: 28
    radius: 6
    border.width: 1
    border.color: seg.active ? AppTheme.foreground : AppTheme.fieldBorder
    color: seg.active ? AppTheme.foreground : segMouse.containsMouse || segMouse.pressed ? AppTheme.hover : AppTheme.surface

    Behavior on color {
        ColorAnimation {
            duration: 100
            easing.type: Easing.OutCubic
        }
    }

    Text {
        anchors.centerIn: parent
        text: seg.label
        font.pixelSize: 12
        font.weight: seg.active ? Font.DemiBold : Font.Normal
        color: seg.active ? AppTheme.background : segMouse.containsMouse || segMouse.pressed ? AppTheme.foreground : AppTheme.muted
    }

    MouseArea {
        id: segMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: seg.clicked()
    }
}
