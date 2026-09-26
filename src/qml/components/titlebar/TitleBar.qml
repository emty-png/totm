import QtQuick
import QtQuick.Layouts
import Totm

// Custom title bar shell: 45px total = 44px bar + 1px bottom border.
// Colors come from the AppTheme singleton. macOS shows left-aligned
// traffic lights (frameless has no native ones); other platforms keep
// the Windows-style right controls. When showTabs is false the bar
// renders chrome-only (drag area + theme + window controls) and the
// tab cluster lives in a side/bottom rail instead.
Item {
    id: titleBar
    height: 45
    implicitHeight: 45

    required property Window window
    property bool showTabs: true
    // Qt6 reports "macos" ("osx" on older builds); both mean mac.
    readonly property bool isMac: Qt.platform.os === "macos" || Qt.platform.os === "osx"

    Column {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            width: parent.width
            height: 44
            color: AppTheme.surface

            RowLayout {
                anchors.fill: parent
                spacing: 0

                MacTrafficLights {
                    id: macLights
                    visible: titleBar.isMac && SettingsStore.showWindowControls
                    window: titleBar.window
                }

                TitleBarTabBar {
                    id: tabBar
                    visible: titleBar.showTabs
                }

                TitleBarDragArea {
                    window: titleBar.window
                    toggleMaximize: controls.toggleMaximize
                    dragEnabled: SettingsStore.windowDragEnabled
                }

                // Theme toggle: moon in dark mode, sun in light mode
                TitleBarButton {
                    visible: SettingsStore.showThemeToggle
                    iconKind: AppTheme.isDark ? "moon" : "sun"
                    onClicked: AppTheme.toggle()
                }

                TitleBarControls {
                    id: controls
                    visible: !titleBar.isMac && SettingsStore.showWindowControls
                    Layout.fillHeight: true
                    window: titleBar.window
                }
            }
        }

        // 1px bottom border. The active-tab cover below hides the segment
        // under the active tab so it blends into the content.
        Rectangle {
            width: parent.width
            height: 1
            color: AppTheme.border
        }
    }

    // Active-tab blend cover, painted over the border. Offset by the
    // tab bar's x so mac traffic lights don't shift it off the tab.
    // Only for the top-tabs mode; side/bottom rails paint their own.
    Rectangle {
        visible: titleBar.showTabs
        x: tabBar.x + tabBar.activeX
        y: 44
        width: tabBar.activeWidth
        height: 1
        color: AppTheme.background
    }
}
