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

    property string pendingDeleteId: ""

    function askDelete(pluginId) {
        var info = PluginStore.plugin(pluginId);
        pluginPanel.pendingDeleteId = pluginId;
        deletePopup.ask(qsTr("Delete plugin?"), qsTr("“%1” leaves this device. Its saved settings go with it.").arg(info && info.name ? info.name : pluginId), qsTr("Delete"));
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
            iconKind: "info"
            filled: false
            strong: true
            iconSize: 16
            onClicked: PluginStore.openGuide()
        }

        PanelIconButton {
            id: importBtn

            iconKind: "plus"
            filled: false
            strong: true
            iconSize: 16
            onClicked: {
                if (importMenu.opened) {
                    importMenu.close();
                    return;
                }
                var p = importBtn.mapToItem(Overlay.overlay, 0, 0);
                importMenu.x = Math.max(8, p.x + importBtn.width - importMenu.width);
                importMenu.y = p.y + importBtn.height + 4;
                importMenu.open();
            }
        }

        PanelIconButton {
            iconKind: "refresh"
            filled: false
            strong: true
            iconSize: 16
            onClicked: {
                PluginStore.clearError();
                PluginStore.scan();
            }
        }

        Popup {
            id: importMenu

            parent: Overlay.overlay
            implicitWidth: 180
            padding: 6
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

            background: Rectangle {
                radius: AppTheme.radiusLarge
                color: AppTheme.surface
                border.width: 1
                border.color: AppTheme.border
            }

            contentItem: ColumnLayout {
                spacing: 2

                MenuItem {
                    label: qsTr("Import folder…")
                    onClicked: {
                        importMenu.close();
                        PluginStore.clearError();
                        folderPicker.open();
                    }
                }
                MenuItem {
                    label: qsTr("Import .zip…")
                    onClicked: {
                        importMenu.close();
                        PluginStore.clearError();
                        zipPicker.open();
                    }
                }
            }
        }
    }

    Text {
        visible: PluginStore.lastError !== ""
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        text: PluginStore.lastError
        font.pixelSize: 11
        color: "#e81123"
        wrapMode: Text.WordWrap
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
                    item.deletePolicy = pluginId => pluginPanel.askDelete(pluginId);
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
        text: qsTr("Import a folder or .zip with +, or copy a folder into %1, then press Rescan.").arg(PluginStore.pluginsDir())
        font.pixelSize: 11
        color: AppTheme.muted
    }

    FilePicker {
        id: folderPicker

        folderMode: true
        suffixes: []
        onAccepted: PluginStore.importFolder(folderPicker.selectedFile)
    }

    FilePicker {
        id: zipPicker

        suffixes: ["zip"]
        onAccepted: PluginStore.importZip(zipPicker.selectedFile)
    }

    ConfirmPopup {
        id: deletePopup

        onConfirmed: {
            if (pluginPanel.pendingDeleteId !== "")
                PluginStore.removePlugin(pluginPanel.pendingDeleteId);
            pluginPanel.pendingDeleteId = "";
        }
    }
}
