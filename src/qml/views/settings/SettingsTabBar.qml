import QtQuick
import QtQuick.Layouts
import Totm

// Settings tab strip: titlebar tab language (surface bar, background
// active fill, bottom hairline). Click policies are wired in onItemAdded
// so delegates never reach for outer ids (same rule as
// LayersView/TimelineView/TitleBarTabBar).
Item {
    id: tabBar

    property var tabs: [
        {
            id: "plugin",
            title: qsTr("Plugin")
        },
        {
            id: "shortcut",
            title: qsTr("Shortcut")
        },
        {
            id: "appearance",
            title: qsTr("Appearance")
        }
    ]
    property string activeTab: "plugin"

    signal tabClicked(string id)

    implicitHeight: 44

    // Bar background.
    Rectangle {
        anchors.fill: parent
        color: AppTheme.surface
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: tabBar.tabs

            onItemAdded: (index, item) => {
                item.clickPolicy = id => tabBar.tabClicked(id);
            }

            delegate: SettingsTab {
                tabId: modelData.id
                title: modelData.title
                active: modelData.id === tabBar.activeTab
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    // Bottom hairline.
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: AppTheme.border
    }
}
