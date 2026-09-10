import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Render progress modal: live bar plus frame count, Cancel kills the
// encode and deletes the partial. Stays open on failure to show the
// backend error; the button becomes Close once idle.
Popup {
    id: progressPopup

    signal cancelClicked

    anchors.centerIn: parent
    implicitWidth: 300
    padding: 12
    modal: true
    dim: true
    closePolicy: Popup.NoAutoClose

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 0.97
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: 100
            easing.type: Easing.InCubic
        }
    }

    background: Rectangle {
        radius: 10
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border
    }

    contentItem: ColumnLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: VideoExporter.rendering ? VideoExporter.qualityLabel : (VideoExporter.lastError !== "" ? qsTr("Render failed") : qsTr("Rendering"))
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: AppTheme.foreground
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: AppTheme.hover

            Rectangle {
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: parent.width * VideoExporter.progress
                radius: 3
                color: AppTheme.foreground
            }
        }

        Text {
            Layout.fillWidth: true
            visible: VideoExporter.lastError === ""
            text: qsTr("Frame %1 / %2").arg(VideoExporter.currentFrame).arg(VideoExporter.totalFrames)
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Text {
            Layout.fillWidth: true
            visible: VideoExporter.lastError !== ""
            text: VideoExporter.lastError
            font.pixelSize: 11
            color: AppTheme.foreground
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 6
            border.width: 1
            border.color: AppTheme.fieldBorder
            color: closeMouse.containsMouse || closeMouse.pressed ? AppTheme.hover : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                anchors.centerIn: parent
                text: VideoExporter.rendering ? qsTr("Cancel") : qsTr("Close")
                font.pixelSize: 12
                color: AppTheme.foreground
            }

            MouseArea {
                id: closeMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: progressPopup.cancelClicked()
            }
        }
    }
}
