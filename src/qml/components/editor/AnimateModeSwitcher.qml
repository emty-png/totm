import QtQuick
import Totm

// Preset / Custom segmented switcher at the top of the animate panel.
// Same metrics and motion as EditorModeSwitcher (8px padding, 28px
// buttons, inverted active fill, springy sliding thumb).
// Does nothing yet besides holding the selection.
Item {
    id: switcher

    property string mode: "preset"

    implicitHeight: 48

    // Track.
    Rectangle {
        id: track
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 8
            rightMargin: 8
        }
        height: 32
        radius: 8
        color: AppTheme.hover

        // Sliding thumb (half the track minus gaps).
        Rectangle {
            id: thumb
            x: switcher.mode === "preset" ? 2 : track.width - width - 2
            y: 2
            width: (track.width - 6) / 2
            height: 28
            radius: 6
            color: AppTheme.foreground

            Behavior on x {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.85
                }
            }
        }

        Row {
            anchors.fill: parent
            spacing: 0

            // Two static segments (a Repeater would hide outer scope
            // from qmllint inside its delegate).
            Item {
                width: track.width / 2
                height: track.height

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Preset")
                    font.pixelSize: 12
                    font.weight: switcher.mode === "preset" ? Font.DemiBold : Font.Medium
                    color: switcher.mode === "preset" ? AppTheme.background : presetMouse.containsMouse || presetMouse.pressed ? AppTheme.foreground : AppTheme.muted

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    id: presetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: switcher.mode = "preset"
                }
            }

            Item {
                width: track.width / 2
                height: track.height

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Custom")
                    font.pixelSize: 12
                    font.weight: switcher.mode === "custom" ? Font.DemiBold : Font.Medium
                    color: switcher.mode === "custom" ? AppTheme.background : customMouse.containsMouse || customMouse.pressed ? AppTheme.foreground : AppTheme.muted

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    id: customMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: switcher.mode = "custom"
                }
            }
        }
    }

    // Bottom divider, like web `.editor-mode-toggle { border-bottom }`.
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: AppTheme.border
    }
}
