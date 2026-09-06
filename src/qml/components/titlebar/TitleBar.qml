import QtQuick
import QtQuick.Layouts
import Totm

// Custom title bar shell: 45px total = 44px bar + 1px bottom border.
// Colors come from the AppTheme singleton.
Item {
    id: titleBar
    height: 45
    implicitHeight: 45

    required property Window window

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

    // Active-tab blend cover, painted over the border.
    Rectangle {
        x: tabBar.activeX
        y: 44
        width: tabBar.activeWidth
        height: 1
        color: AppTheme.background
    }
}
