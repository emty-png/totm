import QtQuick
import QtQuick.Layouts
import Totm

// Left tab cluster: pinned home tab, document tabs, add (+) button.
// Fixed widths (home 46, docs 184) so the active blend cover in TitleBar
// can be positioned arithmetically. Doc tabs drag to reorder: the
// dragged tab follows the cursor while siblings slide open a gap;
// release commits through TabState.moveTab.
RowLayout {
    id: tabBar

    // Active tab geometry for the bottom-border cover (TitleBar draws it).
    // Doc tabs are 4x the 46px home tab = 184px.
    readonly property bool homeActive: TabState.currentIndex === 0
    readonly property real activeX: homeActive ? 0 : 46 + (TabState.currentIndex - 1) * 184
    readonly property real activeWidth: homeActive ? 46 : 184

    // Drag state: source model index, press x in bar coords, last cursor
    // x for the drop glide, live target slot.
    property int dragFrom: -1
    property real pressBarX: 0
    property real lastBarX: 0
    property bool tabDragging: false
    property int dropTarget: -1

    spacing: 0
    Layout.fillHeight: true

    TitleBarHomeTab {
        active: tabBar.homeActive
        onClicked: TabState.select(0)
    }

    Repeater {
        id: rows
        model: TabState.docCount
        onItemAdded: (index, item) => {
            item.pressPolicy = (sx, sy) => {
                var p = item.mapToItem(tabBar, sx, sy);
                tabBar.dragPress(p.x);
            };
            item.movePolicy = dx => tabBar.dragMove(dx);
            item.releasePolicy = () => tabBar.dragRelease();
        }
        TitleBarTab {
            // Delegate index stays injected: declaring it required breaks
            // sibling bindings at runtime.
            title: TabState.titleAt(index + 1)
            active: TabState.currentIndex === index + 1
            onClicked: TabState.select(index + 1)
            onCloseRequested: TabState.closeTab(index + 1)
        }
    }

    // New-tab button, same 46px width as window controls.
    TitleBarButton {
        iconKind: "plus"
        onClicked: TabState.addUntitled()
    }

    // Doc slot k (0-based) spans [46 + k*184, 46 + (k+1)*184); the home
    // tab is pinned, so results are doc model indices (1-based).
    function slotAt(barX) {
        var k = Math.floor((barX - 46) / 184);
        return Math.min(TabState.docCount - 1, Math.max(0, k)) + 1;
    }

    function slotX(modelIndex) {
        return 46 + (modelIndex - 1) * 184;
    }

    function dragPress(barX) {
        tabBar.dragFrom = tabBar.slotAt(barX);
        tabBar.pressBarX = barX;
        tabBar.lastBarX = barX;
        tabBar.tabDragging = false;
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
