import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Appearance settings panel: theme mode, canvas chrome, per-theme
// colors, corner presets + custom radii, UI font with custom file
// imports. Same centered 640px card rhythm as the Shortcut tab.
// Official/bundled theme packs render their gallery right after the
// Theme card via the appearanceSections slot.
ColumnLayout {
    id: appearancePanel

    spacing: 0

    property real centerMargin: Math.max(16, (appearancePanel.width - 640) / 2)
    property var pluginSections: []

    function refreshPlugins() {
        appearancePanel.pluginSections = PluginStore.appearanceSections();
    }

    Component.onCompleted: appearancePanel.refreshPlugins()

    Connections {
        target: PluginStore
        function onPluginsChanged() {
            appearancePanel.refreshPlugins();
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: appearancePanel.centerMargin
        Layout.rightMargin: appearancePanel.centerMargin
        Layout.topMargin: 12
        Layout.bottomMargin: 8
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Appearance")
            font.pixelSize: 16
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: resetText.implicitWidth + 20
            implicitHeight: 28
            radius: AppTheme.radiusSmall
            border.width: 1
            border.color: resetMouse.containsMouse ? AppTheme.foreground : AppTheme.fieldBorder
            color: resetMouse.pressed ? AppTheme.pressed : resetMouse.containsMouse ? AppTheme.hover : AppTheme.surface

            Behavior on color {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                id: resetText

                anchors.centerIn: parent
                text: qsTr("Reset all")
                font.pixelSize: 12
                color: AppTheme.foreground
            }

            MouseArea {
                id: resetMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: SettingsStore.resetAppearance()
            }
        }
    }

    ScrollView {
        id: appearanceScroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: Math.min(640, appearanceScroll.availableWidth - 32)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            AppearanceThemeSection {}

            // Plugin theme galleries (ui.slots). Each entry gets pluginId
            // when it declares it; failures show a muted row.
            Repeater {
                model: appearancePanel.pluginSections

                delegate: PluginSlot {
                    Layout.fillWidth: true
                    entry: modelData
                }
            }

            AppearanceCanvasSection {}

            AppearanceWindowSection {}

            AppearanceTabsSection {}

            AppearanceColorsSection {}

            AppearanceRadiusSection {}

            AppearanceFontSection {}

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 16
            }
        }
    }
}
