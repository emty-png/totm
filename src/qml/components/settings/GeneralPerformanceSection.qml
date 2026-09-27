import QtQuick
import QtQuick.Layouts
import Totm

// Performance card: full vs low-spec preview mode. Low-spec freezes
// preview grain shimmer, ticks playback at 30fps and runs the
// single-threaded scene-graph loop (takes effect on restart). Reads
// SettingsStore directly like the other general cards.
Rectangle {
    id: perfCard

    Layout.fillWidth: true
    implicitHeight: perfBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: perfBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Performance")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Preview quality")
            font.pixelSize: 11
            elide: Text.ElideRight
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("Full")
                active: !SettingsStore.lowSpecMode
                onClicked: SettingsStore.lowSpecMode = false
            }

            SegmentedOption {
                label: qsTr("Low-spec")
                active: SettingsStore.lowSpecMode
                onClicked: SettingsStore.lowSpecMode = true
            }
        }

        Text {
            Layout.fillWidth: true
            visible: SettingsStore.lowSpecMode
            text: qsTr("Static grain, 30fps playback. Scene-graph change applies on restart.")
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            color: AppTheme.muted
        }
    }
}
