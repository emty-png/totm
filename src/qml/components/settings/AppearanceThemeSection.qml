import QtQuick
import QtQuick.Layouts
import Totm

// Theme mode card: System follows the OS, Light/Dark pin an override.
// Reads SettingsStore directly like ShortcutRow (data-only, no policies).
Rectangle {
    id: themeCard

    Layout.fillWidth: true
    implicitHeight: themeBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    ColumnLayout {
        id: themeBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Theme")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("System")
                active: SettingsStore.followSystem
                onClicked: SettingsStore.useSystemTheme()
            }

            SegmentedOption {
                label: qsTr("Light")
                active: !SettingsStore.followSystem && !SettingsStore.isDark
                onClicked: SettingsStore.isDark = false
            }

            SegmentedOption {
                label: qsTr("Dark")
                active: !SettingsStore.followSystem && SettingsStore.isDark
                onClicked: SettingsStore.isDark = true
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: qsTr("Cursor size")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("Small")
                active: SettingsStore.cursorSize === 16
                onClicked: SettingsStore.cursorSize = 16
            }

            SegmentedOption {
                label: qsTr("Medium")
                active: SettingsStore.cursorSize === 20
                onClicked: SettingsStore.cursorSize = 20
            }

            SegmentedOption {
                label: qsTr("Large")
                active: SettingsStore.cursorSize === 24
                onClicked: SettingsStore.cursorSize = 24
            }

            // Free size (12..32px): doubles as the Custom option — typing
            // a non-preset value simply leaves all presets inactive.
            NumberField {
                Layout.preferredWidth: 64
                value: SettingsStore.cursorSize
                minimum: 12
                maximum: 32
                suffix: qsTr("px")
                onCommitted: v => SettingsStore.cursorSize = Math.round(v)
            }
        }
    }
}
