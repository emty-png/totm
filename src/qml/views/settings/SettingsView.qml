import QtQuick
import QtQuick.Layouts
import Totm

// Settings content: tab strip plus one panel per tab. Panels swap on
// the active id; tabs never close.
ColumnLayout {
    id: settingsView

    property string activeTab: "plugin"

    spacing: 0

    SettingsTabBar {
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        activeTab: settingsView.activeTab
        onTabClicked: id => {
            settingsView.activeTab = id;
        }
    }

    PluginSettingsView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: settingsView.activeTab === "plugin"
    }

    ShortcutSettingsView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: settingsView.activeTab === "shortcut"
    }

    AppearanceSettingsView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: settingsView.activeTab === "appearance"
    }
}
