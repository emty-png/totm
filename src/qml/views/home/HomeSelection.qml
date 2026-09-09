import QtQuick
import Totm

// Card selection for one HomeView: selected design ids plus the set ops,
// library deletes and marquee hit-testing over the card delegates.
// Hit-testers take the card list and mapping item as arguments (never
// stored) so delegate rebuilds can never desync them. Ids reassign
// wholesale so card bindings update.
QtObject {
    id: selection

    property var selectedIds: []

    function isSelected(designId) {
        return selection.selectedIds.indexOf(designId) >= 0;
    }

    function selectOnly(designId) {
        selection.selectedIds = designId ? [designId] : [];
    }

    function toggleSelect(designId) {
        var ids = selection.selectedIds.slice();
        var at = ids.indexOf(designId);
        if (at >= 0)
            ids.splice(at, 1);
        else
            ids.push(designId);
        selection.selectedIds = ids;
    }

    function clearSelection() {
        if (selection.selectedIds.length > 0)
            selection.selectedIds = [];
    }

    // Marquee finished: collect cards whose rect touches the area.
    // Card delegates carry designId, so no index math is needed.
    function applyMarquee(kids, toItem, area, additive) {
        var hits = [];
        for (var i = 0; i < kids.length; i++) {
            var child = kids[i];
            if (child.designId === undefined || !child.designId)
                continue;
            var p = child.mapToItem(toItem, 0, 0);
            var touches = !(p.x > area.x + area.width || p.x + child.width < area.x || p.y > area.y + area.height || p.y + child.height < area.y);
            if (touches)
                hits.push(child.designId);
        }
        if (!additive) {
            selection.selectedIds = hits;
            return;
        }
        var ids = selection.selectedIds.slice();
        for (var j = 0; j < hits.length; j++) {
            if (ids.indexOf(hits[j]) < 0)
                ids.push(hits[j]);
        }
        selection.selectedIds = ids;
    }

    // Card under an overlay point, or null. Used to let card
    // presses fall through the marquee area to the cards.
    function cardAt(kids, toItem, x, y) {
        for (var i = 0; i < kids.length; i++) {
            var child = kids[i];
            if (child.designId === undefined || !child.designId)
                continue;
            var p = child.mapToItem(toItem, 0, 0);
            if (x >= p.x && x < p.x + child.width && y >= p.y && y < p.y + child.height)
                return child;
        }
        return null;
    }

    function deleteSelected() {
        var ids = selection.selectedIds.slice();
        if (ids.length === 0)
            return;
        for (var i = 0; i < ids.length; i++) {
            TabStore.closeTabByDesign(ids[i]);
            LibraryStore.deleteDesign(ids[i]);
        }
        selection.selectedIds = [];
    }

    function deleteDesignOrSelected(designId) {
        if (selection.isSelected(designId) && selection.selectedIds.length > 1) {
            selection.deleteSelected();
            return selection.selectedIds.length;
        }
        TabStore.closeTabByDesign(designId);
        LibraryStore.deleteDesign(designId);
        var ids = selection.selectedIds.slice();
        var at = ids.indexOf(designId);
        if (at >= 0) {
            ids.splice(at, 1);
            selection.selectedIds = ids;
        }
        return 1;
    }
}
