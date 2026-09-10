import QtQuick

// Edge alignment for moving boxes: left/center/right edges against
// target lists. Operates via `engine` facade.
QtObject {
    id: snapEdge
    required property var engine

    function edgeMove(box, targets, thresh) {
        var bestDx = 0, bestDy = 0, foundX = false, foundY = false;
        var xOffs = [0, box.w / 2, box.w], yOffs = [0, box.h / 2, box.h];
        for (var a = 0; a < 3; a++) {
            var ex = box.x + xOffs[a];
            for (var i = 0; i < targets.xs.length; i++) {
                var dx = targets.xs[i] - ex;
                if (Math.abs(dx) <= thresh && (!foundX || Math.abs(dx) < Math.abs(bestDx))) {
                    bestDx = dx;
                    foundX = true;
                }
            }
        }
        for (var b = 0; b < 3; b++) {
            var ey = box.y + yOffs[b];
            for (var j = 0; j < targets.ys.length; j++) {
                var dy = targets.ys[j] - ey;
                if (Math.abs(dy) <= thresh && (!foundY || Math.abs(dy) < Math.abs(bestDy))) {
                    bestDy = dy;
                    foundY = true;
                }
            }
        }
        var xG = [], yG = [];
        if (foundX) {
            for (var k = 0; k < targets.xs.length; k++) {
                for (var m = 0; m < 3; m++) {
                    if (Math.abs(targets.xs[k] - (box.x + xOffs[m] + bestDx)) < 0.01)
                        xG.push(targets.xs[k]);
                }
            }
        }
        if (foundY) {
            for (var n = 0; n < targets.ys.length; n++) {
                for (var p = 0; p < 3; p++) {
                    if (Math.abs(targets.ys[n] - (box.y + yOffs[p] + bestDy)) < 0.01)
                        yG.push(targets.ys[n]);
                }
            }
        }
        return {
            dx: foundX ? bestDx : 0,
            dy: foundY ? bestDy : 0,
            xGuides: engine.dedup(xG),
            yGuides: engine.dedup(yG),
            hasX: foundX,
            hasY: foundY
        };
    }
}
