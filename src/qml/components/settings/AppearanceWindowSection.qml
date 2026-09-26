import QtQuick
import QtQuick.Layouts
import Totm

// Window chrome card: top-bar, window-button, theme-toggle visibility
// plus top-bar window dragging. Hiding suits tiling window managers,
// where the compositor owns chrome. Reads SettingsStore directly like
// the theme card (data-only).
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
            text: qsTr("Top bar")
            font.pixelSize: 11
            elide: Text.ElideRight
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("Shown")
                active: SettingsStore.showTopBar
                onClicked: SettingsStore.showTopBar = true
            }

            SegmentedOption {
                label: qsTr("Hidden")
                active: !SettingsStore.showTopBar
                onClicked: SettingsStore.showTopBar = false
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !SettingsStore.showTopBar
            text: qsTr("With the top bar hidden, Top tabs fall back to the bottom rail.")
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            color: AppTheme.muted
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

        Text {
            Layout.fillWidth: true
            text: qsTr("Theme button")
            font.pixelSize: 11
            elide: Text.ElideRight
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("Shown")
                active: SettingsStore.showThemeToggle
                onClicked: SettingsStore.showThemeToggle = true
            }

            SegmentedOption {
                label: qsTr("Hidden")
                active: !SettingsStore.showThemeToggle
                onClicked: SettingsStore.showThemeToggle = false
            }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Window dragging from the top bar")
            font.pixelSize: 11
            elide: Text.ElideRight
            color: AppTheme.muted
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("Enabled")
                active: SettingsStore.windowDragEnabled
                onClicked: SettingsStore.windowDragEnabled = true
            }

            SegmentedOption {
                label: qsTr("Disabled")
                active: !SettingsStore.windowDragEnabled
                onClicked: SettingsStore.windowDragEnabled = false
            }
        }
    }
}
