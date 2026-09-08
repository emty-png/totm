import QtQuick

// Node construction for one Document. Fresh uids, defaults for creation snapshots. Operates on the owning Document via `doc`.
QtObject {
    id: factory
    required property var doc

    function _makeShapeNode(type, snap) {
        var uid = doc.nextNodeUid++;
        var s = snap ?? {};
        // Every field defaults: creation snapshots carry geometry only,
        // clipboard snapshots carry the full style set.
        var n = doc.nodeFactory.createObject(doc, {
            uid: uid,
            kind: "shape",
            shapeType: type,
            name: s.name ?? (doc.shapeLabel(type) + " " + uid),
            x: s.x ?? 0,
            y: s.y ?? 0,
            w: s.w ?? 10,
            h: s.h ?? 10,
            rotation: s.rotation ?? 0,
            fill: s.fill ?? "#d9d9d9",
            stroke: s.stroke ?? "#000000",
            strokeWidth: s.strokeWidth ?? 0,
            opacity: s.opacity ?? 1,
            radius: s.radius ?? 0,
            points: s.points ?? 5,
            flipH: s.flipH ?? false,
            flipV: s.flipV ?? false,
            textContent: s.textContent ?? "",
            fontFamily: s.fontFamily ?? "Inter",
            fontWeight: s.fontWeight ?? 400,
            fontSize: s.fontSize ?? 16,
            lineHeightAuto: s.lineHeightAuto !== false,
            lineHeight: s.lineHeight ?? 1.2,
            letterSpacing: s.letterSpacing ?? 0,
            hAlign: s.hAlign ?? "left",
            vAlign: s.vAlign ?? "top",
            autoSize: s.autoSize ?? (type === "text"),
            selected: true,
            visible: s.visible !== false,
            locked: false,
            renaming: false,
            expanded: true,
            children: []
        });
        return n;
    }

    function _makeGroupNode(name, children) {
        var uid = doc.nextNodeUid++;
        var n = doc.nodeFactory.createObject(doc, {
            uid: uid,
            kind: "group",
            name: name || ("Group " + uid),
            selected: true,
            visible: true,
            locked: false,
            renaming: false,
            expanded: true,
            children: children || []
        });
        return n;
    }

    function addShape(type, x, y, w, h) {
        var container = doc._activeContainerUid();
        doc.clearSelection();
        var n = _makeShapeNode(type, {
            x: Math.round(x),
            y: Math.round(y),
            w: Math.max(1, Math.round(w)),
            h: Math.max(1, Math.round(h))
        });
        var list = doc._childrenOf(container).slice();
        list.unshift(n);
        doc._setChildren(container, list);
        doc.anchorUid = n.uid;
        doc._refreshStructural();
        return n.uid;
    }

    // Text creation: click passes autoSize with a measured box, drag
    // passes a fixed wrapping box. Content starts empty; the canvas
    // opens the inline editor right after.
    function addText(x, y, w, h, auto) {
        var container = doc._activeContainerUid();
        doc.clearSelection();
        var n = _makeShapeNode("text", {
            x: Math.round(x),
            y: Math.round(y),
            w: Math.max(1, Math.round(w)),
            h: Math.max(1, Math.round(h)),
            fill: "#000000",
            autoSize: auto
        });
        var list = doc._childrenOf(container).slice();
        list.unshift(n);
        doc._setChildren(container, list);
        doc.anchorUid = n.uid;
        doc._refreshStructural();
        return n.uid;
    }
}
