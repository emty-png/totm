import QtQuick
import QtQuick.Layouts
import Totm

// Export defaults card: starting quality, frame rate, encode effort and
// container for the video picker. Render saves the used choice back here,
// so the next export opens where the last one left off.
Rectangle {
    id: exportCard

    Layout.fillWidth: true
    implicitHeight: exportBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: exportBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Video export")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

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
                active: SettingsStore.defaultQuality === "sd"
                onClicked: SettingsStore.defaultQuality = "sd"
            }

            SegmentedOption {
                label: qsTr("HD")
                active: SettingsStore.defaultQuality === "hd"
                onClicked: SettingsStore.defaultQuality = "hd"
            }

            SegmentedOption {
                label: qsTr("4K")
                active: SettingsStore.defaultQuality === "4k"
                onClicked: SettingsStore.defaultQuality = "4k"
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
                active: SettingsStore.defaultFps === 30
                onClicked: SettingsStore.defaultFps = 30
            }

            SegmentedOption {
                label: qsTr("60 fps")
                active: SettingsStore.defaultFps === 60
                onClicked: SettingsStore.defaultFps = 60
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
                active: SettingsStore.defaultPerformance === "slow"
                onClicked: SettingsStore.defaultPerformance = "slow"
            }

            SegmentedOption {
                label: qsTr("Normal")
                active: SettingsStore.defaultPerformance === "normal"
                onClicked: SettingsStore.defaultPerformance = "normal"
            }

            SegmentedOption {
                label: qsTr("Fast")
                active: SettingsStore.defaultPerformance === "fast"
                onClicked: SettingsStore.defaultPerformance = "fast"
            }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Format")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("MP4")
                active: SettingsStore.defaultFormat === "mp4"
                onClicked: SettingsStore.defaultFormat = "mp4"
            }

            SegmentedOption {
                label: qsTr("WebM")
                active: SettingsStore.defaultFormat === "webm"
                onClicked: SettingsStore.defaultFormat = "webm"
            }

            SegmentedOption {
                label: qsTr("GIF")
                active: SettingsStore.defaultFormat === "gif"
                onClicked: SettingsStore.defaultFormat = "gif"
            }
        }
    }
}
