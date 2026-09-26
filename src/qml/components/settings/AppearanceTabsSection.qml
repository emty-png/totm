import QtQuick
import QtQuick.Layouts
import Totm

// Tabs card: tab rail position (top / bottom / left / right) plus the
// collapsed icon mode for the vertical rails. Reads SettingsStore
// directly like the window card (data-only).
Rectangle {
    id: tabsCard

    Layout.fillWidth: true
    implicitHeight: tabsBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: tabsBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Tabs")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Tab bar position")
            font.pixelSize: 11
            elide: Text.ElideRight
            color: AppTheme.muted
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 8
            rowSpacing: 8

            SegmentedOption {
                label: qsTr("Top")
                active: SettingsStore.tabPosition === "top"
                onClicked: SettingsStore.tabPosition = "top"
            }

            SegmentedOption {
                label: qsTr("Bottom")
                active: SettingsStore.tabPosition === "bottom"
                onClicked: SettingsStore.tabPosition = "bottom"
            }

            SegmentedOption {
                label: qsTr("Left")
                active: SettingsStore.tabPosition === "left"
                onClicked: SettingsStore.tabPosition = "left"
            }

            SegmentedOption {
                label: qsTr("Right")
                active: SettingsStore.tabPosition === "right"
                onClicked: SettingsStore.tabPosition = "right"
            }
        }

        Text {
            Layout.fillWidth: true
            visible: SettingsStore.tabPosition === "left" || SettingsStore.tabPosition === "right"
            text: qsTr("Vertical width")
            font.pixelSize: 11
            elide: Text.ElideRight
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            visible: SettingsStore.tabPosition === "left" || SettingsStore.tabPosition === "right"
            spacing: 8

            SegmentedOption {
                label: qsTr("Expanded")
                active: !SettingsStore.tabRailCollapsed
                onClicked: SettingsStore.tabRailCollapsed = false
            }

            SegmentedOption {
                label: qsTr("Collapsed")
                active: SettingsStore.tabRailCollapsed
                onClicked: SettingsStore.tabRailCollapsed = true
            }
        }
    }
}
