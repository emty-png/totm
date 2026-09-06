import QtQuick

// Selection and marquee policy for one canvas. Resolves presses to group targets.
QtObject {
    id: selectPolicy
    required property var canvas
    required property var snap

    function applyMarquee(area, additive) {
        if (!canvas.doc)
            return;
        canvas.doc.selectInRect((area.x - canvas.offsetX) / canvas.zoom, (area.y - canvas.offsetY) / canvas.zoom, area.width / canvas.zoom, area.height / canvas.zoom, additive);
    }

    function shapePressed(uid, mods) {
        if (!canvas.doc)
            return;
        canvas.altHeld = !!(mods & Qt.AltModifier);
        var target = canvas.doc.resolvePress(uid);
        var multi = !!(mods & (Qt.ShiftModifier | Qt.ControlModifier | Qt.MetaModifier));
        var sel = canvas.doc.isSelected(target);
        if (multi && sel) {
            canvas.doc.toggleSelect(target);
            canvas.moveAllowed = false;
            canvas.clickArmedUid = -1;
        } else {
            if (!sel) {
                if (multi)
                    canvas.doc.addToSelection(target);
                else
                    canvas.doc.selectOnly(target);
            } else {
                canvas.clickArmedUid = target;
            }
            canvas.moveAllowed = true;
        }
    }

    function shapeDoubleClicked(uid) {
        if (!canvas.doc)
            return;
        var target = canvas.doc.resolvePress(uid);
        var n = canvas.doc.findNode(target);
        if (n && n.kind === "group")
            canvas.doc.drillInto(target);
        else {
            // Double-clicking a leaf inside a group drills into its direct
            // parent group (Figma feel).
            var hit = canvas.doc._find(uid);
            if (hit) {
                for (var i = hit.ancestors.length - 1; i >= 0; i--) {
                    if (hit.ancestors[i].kind === "group") {
                        canvas.doc.drillInto(hit.ancestors[i].uid);
                        break;
                    }
                }
            }
        }
    }

    function shapeMoved(dx, dy) {
        if (!canvas.moveAllowed || !canvas.doc)
            return;
        // Smart-snap the selection bbox: shift the desired box to the
        // winning edge/spacing alignment (5 screen px), then move by the
        // adjusted delta. Guides show while dragging; the pixel settle
        // still runs on release. Alt suspends the magnet for free moves.
        var adjDx = dx, adjDy = dy;
        var b = canvas.selBox;
        if (b && !canvas.altHeld) {
            var want = {
                x: b.x + dx,
                y: b.y + dy,
                w: b.w,
                h: b.h
            };
            var snapped = snap.snapMove(canvas.doc, want, canvas.zoom);
            adjDx = dx + snapped.dx;
            adjDy = dy + snapped.dy;
            canvas.snapXGuides = snapped.xGuides;
            canvas.snapYGuides = snapped.yGuides;
        } else {
            canvas.snapXGuides = [];
            canvas.snapYGuides = [];
        }
        canvas.doc.moveSelected(adjDx, adjDy);
        canvas.clickArmedUid = -1;
    }

    function shapeReleased(wasMoved, mods) {
        if (wasMoved && canvas.doc)
            canvas.doc.snapSelection();
        if (!wasMoved && canvas.clickArmedUid >= 0 && !(mods & (Qt.ShiftModifier | Qt.ControlModifier | Qt.MetaModifier)) && canvas.doc)
            canvas.doc.selectOnly(canvas.clickArmedUid);
        canvas.clickArmedUid = -1;
        canvas.moveAllowed = false;
        canvas.snapXGuides = [];
        canvas.snapYGuides = [];
    }

    function computeSelBox() {
        // Kept for callers during migration; the tree source of truth is
        // Document.selectionBBox (group-aware).
        return canvas.doc ? canvas.doc.selectionBBox() : null;
    }

    function topLeafAt(cx, cy) {
        var d = canvas.doc;
        if (!d)
            return -1;
        var leaves = d.leafList;
        for (var i = 0; i < leaves.length; i++) {
            var s = leaves[i];
            if (!d.isEffectivelyVisible(s) || d.isEffectivelyLocked(s))
                continue;
            var b = d.rotatedBounds(s);
            if (cx >= b.x && cx <= b.x + b.w && cy >= b.y && cy <= b.y + b.h)
                return s.uid;
        }
        return -1;
    }
}
