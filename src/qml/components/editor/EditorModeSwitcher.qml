import QtQuick
import Totm

// Design / Animate segmented switcher at the top of the right panel
// (8px padding, 28px buttons, inverted active fill, sliding thumb).
Item {
    id: switcher

    property string mode: "design"

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
            x: switcher.mode === "design" ? 2 : track.width - width - 2
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
                    text: qsTr("Design")
                    font.pixelSize: 12
                    font.weight: switcher.mode === "design" ? Font.DemiBold : Font.Medium
                    color: switcher.mode === "design" ? AppTheme.background : designMouse.containsMouse || designMouse.pressed ? AppTheme.foreground : AppTheme.muted

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    id: designMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: switcher.mode = "design"
                }
            }

            Item {
                width: track.width / 2
                height: track.height

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Animate")
                    font.pixelSize: 12
                    font.weight: switcher.mode === "animate" ? Font.DemiBold : Font.Medium
                    color: switcher.mode === "animate" ? AppTheme.background : animateMouse.containsMouse || animateMouse.pressed ? AppTheme.foreground : AppTheme.muted

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    id: animateMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: switcher.mode = "animate"
                }
            }
        }
    }

    // Bottom divider.
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
