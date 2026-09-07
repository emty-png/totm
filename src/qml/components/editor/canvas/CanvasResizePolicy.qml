import QtQuick

// BBox resize policy for one canvas. Snapshots press state, scales absolutely.
QtObject {
    id: resizePolicy
    required property var canvas
    required property var snap

    function isCornerHandle(hid) {
        return hid === "nw" || hid === "ne" || hid === "sw" || hid === "se";
    }

    function resizePressed(hid, cx, cy, mods) {
        canvas.forceActiveFocus();
        canvas.altHeld = !!(mods & Qt.AltModifier);
        var d = canvas.doc, b = canvas.selBox;
        if (!d || !b)
            return;
        var orig = d.selectedLeafSnapshot();
        if (orig.length === 0)
            return;
        canvas.resizeState = {
            hid: hid,
            box0: {
                x: b.x,
                y: b.y,
                w: b.w,
                h: b.h
            },
            orig: orig
        };
        canvas.snapXGuides = [];
        canvas.snapYGuides = [];
        resizeApply(cx, cy, mods, false);
    }

    function resizeMoved(cx, cy, mods) {
        resizeApply(cx, cy, mods, true);
    }

    function resizeReleased() {
        if (canvas.resizeState && canvas.doc)
            canvas.doc.snapSelection();
        canvas.resizeState = null;
        canvas.measureBox = null;
        canvas.snapXGuides = [];
        canvas.snapYGuides = [];
    }

    function handleDoubleClicked(cx, cy, mods) {
        canvas.resizeState = null;
        canvas.snapXGuides = [];
        canvas.snapYGuides = [];
        var leaf = canvas.topLeafAt(cx, cy);
        if (leaf < 0)
            return;
        canvas.shapePressed(leaf, mods);
        canvas.shapeDoubleClicked(leaf);
        // Balance the synthetic press (no release will ever come for it).
        canvas.clickArmedUid = -1;
        canvas.moveAllowed = false;
    }

    function resizeApply(cx, cy, mods, live) {
        var st = canvas.resizeState, d = canvas.doc;
        if (!st || !d)
            return;
        var b0 = st.box0;
        var nx, ny, nw, nh;
        if (st.hid === "e" || st.hid === "ne" || st.hid === "se") {
            nx = b0.x;
            nw = cx - b0.x;
        } else if (st.hid === "w" || st.hid === "nw" || st.hid === "sw") {
            nx = cx;
            nw = b0.x + b0.w - cx;
        } else {
            nx = b0.x;
            nw = b0.w;
        }
        if (st.hid === "s" || st.hid === "se" || st.hid === "sw") {
            ny = b0.y;
            nh = cy - b0.y;
        } else if (st.hid === "n" || st.hid === "ne" || st.hid === "nw") {
            ny = cy;
            nh = b0.y + b0.h - cy;
        } else {
            ny = b0.y;
            nh = b0.h;
        }
        // Clamp to 1px first so the aspect scale below stays positive.
        if (nw < 1) {
            if (nx !== b0.x)
                nx = b0.x + b0.w - 1;
            nw = 1;
        }
        if (nh < 1) {
            if (ny !== b0.y)
                ny = b0.y + b0.h - 1;
            nh = 1;
        }
        if (!!(mods & Qt.ShiftModifier) && isCornerHandle(st.hid) && b0.w > 0 && b0.h > 0) {
            var s = Math.max(nw / b0.w, nh / b0.h);
            nw = b0.w * s;
            nh = b0.h * s;
            if (nx !== b0.x)
                nx = b0.x + b0.w - nw;
            if (ny !== b0.y)
                ny = b0.y + b0.h - nh;
            canvas.snapXGuides = [];
            canvas.snapYGuides = [];
        } else if (canvas.altHeld || !!(mods & Qt.AltModifier)) {
            // Alt suspends the magnet for free resizes.
            canvas.altHeld = true;
            canvas.snapXGuides = [];
            canvas.snapYGuides = [];
        } else {
            // Smart-snap the dragged edges (skipped while aspect-locked
            // so Shift keeps exact proportions).
            var snappedBox = snap.snapResize(d, {
                x: nx,
                y: ny,
                w: nw,
                h: nh
            }, st.hid, canvas.zoom);
            nx = snappedBox.box.x;
            ny = snappedBox.box.y;
            nw = snappedBox.box.w;
            nh = snappedBox.box.h;
            canvas.snapXGuides = snappedBox.xGuides;
            canvas.snapYGuides = snappedBox.yGuides;
        }
        d.scaleSelection(st.orig, b0, {
            x: nx,
            y: ny,
            w: nw,
            h: nh
        });
        // Size readout follows the live (post-snap) box at the cursor.
        if (live) {
            canvas.cursorX = canvas.offsetX + cx * canvas.zoom;
            canvas.cursorY = canvas.offsetY + cy * canvas.zoom;
            canvas.measureBox = {
                w: nw,
                h: nh
            };
        }
    }
}
