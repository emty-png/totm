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
    // Rail side for the active blend strips ("left" or "right").
    property string side: "left"
    readonly property int rowHeight: 40
    readonly property int railWidth: tabBar.collapsed ? 52 : 192

    // Drag state: source model index, press y in column coords, last
    // cursor y for the drop glide, live target slot. scrollDirection
    // drives edge autoscroll while dragging (-1 up, 0 off, 1 down).
    property int dragFrom: -1
    property real pressBarY: 0
    property real lastBarY: 0
    property bool tabDragging: false
    property int dropTarget: -1
    property int scrollDirection: 0

    // Overflow: scroll buttons appear only when the doc rows exceed
    // the viewport. Each click scrolls one row (40px); the active row
    // auto-scrolls into view. Compared against the base height (without
    // buttons) so hiding the buttons always exits overflow (no stuck-on).
    readonly property real baseAvailableHeight: Math.max(0, tabBar.height - 3 * tabBar.rowHeight)
    readonly property bool overflowing: docColumn.height > tabBar.baseAvailableHeight + 0.5
    readonly property real maxScrollY: Math.max(0, docFlick.contentHeight - docFlick.height)
    readonly property bool canScrollUp: tabBar.overflowing && docFlick.contentY > 0.5
    readonly property bool canScrollDown: tabBar.overflowing && docFlick.contentY < tabBar.maxScrollY - 0.5

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

        // Active blend strip, same language as the doc rows below.
        Rectangle {
            anchors {
                top: parent.top
                bottom: parent.bottom
            }
            x: tabBar.side === "left" ? homeRow.width - 1 : 0
            width: 1
            visible: homeRow.active
            color: AppTheme.background
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

    // Scroll-up overflow button: one row per click, only when overflowing.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: tabBar.rowHeight
        visible: tabBar.overflowing
        opacity: tabBar.canScrollUp ? 1 : 0.35
        color: upMouse.pressed ? AppTheme.pressed : upMouse.containsMouse ? AppTheme.hover : "transparent"

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
                bottom: parent.bottom
            }
            height: 1
            color: AppTheme.border
        }

        AppIcon {
            anchors.centerIn: parent
            kind: "caret"
            width: 16
            height: 16
            rotation: 180
            iconColor: upMouse.containsMouse || upMouse.pressed ? AppTheme.foreground : AppTheme.muted
        }

        MouseArea {
            id: upMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (tabBar.canScrollUp)
                    tabBar.scrollBy(-tabBar.rowHeight);
            }
        }

        ToolTip.visible: upMouse.containsMouse
        ToolTip.text: qsTr("Scroll tabs up")
        ToolTip.delay: 500
    }

    // Scrollable document rows. A bare Flickable (not ScrollView) so
    // drag autoscroll can read and drive contentY directly.
    Flickable {
        id: docFlick

        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: width
        contentHeight: docColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        // No Behavior on contentY (see TitleBarTabBar): programmatic
        // scrolls stay instant so auto-reveal/clamping always converge.

        Column {
            id: docColumn
            width: docFlick.width
            // Explicit height: a plain Column (not a layout) stacks rows
            // deterministically at y = index * rowHeight, independent of
            // viewport height or scroll-button visibility. This also feeds
            // contentHeight/overflowing below.
            height: TabState.docCount * tabBar.rowHeight
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
                    // Explicit size: plain Column parent positions by
                    // width/height instead of Layout props.
                    width: docColumn.width
                    height: tabBar.rowHeight
                    title: TabState.titleAt(index + 1)
                    active: TabState.currentIndex === index + 1
                    collapsed: tabBar.collapsed
                    side: tabBar.side
                    onClicked: TabState.select(index + 1)
                    onCloseRequested: TabState.closeTab(index + 1)
                }
            }
        }
    }

    // Edge autoscroll: while a dragged tab parks within 24px of the
    // viewport edge, the list scrolls under it so far tabs stay
    // reachable. Each step re-runs target adoption at the held cursor.
    Timer {
        id: scrollTimer

        interval: 16
        repeat: true
        running: tabBar.tabDragging && tabBar.scrollDirection !== 0
        onTriggered: {
            var maxY = Math.max(0, docFlick.contentHeight - docFlick.height);
            docFlick.contentY = Math.min(maxY, Math.max(0, docFlick.contentY + tabBar.scrollDirection * 10));
            tabBar.updateTargets(tabBar.lastBarY);
        }
    }

    // Scroll-down overflow button: one row per click, only when overflowing.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: tabBar.rowHeight
        visible: tabBar.overflowing
        opacity: tabBar.canScrollDown ? 1 : 0.35
        color: downMouse.pressed ? AppTheme.pressed : downMouse.containsMouse ? AppTheme.hover : "transparent"

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
            rotation: 0
            iconColor: downMouse.containsMouse || downMouse.pressed ? AppTheme.foreground : AppTheme.muted
        }

        MouseArea {
            id: downMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (tabBar.canScrollDown)
                    tabBar.scrollBy(tabBar.rowHeight);
            }
        }

        ToolTip.visible: downMouse.containsMouse
        ToolTip.text: qsTr("Scroll tabs down")
        ToolTip.delay: 500
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

    // Clamp scroll when tabs close and auto-reveal selection changes.
    onMaxScrollYChanged: {
        if (docFlick.contentY > tabBar.maxScrollY)
            docFlick.contentY = tabBar.maxScrollY;
    }

    Connections {
        target: TabState
        function onCurrentIndexChanged() {
            if (!tabBar.tabDragging)
                tabBar.ensureVisible(TabState.currentIndex);
        }
        function onDocCountChanged() {
            if (!tabBar.tabDragging)
                tabBar.ensureVisible(TabState.currentIndex);
        }
    }
    onHeightChanged: {
        if (!tabBar.tabDragging)
            tabBar.ensureVisible(TabState.currentIndex);
    }

    function scrollBy(delta) {
        docFlick.contentY = Math.min(tabBar.maxScrollY, Math.max(0, docFlick.contentY + delta));
    }

    function ensureVisible(modelIndex) {
        if (modelIndex < 1 || modelIndex > TabState.docCount)
            return;
        // Skip while the viewport is still zero (first polish after a
        // tab add); the height handler re-runs this once it settles.
        if (docFlick.height <= 0)
            return;
        var top = tabBar.slotY(modelIndex);
        var bottom = top + tabBar.rowHeight;
        var viewTop = docFlick.contentY;
        var viewBottom = viewTop + docFlick.height;
        if (top < viewTop)
            docFlick.contentY = Math.min(tabBar.maxScrollY, Math.max(0, top));
        else if (bottom > viewBottom)
            docFlick.contentY = Math.min(tabBar.maxScrollY, Math.max(0, bottom - docFlick.height));
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
        tabBar.updateTargets(barY);
        tabBar.updateScroll(barY);
    }

    function updateTargets(barY) {
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

    // Edge zones (24px) steer the autoscroll timer; barY and contentY
    // share docColumn coords, so no mapping is needed.
    function updateScroll(barY) {
        if (!tabBar.tabDragging) {
            tabBar.scrollDirection = 0;
            return;
        }
        var viewTop = docFlick.contentY;
        var viewBottom = viewTop + docFlick.height;
        if (barY < viewTop + 24)
            tabBar.scrollDirection = -1;
        else if (barY > viewBottom - 24)
            tabBar.scrollDirection = 1;
        else
            tabBar.scrollDirection = 0;
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
        tabBar.scrollDirection = 0;
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
