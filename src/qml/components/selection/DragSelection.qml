import QtQuick

// Marquee selection logic core: no visuals, no input handling.
// Owns the drag state machine (press/move/release with threshold) and
// reports the normalized rect. Pair with any MouseArea + rect visual,
// or use DragSelectionBox for the batteries-included overlay.
// (State is flat typed properties — not a holder object — so member
// access stays statically resolvable.)
QtObject {
    id: logic

    property real threshold: 4
    property real sx: 0
    property real sy: 0
    property real x: 0
    property real y: 0
    property real w: 0
    property real h: 0
    property bool active: false

    readonly property bool selecting: logic.active
    readonly property rect selection: Qt.rect(logic.x, logic.y, logic.w, logic.h)

    signal started
    signal changed(rect area)
    signal finished(rect area, bool additive)
    signal tapped

    function pressAt(px, py) {
        logic.sx = px;
        logic.sy = py;
        logic.x = px;
        logic.y = py;
        logic.w = 0;
        logic.h = 0;
        logic.active = false;
    }

    function moveTo(px, py) {
        if (!logic.active) {
            if (Math.hypot(px - logic.sx, py - logic.sy) < logic.threshold)
                return;
            logic.active = true;
            logic.started();
        }
        logic.x = Math.min(logic.sx, px);
        logic.y = Math.min(logic.sy, py);
        logic.w = Math.abs(px - logic.sx);
        logic.h = Math.abs(py - logic.sy);
        logic.changed(logic.selection);
    }

    function release(additive) {
        if (!logic.active) {
            logic.tapped();
            return;
        }
        logic.active = false;
        logic.finished(logic.selection, !!additive);
        logic.w = 0;
        logic.h = 0;
    }
}
