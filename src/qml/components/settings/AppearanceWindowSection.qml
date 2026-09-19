import QtQuick
import QtQuick.Layouts
import Totm

// Window chrome card: native-feeling window-button visibility. Hiding
// suits tiling window managers, where the compositor owns chrome.
// Reads SettingsStore directly like the theme card (data-only).
Rectangle {
    id: windowCard

    Layout.fillWidth: true
    implicitHeight: windowBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: windowBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Window")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Window controls")
            font.pixelSize: 11
            elide: Text.ElideRight
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("Shown")
                active: SettingsStore.showWindowControls
                onClicked: SettingsStore.showWindowControls = true
            }

            SegmentedOption {
                label: qsTr("Hidden")
                active: !SettingsStore.showWindowControls
                onClicked: SettingsStore.showWindowControls = false
            }
        }
    }
}
