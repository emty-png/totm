import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Export quality picker: SD/HD/4K plus 30/60fps plus Slow/Normal/Fast
// encode effort, then Render. Centered modal; Render snapshots the scene
// fresh so later edits only affect the next export. Styling mirrors the
// panel popups (r10 surface, 1px hairline, 120ms transitions).
Popup {
    id: qualityPopup

    property string quality: "hd"
    property int fps: 30
    property string performance: "normal"

    signal renderClicked(string quality, int fps, string performance)

    anchors.centerIn: parent
    implicitWidth: 300
    padding: 12
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape

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
            text: qsTr("Quality")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("SD")
                active: qualityPopup.quality === "sd"
                onClicked: qualityPopup.quality = "sd"
            }

            SegmentedOption {
                label: qsTr("HD")
                active: qualityPopup.quality === "hd"
                onClicked: qualityPopup.quality = "hd"
            }

            SegmentedOption {
                label: qsTr("4K")
                active: qualityPopup.quality === "4k"
                onClicked: qualityPopup.quality = "4k"
            }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Frame rate")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("30 fps")
                active: qualityPopup.fps === 30
                onClicked: qualityPopup.fps = 30
            }

            SegmentedOption {
                label: qsTr("60 fps")
                active: qualityPopup.fps === 60
                onClicked: qualityPopup.fps = 60
            }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Performance")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("Slow")
                active: qualityPopup.performance === "slow"
                onClicked: qualityPopup.performance = "slow"
            }

            SegmentedOption {
                label: qsTr("Normal")
                active: qualityPopup.performance === "normal"
                onClicked: qualityPopup.performance = "normal"
            }

            SegmentedOption {
                label: qsTr("Fast")
                active: qualityPopup.performance === "fast"
                onClicked: qualityPopup.performance = "fast"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Secondary action, styled like an inactive SegmentedOption
            // (surface rest, hover fill, muted-to-foreground label).
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 6
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: cancelMouse.containsMouse || cancelMouse.pressed ? AppTheme.hover : AppTheme.surface

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Cancel")
                    font.pixelSize: 12
                    color: cancelMouse.containsMouse || cancelMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: cancelMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: qualityPopup.close()
                }
            }

            // Primary render action, styled like an active SegmentedOption:
            // inverted fill wins over hover/pressed, so the label never
            // flips to an unreadable pairing mid-hover.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 6
                border.width: 1
                border.color: AppTheme.foreground
                color: AppTheme.foreground

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Render")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: AppTheme.background
                }

                MouseArea {
                    id: renderMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: qualityPopup.renderClicked(qualityPopup.quality, qualityPopup.fps, qualityPopup.performance)
                }
            }
        }
    }
}
