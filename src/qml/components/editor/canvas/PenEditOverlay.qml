import QtQuick
import QtQuick.Shapes
import Totm

// Edit-mode points for the pen node under PenEdit. Anchors stay
// square/circle by smooth flag, selected fill blue, handles only for
// the selection, hover rings + edge-insert ghost while idle. Reads
// doc.rev so drags repaint without new props.
Item {
    id: overlay

    anchors.fill: parent

    required property var tool
    required property var doc
    required property real zoom
    required property real offsetX
    required property real offsetY
    required property bool editActive

    visible: overlay.editActive && overlay.editNode() !== null

    readonly property real cz: overlay.zoom > 0 ? overlay.zoom : 1
    readonly property real dot: 9 / overlay.cz
    readonly property real small: 6 / overlay.cz

    function editNode() {
        if (!overlay.doc || !overlay.tool || overlay.tool.editUid < 0)
            return null;
        return overlay.doc.findNode(overlay.tool.editUid);
    }

    function allPts() {
        if (overlay.doc)
            overlay.doc.rev;
        var n = overlay.editNode();
        if (!n)
            return [];
        var out = [];
        var path = n.pathData || [];
        for (var s = 0; s < path.length; s++) {
            var pts = (path[s] || {}).pts || [];
            for (var i = 0; i < pts.length; i++) {
                out.push({
                    sub: s,
                    idx: i,
                    pt: pts[i] || {}
                });
            }
        }
        return out;
    }

    function selHandles() {
        if (overlay.doc)
            overlay.doc.rev;
        var n = overlay.editNode();
        if (!n || !overlay.tool)
            return [];
        var out = [];
        for (var k = 0; k < overlay.tool.sel.length; k++) {
            var s = overlay.tool.sel[k].sub, i = overlay.tool.sel[k].idx;
            var path = n.pathData || [];
            if (!path[s] || !path[s].pts[i])
                continue;
            var p = path[s].pts[i] || {};
            if (p.smooth !== true)
                continue;
            out.push({
                sub: s,
                idx: i,
                pt: p
            });
        }
        return out;
    }

    function isSel(sub, idx) {
        if (!overlay.tool)
            return false;
        for (var i = 0; i < overlay.tool.sel.length; i++) {
            if (overlay.tool.sel[i].sub === sub && overlay.tool.sel[i].idx === idx)
                return true;
        }
        return false;
    }

    // Hover affordances while idle (hidden mid-drag so the live geometry
    // reads clean). Hover carries kind point/handle/edge; positions look
    // up the node so rings track drags via doc.rev.
    readonly property bool hoverIdle: overlay.tool && overlay.tool.drag === null && overlay.tool.hover !== null
    function hoverPoint() {
        if (overlay.doc)
            overlay.doc.rev;
        if (!overlay.hoverIdle || overlay.tool.hover.kind !== "point")
            return null;
        var n = overlay.editNode();
        var h = overlay.tool.hover;
        var path = n ? (n.pathData || []) : [];
        if (!path[h.sub] || !path[h.sub].pts[h.idx])
            return null;
        var p = path[h.sub].pts[h.idx] || {};
        return {
            x: Number(p.x) || 0,
            y: Number(p.y) || 0,
            smooth: p.smooth === true,
            selected: overlay.isSel(h.sub, h.idx)
        };
    }
    function hoverHandle() {
        if (overlay.doc)
            overlay.doc.rev;
        if (!overlay.hoverIdle || overlay.tool.hover.kind !== "handle")
            return null;
        var n = overlay.editNode();
        var h = overlay.tool.hover;
        var path = n ? (n.pathData || []) : [];
        if (!path[h.sub] || !path[h.sub].pts[h.idx])
            return null;
        var p = path[h.sub].pts[h.idx] || {};
        if (p.smooth !== true)
            return null;
        var hx = h.which === "in" ? (p.inX !== undefined ? Number(p.inX) : Number(p.x)) : (p.outX !== undefined ? Number(p.outX) : Number(p.x));
        var hy = h.which === "in" ? (p.inY !== undefined ? Number(p.inY) : Number(p.y)) : (p.outY !== undefined ? Number(p.outY) : Number(p.y));
        return {
            x: hx || 0,
            y: hy || 0
        };
    }
    function hoverEdge() {
        if (!overlay.hoverIdle || overlay.tool.hover.kind !== "edge" || !overlay.tool.hover.pt)
            return null;
        return overlay.tool.hover.pt;
    }

    Item {
        x: overlay.offsetX
        y: overlay.offsetY
        scale: overlay.cz
        transformOrigin: Item.TopLeft

        Repeater {
            model: overlay.selHandles()

            delegate: Item {
                required property var modelData

                visible: modelData.pt.smooth === true

                Shape {
                    antialiasing: true

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: AppTheme.selection
                        strokeWidth: 1 / overlay.cz
                        PathSvg {
                            path: "M " + modelData.pt.inX + "," + modelData.pt.inY + " L " + modelData.pt.x + "," + modelData.pt.y + " L " + modelData.pt.outX + "," + modelData.pt.outY
                        }
                    }
                }

                Rectangle {
                    x: modelData.pt.inX - overlay.small / 2
                    y: modelData.pt.inY - overlay.small / 2
                    width: overlay.small
                    height: overlay.small
                    radius: overlay.small / 2
                    color: "#ffffff"
                    border.width: 1 / overlay.cz
                    border.color: AppTheme.selection
                }

                Rectangle {
                    x: modelData.pt.outX - overlay.small / 2
                    y: modelData.pt.outY - overlay.small / 2
                    width: overlay.small
                    height: overlay.small
                    radius: overlay.small / 2
                    color: "#ffffff"
                    border.width: 1 / overlay.cz
                    border.color: AppTheme.selection
                }
            }
        }

        Repeater {
            model: overlay.allPts()

            delegate: Rectangle {
                required property var modelData

                readonly property bool selected: overlay.isSel(modelData.sub, modelData.idx)
                readonly property bool isSmooth: modelData.pt.smooth === true

                x: modelData.pt.x - width / 2
                y: modelData.pt.y - height / 2
                width: overlay.dot
                height: overlay.dot
                radius: isSmooth ? width / 2 : 1 / overlay.cz
                color: selected ? AppTheme.selection : "#ffffff"
                border.width: 1.5 / overlay.cz
                border.color: AppTheme.selection
            }
        }

        // Point hover ring (skips selected: those already read blue).
        Rectangle {
            property var hp: overlay.hoverPoint()
            visible: hp !== null && hp.selected !== true
            x: hp ? hp.x - width / 2 : 0
            y: hp ? hp.y - height / 2 : 0
            width: overlay.dot + 4 / overlay.cz
            height: overlay.dot + 4 / overlay.cz
            radius: hp && hp.smooth ? width / 2 : 2 / overlay.cz
            color: "transparent"
            border.width: 1.5 / overlay.cz
            border.color: AppTheme.selection
        }

        // Handle hover swell.
        Rectangle {
            property var hh: overlay.hoverHandle()
            visible: hh !== null
            x: hh ? hh.x - width / 2 : 0
            y: hh ? hh.y - height / 2 : 0
            width: overlay.small + 4 / overlay.cz
            height: overlay.small + 4 / overlay.cz
            radius: width / 2
            color: "transparent"
            border.width: 1.5 / overlay.cz
            border.color: AppTheme.selection
        }

        // Edge-insert ghost: what the click would add.
        Rectangle {
            property var he: overlay.hoverEdge()
            visible: he !== null
            x: he ? he.x - width / 2 : 0
            y: he ? he.y - height / 2 : 0
            width: overlay.dot
            height: overlay.dot
            radius: width / 2
            color: "#ffffff"
            opacity: 0.9
            border.width: 1.5 / overlay.cz
            border.color: AppTheme.selection
        }
    }
}
