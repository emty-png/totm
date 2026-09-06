import QtQuick
import Totm

// Smart snapping entry point. Threshold stays 5 screen px so the magnet
// feels the same at any zoom. Work lives in snap/ helpers; this facade
// only owns the threshold and forwards calls.
QtObject {
    id: root

    readonly property real screenThreshold: 5

    property var targets: SnapTargets {
        engine: root
    }
    property var edge: SnapEdge {
        engine: root
    }
    property var spacing: SnapSpacing {
        engine: root
    }
    property var combos: SnapCombinators {
        engine: root
    }

    function threshFor(zoom) {
        return targets.threshFor(zoom);
    }
    function collectOthers(doc) {
        return targets.collectOthers(doc);
    }
    function targetLists(doc, others) {
        return targets.targetLists(doc, others);
    }
    function dedup(list) {
        return targets.dedup(list);
    }
    function edgeMove(box, t, thresh) {
        return edge.edgeMove(box, t, thresh);
    }
    function spacingMove(box, others, thresh) {
        return spacing.spacingMove(box, others, thresh);
    }
    function snapMove(doc, box, zoom) {
        return combos.snapMove(doc, box, zoom);
    }
    function snapResize(doc, newBox, hid, zoom) {
        return combos.snapResize(doc, newBox, hid, zoom);
    }
    function snapPoint(doc, px, py, zoom) {
        return combos.snapPoint(doc, px, py, zoom);
    }
    function snapCreate(doc, sx, sy, cx, cy, zoom) {
        return combos.snapCreate(doc, sx, sy, cx, cy, zoom);
    }
}
