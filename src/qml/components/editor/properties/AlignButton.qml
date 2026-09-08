import QtQuick
import QtQuick.Layouts
import Totm

// Line-drawn alignment button (no icon font needed): three bars
// arranged per mode. Styled like SegOption (inverted when active).
// Modes: hLeft | hCenter | hRight | justify | vTop | vMiddle | vBottom.
Rectangle {
    id: btn

    property string mode: "hLeft"
    property bool active: false

    signal clicked

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.preferredHeight: 28
    radius: 6
    border.width: 1
    border.color: btn.active ? AppTheme.foreground : AppTheme.fieldBorder
    color: btn.active ? AppTheme.foreground : btnMouse.containsMouse || btnMouse.pressed ? AppTheme.hover : AppTheme.surface

    Behavior on color {
        ColorAnimation {
            duration: 100
            easing.type: Easing.OutCubic
        }
    }

    Item {
        anchors.centerIn: parent
        width: 16
        height: 16

        Repeater {
            model: 3

            Rectangle {
                property var geom: btn.barGeom(index)

                x: geom[0]
                y: geom[1]
                width: geom[2]
                height: 2
                radius: 1
                color: btn.active ? AppTheme.background : btnMouse.containsMouse || btnMouse.pressed ? AppTheme.foreground : AppTheme.muted
            }
        }
    }

    MouseArea {
        id: btnMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }

    // [x, y, width] per bar. Horizontal modes vary x/width across rows
    // [12, 8, 12]; vertical modes stack full-width bars top/mid/bottom.
    function barGeom(i) {
        var rows = [1, 7, 13];
        switch (btn.mode) {
        case "hLeft":
            return [0, rows[i], [12, 8, 12][i]];
        case "hCenter":
            return [(16 - [12, 8, 12][i]) / 2, rows[i], [12, 8, 12][i]];
        case "hRight":
            return [16 - [12, 8, 12][i], rows[i], [12, 8, 12][i]];
        case "justify":
            return [0, rows[i], 16];
        case "vTop":
            return [0, [0, 5, 10][i], 16];
        case "vMiddle":
            return [0, [2, 7, 12][i], 16];
        case "vBottom":
            return [0, [4, 9, 14][i], 16];
        default:
            return [0, rows[i], 12];
        }
    }
}
