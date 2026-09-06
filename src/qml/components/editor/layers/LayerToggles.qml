import QtQuick
import QtQuick.Layouts
import Totm

// Eye + lock toggles for a layers row. Hidden until hover except for
// active states; hidden rows dim.
RowLayout {
    id: toggles

    required property bool rowVisible
    required property bool rowLocked
    required property bool editing
    required property bool rowHovered
    property var eyePolicy: null
    property var lockPolicy: null

    readonly property bool hovered: eyeMouse.containsMouse || lockMouse.containsMouse

    spacing: 4

    Item {
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        Layout.alignment: Qt.AlignVCenter
        visible: (!toggles.rowVisible || toggles.rowHovered || toggles.hovered) && !toggles.editing

        TitleBarIcon {
            anchors.centerIn: parent
            width: 14
            height: 14
            kind: toggles.rowVisible ? "eye" : "eyeOff"
            iconColor: eyeMouse.containsMouse || !toggles.rowVisible ? AppTheme.foreground : AppTheme.muted

            Behavior on iconColor {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: eyeMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (toggles.eyePolicy)
                    toggles.eyePolicy();
            }
        }
    }

    Item {
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        Layout.alignment: Qt.AlignVCenter
        visible: (toggles.rowLocked || toggles.rowHovered || toggles.hovered) && !toggles.editing

        TitleBarIcon {
            anchors.centerIn: parent
            width: 14
            height: 14
            kind: toggles.rowLocked ? "lock" : "unlock"
            iconColor: lockMouse.containsMouse || toggles.rowLocked ? AppTheme.foreground : AppTheme.muted

            Behavior on iconColor {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: lockMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (toggles.lockPolicy)
                    toggles.lockPolicy();
            }
        }
    }
}
