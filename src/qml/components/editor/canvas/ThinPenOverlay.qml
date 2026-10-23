import QtQuick
import QtQuick.Shapes
import Totm

// Editor-only locator for selected or hovered pen paths whose authored
// stroke is too thin to resolve at the current canvas zoom. It never
// changes the artwork renderer or exported output: the blue hairline is
// selection chrome, like bounds and resize handles.
Item {
    id: overlay

    anchors.fill: parent

    required property var doc
    required property real zoom
    required property real offsetX
    required property real offsetY
    property int hoverUid: -1

    readonly property real cz: overlay.zoom > 0 ? overlay.zoom : 1
    readonly property var bezier: BezierMath {}

    function candidateNodes() {
        var d = overlay.doc;
        if (!d)
            return [];
        d.rev;
        var out = [];
        var seen = {};
        var tops = d.selectedTops ? d.selectedTops() : [];
        for (var i = 0; i < tops.length; i++) {
            var leaves = tops[i].kind === "shape" ? [tops[i]] : d._leavesUnder(tops[i]);
            for (var j = 0; j < leaves.length; j++) {
                var n = leaves[j];
                if (n && n.shapeType === "pen" && !seen[n.uid]) {
                    out.push(n);
                    seen[n.uid] = true;
                }
            }
        }
        var hover = d.findNode(overlay.hoverUid);
        if (hover && hover.kind === "shape" && hover.shapeType === "pen" && !seen[hover.uid])
            out.push(hover);
        return out;
    }

    function isThin(node) {
        var strokes = node ? (node.strokes || []) : [];
        for (var i = 0; i < strokes.length; i++) {
            var s = strokes[i] || {};
            var w = Number(s.width) || 0;
            if (s.enabled !== false && w > 0 && w * overlay.cz < 1)
                return true;
        }
        return false;
    }

    function pathFor(node) {
        var out = "";
        var subs = node ? (node.pathData || []) : [];
        for (var s = 0; s < subs.length; s++) {
            var sub = subs[s] || {};
            var pts = sub.pts || [];
            if (pts.length < 2)
                continue;
            var first = pts[0] || {};
            out += (out === "" ? "M " : " M ") + (Number(first.x) || 0) + "," + (Number(first.y) || 0);
            for (var i = 1; i < pts.length; i++)
                out += overlay.bezier.segSvg(pts[i - 1], pts[i]);
            if (sub.closed === true)
                out += overlay.bezier.segSvg(pts[pts.length - 1], first) + " Z";
        }
        return out;
    }

    Item {
        x: overlay.offsetX
        y: overlay.offsetY
        scale: overlay.cz
        transformOrigin: Item.TopLeft

        Repeater {
            model: overlay.candidateNodes()

            delegate: Shape {
                required property var modelData

                visible: overlay.isThin(modelData)
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: AppTheme.selection
                    strokeWidth: 1.5 / overlay.cz
                    PathSvg {
                        path: overlay.pathFor(modelData)
                    }
                }
            }
        }
    }
}
