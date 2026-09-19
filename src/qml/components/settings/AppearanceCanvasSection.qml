import QtQuick
import QtQuick.Layouts
import Totm

// Canvas chrome card: zoom pill visibility. Reads SettingsStore
// directly like the theme card (data-only, no policies).
Rectangle {
    id: canvasCard

    Layout.fillWidth: true
    implicitHeight: canvasBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: canvasBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Canvas")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Zoom pill")
            font.pixelSize: 11
            elide: Text.ElideRight
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("Shown")
                active: SettingsStore.showZoomPill
                onClicked: SettingsStore.showZoomPill = true
            }

            SegmentedOption {
                label: qsTr("Hidden")
                active: !SettingsStore.showZoomPill
                onClicked: SettingsStore.showZoomPill = false
            }
        }
    }
}
