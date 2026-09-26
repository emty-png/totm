import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Vertical tab cluster: pinned home button, scrollable document rows,
// new-tab (+) button and collapse toggle. Row height is a uniform 40px
// so the active geometry and drag slots stay arithmetic (mirrors the
// 184px horizontal math in TitleBarTabBar). Doc tabs drag to reorder
// on Y: the dragged tab follows the cursor while siblings slide open
// a gap; release commits through TabState.moveTab.
ColumnLayout {
    id: tabBar

    property bool collapsed: false
    readonly property int rowHeight: 40
    readonly property int railWidth: tabBar.collapsed ? 52 : 192

    // Drag state: source model index, press y in column coords, last
    // cursor y for the drop glide, live target slot.
    property int dragFrom: -1
    property real pressBarY: 0
    property real lastBarY: 0
    property bool tabDragging: false
    property int dropTarget: -1

    spacing: 0

    // Pinned home row. Same hover language as the horizontal home tab;
    // bottom divider matches the doc rows.
    Rectangle {
        id: homeRow

        property bool active: TabState.currentIndex === 0

        Layout.fillWidth: true
        Layout.preferredHeight: tabBar.rowHeight
        color: homeRow.active ? AppTheme.background : homeMouse.pressed ? AppTheme.pressed : homeMouse.containsMouse ? AppTheme.hover : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        AppIcon {
            anchors.centerIn: parent
            kind: "apps"
            width: 20
            height: 20
            iconColor: homeRow.active || homeMouse.containsMouse || homeMouse.pressed ? AppTheme.foreground : AppTheme.muted

            Behavior on iconColor {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 1
            color: AppTheme.border
        }

        MouseArea {
            id: homeMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: TabState.select(0)
        }

        ToolTip.visible: tabBar.collapsed && homeMouse.containsMouse
        ToolTip.text: qsTr("Home")
        ToolTip.delay: 500
    }

    ScrollView {
        id: docScroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            id: docColumn
            width: docScroll.availableWidth
            spacing: 0

            Repeater {
                id: rows
                model: TabState.docCount
                onItemAdded: (index, item) => {
                    item.pressPolicy = (sx, sy) => {
                        var p = item.mapToItem(docColumn, sx, sy);
                        tabBar.dragPress(p.y);
                    };
                    item.movePolicy = dy => tabBar.dragMove(dy);
                    item.releasePolicy = () => tabBar.dragRelease();
                }
                VerticalTab {
                    title: TabState.titleAt(index + 1)
                    active: TabState.currentIndex === index + 1
                    collapsed: tabBar.collapsed
                    onClicked: TabState.select(index + 1)
                    onCloseRequested: TabState.closeTab(index + 1)
                }
            }
        }
    }

    // New-tab row.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: tabBar.rowHeight
        color: plusMouse.pressed ? AppTheme.pressed : plusMouse.containsMouse ? AppTheme.hover : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 1
            color: AppTheme.border
        }

        AppIcon {
            anchors.centerIn: parent
            kind: "plus"
            width: 16
            height: 16
            iconColor: plusMouse.containsMouse || plusMouse.pressed ? AppTheme.foreground : AppTheme.muted
        }

        MouseArea {
            id: plusMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: TabState.addUntitled()
        }

        ToolTip.visible: plusMouse.containsMouse
        ToolTip.text: qsTr("New tab")
        ToolTip.delay: 500
    }

    // Collapse toggle row.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: tabBar.rowHeight
        color: collapseMouse.pressed ? AppTheme.pressed : collapseMouse.containsMouse ? AppTheme.hover : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 1
            color: AppTheme.border
        }

        AppIcon {
            anchors.centerIn: parent
            kind: "caret"
            width: 16
            height: 16
            rotation: tabBar.collapsed ? 270 : 90
            iconColor: collapseMouse.containsMouse || collapseMouse.pressed ? AppTheme.foreground : AppTheme.muted
        }

        MouseArea {
            id: collapseMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: SettingsStore.tabRailCollapsed = !SettingsStore.tabRailCollapsed
        }

        ToolTip.visible: collapseMouse.containsMouse
        ToolTip.text: tabBar.collapsed ? qsTr("Expand tabs") : qsTr("Collapse tabs")
        ToolTip.delay: 500
    }

    // Doc slot k (0-based) spans [k*rowHeight, (k+1)*rowHeight) inside
    // docColumn; results are doc model indices (1-based).
    function slotAt(barY) {
        var k = Math.floor(barY / tabBar.rowHeight);
        return Math.min(TabState.docCount - 1, Math.max(0, k)) + 1;
    }

    function slotY(modelIndex) {
        return (modelIndex - 1) * tabBar.rowHeight;
    }

    function dragPress(barY) {
        tabBar.dragFrom = tabBar.slotAt(barY);
        tabBar.pressBarY = barY;
        tabBar.lastBarY = barY;
        tabBar.tabDragging = false;
        tabBar.dropTarget = tabBar.dragFrom;
    }

    function dragMove(deltaY) {
        if (tabBar.dragFrom < 0)
            return;
        var barY = tabBar.pressBarY + deltaY;
        tabBar.lastBarY = barY;
        if (!tabBar.tabDragging && Math.abs(deltaY) <= 6)
            return;
        tabBar.tabDragging = true;
        tabBar.adoptSlot(barY);
        for (var i = 0; i < TabState.docCount; i++) {
            var item = rows.itemAt(i);
            if (!item)
                continue;
            var m = i + 1;
            if (m === tabBar.dragFrom) {
                item.gapShift = 0;
                item.dragOffset = barY - tabBar.pressBarY;
            } else if (tabBar.dragFrom < tabBar.dropTarget && m > tabBar.dragFrom && m <= tabBar.dropTarget) {
                item.gapShift = -tabBar.rowHeight;
                item.dragOffset = 0;
            } else if (tabBar.dropTarget < tabBar.dragFrom && m >= tabBar.dropTarget && m < tabBar.dragFrom) {
                item.gapShift = tabBar.rowHeight;
                item.dragOffset = 0;
            } else {
                item.gapShift = 0;
                item.dragOffset = 0;
            }
        }
    }

    // Hysteresis: a neighboring slot only wins past 12px penetration.
    function adoptSlot(barY) {
        var cur = tabBar.dropTarget;
        if (cur < 1)
            cur = tabBar.dragFrom;
        while (cur < TabState.docCount && barY > tabBar.slotY(cur) + tabBar.rowHeight + 12)
            cur++;
        while (cur > 1 && barY < tabBar.slotY(cur) - 12)
            cur--;
        tabBar.dropTarget = cur;
    }

    function dragRelease() {
        var glideItem = null;
        var dist = 0;
        if (tabBar.tabDragging && tabBar.dragFrom > 0 && tabBar.dropTarget > 0) {
            dist = tabBar.slotY(tabBar.dragFrom) + (tabBar.lastBarY - tabBar.pressBarY) - tabBar.slotY(tabBar.dropTarget);
            var target = tabBar.dropTarget;
            TabState.moveTab(tabBar.dragFrom, target);
            if (Math.abs(dist) > 1)
                glideItem = rows.itemAt(target - 1);
        }
        tabBar.clearDrag();
        if (glideItem) {
            glideItem.animateGap = false;
            glideItem.gapShift = dist;
            glideItem.animateGap = true;
            glideItem.gapShift = 0;
        }
    }

    function clearDrag() {
        tabBar.dragFrom = -1;
        tabBar.tabDragging = false;
        tabBar.dropTarget = -1;
        for (var i = 0; i < TabState.docCount; i++) {
            var item = rows.itemAt(i);
            if (!item)
                continue;
            item.animateGap = false;
            item.animateFollow = false;
            item.gapShift = 0;
            item.dragOffset = 0;
            item.animateGap = true;
            item.animateFollow = true;
        }
    }
}
