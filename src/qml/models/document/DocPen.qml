import QtQuick

// Pen point edits for one Document. All ops reassign pathData wholesale
// so bindings fire, then resync x/y/w/h from the factory bbox.
// Callers own undo (checkpoint or begin/end); this only touches.
QtObject {
    id: pen
    required property var doc

    function _node(uid) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || n.shapeType !== "pen")
            return null;
        if (doc.isEffectivelyLocked(n))
            return null;
        return n;
    }

    function _sync(n, path) {
        n.pathData = path;
        var box = doc.factory.penBBoxFor(path);
        n.x = box.x;
        n.y = box.y;
        n.w = box.w;
        n.h = box.h;
        doc.touch();
    }

    function movePoint(uid, sub, idx, dx, dy) {
        var n = pen._node(uid);
        if (!n)
            return false;
        var path = doc.factory._copyPath(n.pathData);
        if (!path[sub] || !path[sub].pts[idx])
            return false;
        var p = path[sub].pts[idx];
        p.x += dx;
        p.y += dy;
        p.inX += dx;
        p.inY += dy;
        p.outX += dx;
        p.outY += dy;
        pen._sync(n, path);
        return true;
    }

    function moveHandle(uid, sub, idx, which, x, y) {
        var n = pen._node(uid);
        if (!n)
            return false;
        var path = doc.factory._copyPath(n.pathData);
        if (!path[sub] || !path[sub].pts[idx])
            return false;
        var p = path[sub].pts[idx];
        if (which === "in") {
            p.inX = x;
            p.inY = y;
            p.outX = p.x + (p.x - x);
            p.outY = p.y + (p.y - y);
        } else {
            p.outX = x;
            p.outY = y;
            p.inX = p.x + (p.x - x);
            p.inY = p.y + (p.y - y);
        }
        p.smooth = true;
        pen._sync(n, path);
        return true;
    }

    function toggleSmooth(uid, sub, idx) {
        var n = pen._node(uid);
        if (!n)
            return false;
        var path = doc.factory._copyPath(n.pathData);
        if (!path[sub] || !path[sub].pts[idx])
            return false;
        var p = path[sub].pts[idx];
        if (p.smooth === true) {
            p.smooth = false;
            p.inX = p.x;
            p.inY = p.y;
            p.outX = p.x;
            p.outY = p.y;
        } else {
            p.smooth = true;
            p.inX = p.x - 20;
            p.inY = p.y;
            p.outX = p.x + 20;
            p.outY = p.y;
        }
        pen._sync(n, path);
        return true;
    }

    function insertPoint(uid, sub, at, pt) {
        var n = pen._node(uid);
        if (!n)
            return false;
        var path = doc.factory._copyPath(n.pathData);
        if (!path[sub])
            return false;
        var pts = path[sub].pts || [];
        if (at < 0)
            at = 0;
        if (at > pts.length)
            at = pts.length;
        pts.splice(at, 0, {
            x: pt.x,
            y: pt.y,
            smooth: false,
            inX: pt.x,
            inY: pt.y,
            outX: pt.x,
            outY: pt.y
        });
        path[sub].pts = pts;
        pen._sync(n, path);
        return true;
    }

    function deletePoint(uid, sub, idx) {
        var n = doc.findNode(uid);
        if (!n || n.kind !== "shape" || n.shapeType !== "pen")
            return false;
        if (doc.isEffectivelyLocked(n))
            return false;
        var path = doc.factory._copyPath(n.pathData);
        if (!path[sub] || !path[sub].pts[idx])
            return false;
        path[sub].pts.splice(idx, 1);
        if (path[sub].pts.length === 0)
            path.splice(sub, 1);
        if (path.length === 0) {
            var hit = doc._find(uid);
            if (!hit)
                return false;
            var list = doc._childrenOf(hit.parentUid).slice();
            list.splice(hit.index, 1);
            doc._setChildren(hit.parentUid, list);
            n.destroy();
            doc.pruneDrillPath();
            doc.anchorUid = -1;
            doc._refreshStructural();
            return true;
        }
        pen._sync(n, path);
        return true;
    }
}
