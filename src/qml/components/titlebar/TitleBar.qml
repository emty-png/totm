import QtQuick
import QtQuick.Layouts
import Totm

// Custom title bar shell: 45px total = 44px bar + 1px bottom border.
// Colors come from the AppTheme singleton. macOS shows left-aligned
// traffic lights (frameless has no native ones); other platforms keep
// the Windows-style right controls.
Item {
    id: titleBar
    height: 45
    implicitHeight: 45

    required property Window window
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
                    visible: titleBar.isMac
                    window: titleBar.window
                }

                TitleBarTabBar {
                    id: tabBar
                }

                TitleBarDragArea {
                    window: titleBar.window
                    toggleMaximize: controls.toggleMaximize
                }

                // Theme toggle: moon in dark mode, sun in light mode
                TitleBarButton {
                    iconKind: AppTheme.isDark ? "moon" : "sun"
                    onClicked: AppTheme.toggle()
                }

                TitleBarControls {
                    id: controls
                    visible: !titleBar.isMac
                    Layout.fillHeight: true
                    window: titleBar.window
                }
            }
        }

        // 1px bottom border (full width; the active-tab cover below hides
        // the segment under the active tab so it blends into the content,
        // like web `border-bottom-color: background`).
        Rectangle {
            width: parent.width
            height: 1
            color: AppTheme.border
        }
    }

    // Active-tab blend cover, painted over the border. Offset by the
    // tab bar's x so mac traffic lights don't shift it off the tab.
    Rectangle {
        x: tabBar.x + tabBar.activeX
        y: 44
        width: tabBar.activeWidth
        height: 1
        color: AppTheme.background
    }
}
