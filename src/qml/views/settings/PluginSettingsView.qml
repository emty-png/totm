import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Plugin settings panel: installed plugins with enable toggles, errors,
// and per-plugin permission review. Empty library shows the placeholder.
ColumnLayout {
    id: pluginPanel

    spacing: 0

    function togglePlugin(pluginId) {
        var info = PluginStore.plugin(pluginId);
        PluginStore.setEnabled(pluginId, !(info && info.enabled));
    }

    function reviewPlugin(pluginId) {
        PluginStore.requestPermissions(pluginId);
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        Layout.topMargin: 12
        Layout.bottomMargin: 8
        spacing: 8

        Text {
            Layout.fillWidth: true
            visible: PluginStore.pluginList.length > 0
            text: qsTr("Plugins")
            font.pixelSize: 16
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        // Keeps the buttons right-aligned while the title is hidden.
        Item {
            Layout.fillWidth: true
            visible: PluginStore.pluginList.length === 0
        }

        PanelIconButton {
            iconKind: "book"
            filled: false
            strong: true
            iconSize: 16
            onClicked: PluginStore.openGuide()
        }

        PanelIconButton {
            iconKind: "sparkle"
            filled: false
            strong: true
            iconSize: 16
            onClicked: PluginStore.scan()
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        visible: PluginStore.pluginList.length === 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        text: qsTr("Nothing to see here...")
        font.pixelSize: 13
        color: AppTheme.muted
    }

    ScrollView {
        id: pluginListScroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        visible: PluginStore.pluginList.length > 0
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: pluginListScroll.availableWidth
            spacing: 2

            Repeater {
                model: PluginStore.pluginList

                onItemAdded: (index, item) => {
                    item.togglePolicy = pluginId => pluginPanel.togglePlugin(pluginId);
                    item.reviewPolicy = pluginId => pluginPanel.reviewPlugin(pluginId);
                }

                delegate: PluginManagerRow {
                    Layout.fillWidth: true
                    entry: modelData
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        Layout.topMargin: 8
        Layout.bottomMargin: 12
        visible: PluginStore.pluginList.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: qsTr("Copy a plugin folder into %1, then press Rescan.").arg(PluginStore.pluginsDir())
        font.pixelSize: 11
        color: AppTheme.muted
    }
}
