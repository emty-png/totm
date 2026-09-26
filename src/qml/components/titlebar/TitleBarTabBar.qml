import QtQuick
import QtQuick.Layouts
import Totm

// Left tab cluster: pinned home tab, scrollable document tabs, add (+) button.
// Fixed widths (home 46, docs 184) so the active blend cover in TitleBar
// can be positioned arithmetically. Doc tabs drag to reorder: the
// dragged tab follows the cursor while siblings slide open a gap;
// release commits through TabState.moveTab.
//
// Overflow: when the doc strip is wider than the available viewport, a
// 46px scroll button appears after home and before +. Each click scrolls
// by one tab (184px); the active tab auto-scrolls into view.
RowLayout {
    id: tabBar

    // Active tab geometry for the bottom-border cover (TitleBar draws it).
    // Doc tabs are 4x the 46px home tab = 184px. When overflowing, the
    // visible x shifts by contentX and the left scroll button offset.
    readonly property bool homeActive: TabState.currentIndex === 0
    readonly property real activeWidth: homeActive ? 46 : 184
    readonly property real activeX: {
        if (homeActive)
            return 0;
        return 46 + (tabBar.overflowing ? 46 : 0) + (tabBar.slotX(TabState.currentIndex) - docFlick.contentX);
    }
    // The cover should only paint when the active tab is fully visible.
    // Home is pinned, so always visible; docs need full viewport overlap.
    // Auto-reveal keeps the selection scrolled into view.
    readonly property bool activeVisible: {
        if (homeActive)
            return true;
        if (TabState.currentIndex < 1 || TabState.currentIndex > TabState.docCount)
            return false;
        if (!tabBar.overflowing)
            return true;
        var left = tabBar.slotX(TabState.currentIndex) - docFlick.contentX;
        return left >= -0.5 && (left + 184) <= docFlick.width + 0.5;
    }

    // Overflow bookkeeping. preferred/max exclude the scroll buttons so
    // showing them never grows the bar (stable, no layout oscillation):
    // the bar sizes to home+docs+plus, and the buttons steal viewport.
    readonly property int docContentWidth: TabState.docCount * 184
    readonly property real baseAvailableWidth: Math.max(0, tabBar.width - 92)
    readonly property bool overflowing: tabBar.docContentWidth > tabBar.baseAvailableWidth + 0.5
    readonly property real maxScroll: Math.max(0, tabBar.docContentWidth - docFlick.width)
    readonly property bool canScrollLeft: tabBar.overflowing && docFlick.contentX > 0.5
    readonly property bool canScrollRight: tabBar.overflowing && docFlick.contentX < tabBar.maxScroll - 0.5

    // Drag state: source model index, press x in content coords, last
    // cursor x for the drop glide, live target slot, edge-autoscroll dir.
    property int dragFrom: -1
    property real pressBarX: 0
    property real lastBarX: 0
    property bool tabDragging: false
    property int dropTarget: -1
    property int scrollDirection: 0

    spacing: 0
    Layout.fillHeight: true
    Layout.fillWidth: true
    Layout.preferredWidth: 92 + docContentWidth
    Layout.maximumWidth: 92 + docContentWidth
    Layout.minimumWidth: 92

    TitleBarHomeTab {
        active: tabBar.homeActive
        onClicked: TabState.select(0)
    }

    // Scroll left: one tab per click, clamped. Dimmed at the left edge.
    TitleBarButton {
        visible: tabBar.overflowing
        iconKind: "caret"
        iconRotation: 90
        opacity: tabBar.canScrollLeft ? 1 : 0.35
        onClicked: {
            if (tabBar.canScrollLeft)
                tabBar.scrollBy(-184);
        }
    }

    Flickable {
        id: docFlick

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: tabBar.docContentWidth
        contentWidth: tabBar.docContentWidth
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        // No Behavior on contentX: Flickable owns this property and a
        // running animation fights programmatic writes (scroll buttons,
        // auto-reveal, drag autoscroll), stranding the viewport at stale
        // offsets. All scrolls are instant; last write wins.

        Row {
            id: docRow
            width: tabBar.docContentWidth
            height: docFlick.height
            spacing: 0

            Repeater {
                id: rows
                model: TabState.docCount
                onItemAdded: (index, item) => {
                    item.pressPolicy = (sx, sy) => {
                        var p = item.mapToItem(docRow, sx, sy);
                        tabBar.dragPress(p.x);
                    };
                    item.movePolicy = dx => tabBar.dragMove(dx);
                    item.releasePolicy = () => tabBar.dragRelease();
                }
                TitleBarTab {
                    // Delegate index stays injected: declaring it required breaks
                    // sibling bindings at runtime.
                    // Explicit size: the strip is a plain Row (not a layout)
                    // so each tab sits at x = index * 184 regardless of
                    // viewport width or scroll-button visibility.
                    width: 184
                    height: docRow.height
                    title: TabState.titleAt(index + 1)
                    active: TabState.currentIndex === index + 1
                    onClicked: TabState.select(index + 1)
                    onCloseRequested: TabState.closeTab(index + 1)
                }
            }
        }
    }

    // Scroll right: one tab per click, clamped. Dimmed at the right edge.
    TitleBarButton {
        visible: tabBar.overflowing
        iconKind: "caret"
        iconRotation: 270
        opacity: tabBar.canScrollRight ? 1 : 0.35
        onClicked: {
            if (tabBar.canScrollRight)
                tabBar.scrollBy(184);
        }
    }

    // New-tab button, same 46px width as window controls.
    TitleBarButton {
        iconKind: "plus"
        onClicked: TabState.addUntitled()
    }

    // Edge autoscroll while dragging: parks within 24px of the viewport
    // edge scroll under the held cursor so far tabs stay reachable.
    Timer {
        id: scrollTimer
        interval: 16
        repeat: true
        running: tabBar.tabDragging && tabBar.scrollDirection !== 0
        onTriggered: {
            var next = Math.min(tabBar.maxScroll, Math.max(0, docFlick.contentX + tabBar.scrollDirection * 10));
            docFlick.contentX = next;
            tabBar.updateTargets(tabBar.lastBarX);
        }
    }

    // Clamp scroll when tabs close or the window grows.
    onMaxScrollChanged: {
        if (docFlick.contentX > tabBar.maxScroll)
            docFlick.contentX = tabBar.maxScroll;
    }

    // Auto-reveal the selection and newly opened tabs.
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
    onWidthChanged: {
        if (!tabBar.tabDragging)
            tabBar.ensureVisible(TabState.currentIndex);
    }

    function scrollBy(delta) {
        docFlick.contentX = Math.min(tabBar.maxScroll, Math.max(0, docFlick.contentX + delta));
    }

    function ensureVisible(modelIndex) {
        if (modelIndex < 1 || modelIndex > TabState.docCount)
            return;
        // The viewport may still be zero on the frame a tab is added
        // (outer layout hasn't granted the new width yet); the width
        // handler re-runs this once it settles, so skip rather than
        // scroll from stale geometry.
        if (docFlick.width <= 0)
            return;
        if (!tabBar.overflowing && docFlick.contentX !== 0)
            docFlick.contentX = 0;
        var left = tabBar.slotX(modelIndex);
        var right = left + 184;
        var viewLeft = docFlick.contentX;
        var viewRight = viewLeft + docFlick.width;
        if (left < viewLeft)
            docFlick.contentX = Math.min(tabBar.maxScroll, Math.max(0, left));
        else if (right > viewRight)
            docFlick.contentX = Math.min(tabBar.maxScroll, Math.max(0, right - docFlick.width));
    }

    // Doc slot k (0-based) spans [k*184, (k+1)*184) in content coords;
    // the home tab is pinned outside the flick, so results are doc model
    // indices (1-based).
    function slotAt(contentX) {
        var k = Math.floor(contentX / 184);
        return Math.min(TabState.docCount - 1, Math.max(0, k)) + 1;
    }

    function slotX(modelIndex) {
        return (modelIndex - 1) * 184;
    }

    function dragPress(contentX) {
        tabBar.dragFrom = tabBar.slotAt(contentX);
        tabBar.pressBarX = contentX;
        tabBar.lastBarX = contentX;
        tabBar.tabDragging = false;
        tabBar.scrollDirection = 0;
        tabBar.dropTarget = tabBar.dragFrom;
    }

    function dragMove(deltaX) {
        if (tabBar.dragFrom < 0)
            return;
        var barX = tabBar.pressBarX + deltaX;
        tabBar.lastBarX = barX;
        if (!tabBar.tabDragging && Math.abs(deltaX) <= 6)
            return;
        tabBar.tabDragging = true;
        tabBar.updateTargets(barX);
        tabBar.updateScroll(barX);
    }

    function updateTargets(barX) {
        tabBar.adoptSlot(barX);
        for (var i = 0; i < TabState.docCount; i++) {
            var item = rows.itemAt(i);
            if (!item)
                continue;
            var m = i + 1;
            if (m === tabBar.dragFrom) {
                item.gapShift = 0;
                // Fractional cursor delta from press: the tab keeps its
                // grab point and the follow trail (see dragOffset)
                // smooths it; rounding here flip-flops at x.5 instead.
                item.dragOffset = barX - tabBar.pressBarX;
            } else if (tabBar.dragFrom < tabBar.dropTarget && m > tabBar.dragFrom && m <= tabBar.dropTarget) {
                item.gapShift = -184;
                item.dragOffset = 0;
            } else if (tabBar.dropTarget < tabBar.dragFrom && m >= tabBar.dropTarget && m < tabBar.dragFrom) {
                item.gapShift = 184;
                item.dragOffset = 0;
            } else {
                item.gapShift = 0;
                item.dragOffset = 0;
            }
        }
    }

    // Edge zones (24px) steer the autoscroll timer; barX and contentX
    // share docRow coords, so compare against the viewport window.
    function updateScroll(barX) {
        if (!tabBar.tabDragging) {
            tabBar.scrollDirection = 0;
            return;
        }
        var viewLeft = docFlick.contentX;
        var viewRight = viewLeft + docFlick.width;
        if (barX < viewLeft + 24)
            tabBar.scrollDirection = -1;
        else if (barX > viewRight - 24)
            tabBar.scrollDirection = 1;
        else
            tabBar.scrollDirection = 0;
    }

    // Hysteresis: a neighboring slot only wins past 24px penetration, so
    // hovering a boundary never flickers siblings back and forth.
    function adoptSlot(barX) {
        var cur = tabBar.dropTarget;
        if (cur < 1)
            cur = tabBar.dragFrom;
        while (cur < TabState.docCount && barX > tabBar.slotX(cur) + 184 + 24)
            cur++;
        while (cur > 1 && barX < tabBar.slotX(cur) - 24)
            cur--;
        tabBar.dropTarget = cur;
    }

    function dragRelease() {
        var glideItem = null;
        var dist = 0;
        if (tabBar.tabDragging && tabBar.dragFrom > 0 && tabBar.dropTarget > 0) {
            dist = tabBar.slotX(tabBar.dragFrom) + (tabBar.lastBarX - tabBar.pressBarX) - tabBar.slotX(tabBar.dropTarget);
            var target = tabBar.dropTarget;
            TabState.moveTab(tabBar.dragFrom, target);
            if (Math.abs(dist) > 1)
                glideItem = rows.itemAt(target - 1);
        }
        tabBar.clearDrag();
        // Glide home: stage the cursor-to-slot distance instantly (gate
        // off, never paints mid-frame) and animate it away.
        if (glideItem) {
            glideItem.animateGap = false;
            glideItem.gapShift = dist;
            glideItem.animateGap = true;
            glideItem.gapShift = 0;
        }
    }

    // Instant reset, gates off: post-move layout already matches the gap
    // preview, so siblings are home the moment transforms clear. The
    // follow offset snaps with its gate off too, handing an exact
    // cursor position to the drop glide (no double counting).
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
