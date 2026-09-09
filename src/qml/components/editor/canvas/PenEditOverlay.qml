import QtQuick
import QtQuick.Shapes
import Totm

// Edit-mode points for the pen node under PenEdit. Anchors stay
// square/circle by smooth flag, selected fill blue, handles only for
// the selection. Reads doc.rev so drags repaint without new props.
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
    }
}
