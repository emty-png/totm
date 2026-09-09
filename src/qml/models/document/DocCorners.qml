import QtQuick

// Independent corner radii for rectangle/triangle/star. Counts follow
// paint order: rect TL,TR,BR,BL; triangle top,BR,BL; star outer tips
// from the top clockwise. Lengths resize on toggle and star-points
// edits; callers own undo, this only touches.
QtObject {
    id: corners
    required property var doc

    function countFor(node) {
        if (!node || node.kind !== "shape")
            return 0;
        if (node.shapeType === "rectangle")
            return 4;
        if (node.shapeType === "triangle")
            return 3;
        if (node.shapeType === "star")
            return Math.max(3, Math.min(12, Math.round(node.points)));
        return 0;
    }

    function cleanRadii(node) {
        return doc.factory._copyRadii(node.cornerRadii);
    }

    function ensureLength(node) {
        var want = corners.countFor(node);
        if (want <= 0)
            return [];
        var cur = corners.cleanRadii(node);
        while (cur.length < want)
            cur.push(Math.max(0, Number(node.radius) || 0));
        return cur.slice(0, want);
    }

    function toggle(uid, on) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return false;
        if (corners.countFor(n) <= 0)
            return false;
        if (on) {
            if (n.independentCorners === true)
                return true;
            n.independentCorners = true;
            n.cornerRadii = corners.ensureLength(n);
        } else {
            if (n.independentCorners !== true)
                return true;
            var cur = corners.cleanRadii(n);
            n.independentCorners = false;
            n.radius = cur.length > 0 ? cur[0] : (Math.max(0, Number(n.radius) || 0));
            n.cornerRadii = [];
        }
        doc.touch();
        return true;
    }

    function setUniform(uid, value) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return false;
        var v = Math.max(0, Number(value) || 0);
        n.radius = v;
        if (n.independentCorners === true) {
            var want = corners.countFor(n);
            var out = [];
            for (var i = 0; i < want; i++)
                out.push(v);
            n.cornerRadii = out;
        }
        doc.touch();
        return true;
    }

    function setCorner(uid, index, value) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || doc.isEffectivelyLocked(n))
            return false;
        if (n.independentCorners !== true)
            return false;
        var want = corners.countFor(n);
        if (index < 0 || index >= want)
            return false;
        var cur = corners.ensureLength(n);
        cur[index] = Math.max(0, Number(value) || 0);
        n.cornerRadii = cur;
        doc.touch();
        return true;
    }

    function adaptStarPoints(node) {
        if (!node || node.shapeType !== "star" || node.independentCorners !== true)
            return;
        node.cornerRadii = corners.ensureLength(node);
    }
}
