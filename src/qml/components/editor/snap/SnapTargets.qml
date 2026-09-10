import QtQuick

// Snap target collection: edge lists from unselected boxes plus scene
// edges/centers. Operates via `engine` facade.
QtObject {
    id: snapTargets
    required property var engine

    function threshFor(zoom) {
        var z = zoom > 0 ? zoom : 1;
        return engine.screenThreshold / z;
    }

    function collectOthers(doc) {
        if (!doc || !doc.unselectedSnapBoxes)
            return [];
        return doc.unselectedSnapBoxes();
    }

    function targetLists(doc, others) {
        var xs = [], ys = [];
        for (var i = 0; i < others.length; i++) {
            var b = others[i];
            xs.push(b.x, b.x + b.w / 2, b.x + b.w);
            ys.push(b.y, b.y + b.h / 2, b.y + b.h);
        }
        if (doc) {
            xs.push(0, doc.sceneWidth / 2, doc.sceneWidth);
            ys.push(0, doc.sceneHeight / 2, doc.sceneHeight);
        }
        return {
            xs: xs,
            ys: ys
        };
    }

    function dedup(list) {
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var v = list[i], found = false;
            for (var j = 0; j < out.length; j++) {
                if (Math.abs(out[j] - v) < 0.001) {
                    found = true;
                    break;
                }
            }
            if (!found)
                out.push(v);
        }
        return out;
    }
}
