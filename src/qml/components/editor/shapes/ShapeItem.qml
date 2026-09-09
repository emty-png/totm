import QtQuick
import QtQuick.Shapes
import Totm

// One shape on the canvas. Root geometry IS the shape geometry
// (x/y/width/height/rotation bound from model roles by the repeater).
// Reports press/move/release; the canvas owns selection policy.
// Hidden shapes vanish entirely (no input); locked shapes render but
// swallow canvas presses without acting, so the marquee below never
// starts and selection policy stays untouched.
// Drag deltas are measured in window-stable global coords and forwarded
// in whole screen pixels (via zoom), so motion stays 1:1 smooth at any
// zoom - measuring in local coords would feed back as the item moves
// under the cursor and judder. Whole-pixel model snapping happens on
// release (see Document.snapSelection), never mid-gesture.
Item {
    id: shape

    // Model-bound props (set explicitly from roles, avoiding Item clashes).
    // NOTE: no `required` declarations for Repeater-injected names here —
    // they silently break sibling initializer bindings (verified).
    // Paint follows the sidebar order via depth (renumbered by the
    // document after every reorder); uid order must never drive paint.
    property int uid: -1
    property string shapeType: "rectangle"
    property real sx: 0
    property real sy: 0
    property real sw: 10
    property real sh: 10
    property real shapeRotation: 0
    property color fill: "#d9d9d9"
    property color strokeColor: "#000000"
    property real strokeWidth: 0
    property real shapeOpacity: 1
    property real radius: 0
    property bool independentCorners: false
    property var cornerRadii: []
    property bool flipH: false
    property bool flipV: false
    // Star tips; clamped 3..12 by the document on edit.
    property int points: 5
    // Pen subpaths in absolute content coords (meaningful for pen).
    // [{closed, pts: [{x, y, smooth, inX, inY, outX, outY}]}]
    property var pathData: []
    // Text content/style (meaningful when shapeType === "text").
    // letterSpacing stores percent of font size; rendering converts.
    property string textContent: ""
    property string fontFamily: "Inter"
    property int fontWeight: 400
    property real fontSize: 16
    property bool lineHeightAuto: true
    property real lineHeight: 1.2
    property real letterSpacing: 0
    property string hAlign: "left"
    property string vAlign: "top"
    property bool autoSize: true
    // True while the canvas inline editor owns this text: the static
    // glyphs hide so they never double-draw under the editor.
    property bool editing: false
    property bool selected: false
    property bool shapeVisible: true
    property bool shapeLocked: false
    property int paintDepth: 0
    property real zoom: 1

    // Selection policy callbacks, assigned by the canvas in onItemAdded
    // (calling item.customSignal() there would fail lint: onItemAdded's
    // item is statically QQuickItem, while plain assignments stay dynamic).
    property var activatePolicy: null
    property var pressPolicy: null
    property var movePolicy: null
    property var releasePolicy: null
    property var doublePolicy: null
    // Auto-size writeback for text: the canvas clamps and commits.
    property var measurePolicy: null

    x: shape.sx
    y: shape.sy
    width: shape.sw
    height: shape.sh
    z: shape.paintDepth
    rotation: shape.shapeRotation
    transformOrigin: Item.Center
    visible: shape.shapeVisible

    // Rectangle: native item (radius + stroke border built in).
    // Flip mirrors paint about the center in local space, under the
    // root rotation; geometry, outline and hit area keep the bbox.
    Rectangle {
        anchors.fill: parent
        visible: shape.shapeType === "rectangle" && !shape.independentCorners
        color: shape.fill
        radius: shape.radius
        border.width: shape.strokeWidth
        border.color: shape.strokeWidth > 0 ? shape.strokeColor : "transparent"
        opacity: shape.shapeOpacity
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: shape.sw / 2
            origin.y: shape.sh / 2
        }
    }

    // Other types: stroked/filled vector path (round joins, cute).
    // Independent rectangles join them so every corner keeps its own cut.
    Shape {
        anchors.fill: parent
        visible: (shape.shapeType !== "rectangle" && shape.shapeType !== "text") || (shape.shapeType === "rectangle" && shape.independentCorners)
        antialiasing: true
        opacity: shape.shapeOpacity
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: shape.sw / 2
            origin.y: shape.sh / 2
        }
        ShapePath {
            fillColor: shape.fill
            strokeColor: shape.strokeWidth > 0 ? shape.strokeColor : "transparent"
            strokeWidth: shape.strokeWidth
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathSvg {
                path: shape.vectorPath()
            }
        }
    }

    // Text: fill paints the glyphs; stroke is a native 1px outline
    // (Text has no outline-width API, so the width field only toggles
    // it on/off for text). Fixed boxes wrap, auto-size boxes grow (the
    // canvas writes measured sizes back).
    Item {
        id: textRoot

        anchors.fill: parent
        visible: shape.shapeType === "text" && !shape.editing
        opacity: shape.shapeOpacity
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: shape.sw / 2
            origin.y: shape.sh / 2
        }

        TextGlyphs {
            id: glyphs

            anchors.fill: parent
            text: shape.textContent
            color: shape.fill
            style: shape.strokeWidth > 0 ? Text.Outline : Text.Normal
            styleColor: shape.strokeColor
            family: shape.fontFamily
            weight: shape.fontWeight
            size: shape.fontSize
            spacingPct: shape.letterSpacing
            halign: shape.hAlign
            valign: shape.vAlign
            wrap: !shape.autoSize
            autoLeading: shape.lineHeightAuto
            leading: shape.lineHeight
            onContentSizeChanged: shape.reportMeasure()
        }
    }

    // Selection outline: constant screen size at any zoom (Figma bbox).
    Rectangle {
        visible: shape.selected
        x: -3 / shape.zoom
        y: -3 / shape.zoom
        width: parent.width + 6 / shape.zoom
        height: parent.height + 6 / shape.zoom
        color: "transparent"
        border.width: 1.5 / shape.zoom
        border.color: AppTheme.selection
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: shape.shapeLocked ? Qt.ForbiddenCursor : shape.moving ? Qt.ClosedHandCursor : Qt.ArrowCursor

        onPressed: event => shape.pressAt(event.x, event.y, event.modifiers)
        onPositionChanged: event => shape.moveAt(event.x, event.y)
        onReleased: event => shape.releaseAt(event.modifiers)
        onDoubleClicked: {
            if (shape.doublePolicy)
                shape.doublePolicy(shape.uid);
        }
    }

    // Move state lives here so press/move/release stay consistent.
    // lastGX/lastGY anchor the drag in global coords (stable while the
    // item moves); remCX/remCY bank sub-screen-pixel motion in content
    // units so not a pixel of travel is ever lost and only whole screen
    // pixels move shapes (smooth at any zoom; the document snaps the
    // resting values to whole pixels on release).
    // `refused` marks a press on a locked shape: claimed (so the marquee
    // below never starts) but never touching selection policy.
    property bool moving: false
    property bool dragged: false
    property bool refused: false
    property real lastGX: 0
    property real lastGY: 0
    property real startGX: 0
    property real startGY: 0
    property real remCX: 0
    property real remCY: 0

    // Corner points for the pointed shapes. Star alternates outer and
    // inner tips (first tip up); the inner notch is a fixed ratio.
    function cornerPoints() {
        var w = shape.sw, h = shape.sh;
        if (shape.shapeType === "triangle")
            return [w / 2, 0, w, h, 0, h];
        var n = Math.max(3, Math.min(12, Math.round(shape.points)));
        var cx = w / 2, cy = h / 2, inner = 0.4;
        var pts = [];
        for (var k = 0; k < n * 2; k++) {
            var a = -Math.PI / 2 + k * Math.PI / n;
            var rr = (k % 2 === 0) ? 1 : inner;
            pts.push(cx + w / 2 * rr * Math.cos(a), cy + h / 2 * rr * Math.sin(a));
        }
        return pts;
    }

    // Per-vertex radius in paint order. Uniform shapes return -1 so
    // the caller falls back to shape.radius; independent shapes read
    // cornerRadii (star maps outer tip k to vertex 2k, inner stays 0).
    function radiusAt(i, tipsOnly) {
        if (shape.independentCorners !== true)
            return -1;
        var arr = shape.cornerRadii || [];
        if (shape.shapeType === "star") {
            if (i % 2 === 1)
                return 0;
            var tip = i / 2;
            return tip < arr.length ? Math.max(0, Number(arr[tip]) || 0) : 0;
        }
        return i < arr.length ? Math.max(0, Number(arr[i]) || 0) : 0;
    }

    // Rounded rectangle with a cut per corner (TL,TR,BR,BL clockwise).
    // Overclaimed edges share proportionally like the polygons below.
    function rectPath() {
        var w = shape.sw, h = shape.sh;
        var src = shape.cornerRadii || [];
        var r = [];
        for (var i = 0; i < 4; i++)
            r.push(Math.max(0, i < src.length ? (Number(src[i]) || 0) : 0));
        var caps = [Math.min(w / 2, h / 2), Math.min(w / 2, h / 2), Math.min(w / 2, h / 2), Math.min(w / 2, h / 2)];
        for (var k = 0; k < 4; k++)
            r[k] = Math.min(r[k], caps[k]);
        var edges = [[0, 1, w], [1, 2, h], [2, 3, w], [3, 0, h]];
        for (var e = 0; e < 4; e++) {
            var a = edges[e][0], b = edges[e][1], len = edges[e][2];
            var sum = r[a] + r[b];
            if (len > 0 && sum > len) {
                r[a] *= len / sum;
                r[b] *= len / sum;
            }
        }
        var seg = (x1, y1, cx, cy, x2, y2, cut) => {
            if (cut <= 0)
                return " L " + x2 + "," + y2;
            return " L " + x1 + "," + y1 + " Q " + cx + "," + cy + " " + x2 + "," + y2;
        };
        var d = "M " + r[0] + ",0 L " + (w - r[1]) + ",0";
        d += seg(w - r[1], 0, w, 0, w, r[1], r[1]);
        d += seg(w, h - r[2], w, h, w - r[2], h, r[2]);
        d += seg(r[3], h, 0, h, 0, h - r[3], r[3]);
        d += seg(0, r[0], 0, 0, r[0], 0, r[0]);
        return d + " Z";
    }

    // Closed polygon path with per-vertex rounding. Each cut takes up to
    // the full neighbor edges; where two cuts would overlap an edge they
    // share it proportionally, so roundings meet into blobs instead of
    // folding over. tipsOnly rounds even vertices (star tips).
    function roundedPoly(pts, tipsOnly) {
        var n = pts.length / 2;
        var uniform = Math.max(0, shape.radius);
        var cut = [];
        for (var i = 0; i < n; i++) {
            var want = shape.radiusAt(i, tipsOnly);
            var r = want >= 0 ? want : uniform;
            if (r <= 0 || (tipsOnly && i % 2 === 1 && shape.independentCorners !== true)) {
                cut.push(0);
                continue;
            }
            var px = pts[((i - 1 + n) % n) * 2], py = pts[((i - 1 + n) % n) * 2 + 1];
            var vx = pts[i * 2], vy = pts[i * 2 + 1];
            var nx = pts[((i + 1) % n) * 2], ny = pts[((i + 1) % n) * 2 + 1];
            var l1 = Math.hypot(vx - px, vy - py);
            var l2 = Math.hypot(nx - vx, ny - vy);
            cut.push(l1 <= 0 || l2 <= 0 ? 0 : Math.min(r, l1, l2));
        }
        // Share overclaimed edges: neighbors meet instead of crossing.
        for (var e = 0; e < n; e++) {
            var f = e, g = (e + 1) % n;
            var len = Math.hypot(pts[g * 2] - pts[f * 2], pts[g * 2 + 1] - pts[f * 2 + 1]);
            var sum = cut[f] + cut[g];
            if (len > 0 && sum > len) {
                cut[f] *= len / sum;
                cut[g] *= len / sum;
            }
        }
        var d = "";
        for (var j = 0; j < n; j++) {
            var qx = pts[((j - 1 + n) % n) * 2], qy = pts[((j - 1 + n) % n) * 2 + 1];
            var wx = pts[j * 2], wy = pts[j * 2 + 1];
            var ex = pts[((j + 1) % n) * 2], ey = pts[((j + 1) % n) * 2 + 1];
            var m1 = Math.hypot(wx - qx, wy - qy);
            var m2 = Math.hypot(ex - wx, ey - wy);
            var ax = wx, ay = wy, bx = wx, by = wy;
            if (cut[j] > 0 && m1 > 0 && m2 > 0) {
                ax = wx - (wx - qx) / m1 * cut[j];
                ay = wy - (wy - qy) / m1 * cut[j];
                bx = wx + (ex - wx) / m2 * cut[j];
                by = wy + (ey - wy) / m2 * cut[j];
            }
            d += (j === 0 ? "M " : " L ") + ax + "," + ay;
            if (cut[j] > 0)
                d += " Q " + wx + "," + wy + " " + bx + "," + by;
        }
        return d + " Z";
    }

    // Pen subpath as local SVG. Anchors stay absolute in the model so
    // moves stay exact; paint subtracts the bbox origin. Smooth sides
    // emit cubics, corner sides collapse their control onto the anchor.
    function penPath() {
        var subs = shape.pathData || [];
        var ox = shape.sx, oy = shape.sy;
        var d = "";
        for (var s = 0; s < subs.length; s++) {
            var sub = subs[s] || {};
            var pts = sub.pts || [];
            if (pts.length === 0)
                continue;
            var first = pts[0] || {};
            d += (d === "" ? "M " : " M ") + ((Number(first.x) || 0) - ox) + "," + ((Number(first.y) || 0) - oy);
            var seg = (a, b) => {
                var ax = (Number(a.x) || 0) - ox, ay = (Number(a.y) || 0) - oy;
                var bx = (Number(b.x) || 0) - ox, by = (Number(b.y) || 0) - oy;
                var aSmooth = a.smooth === true, bSmooth = b.smooth === true;
                if (!aSmooth && !bSmooth)
                    return " L " + bx + "," + by;
                var c1x = aSmooth ? (a.outX !== undefined ? Number(a.outX) - ox : ax) : ax;
                var c1y = aSmooth ? (a.outY !== undefined ? Number(a.outY) - oy : ay) : ay;
                var c2x = bSmooth ? (b.inX !== undefined ? Number(b.inX) - ox : bx) : bx;
                var c2y = bSmooth ? (b.inY !== undefined ? Number(b.inY) - oy : by) : by;
                return " C " + c1x + "," + c1y + " " + c2x + "," + c2y + " " + bx + "," + by;
            };
            for (var i = 1; i < pts.length; i++)
                d += seg(pts[i - 1], pts[i]);
            if (sub.closed === true && pts.length > 1)
                d += seg(pts[pts.length - 1], pts[0]) + " Z";
        }
        return d;
    }

    function vectorPath() {
        var w = shape.sw, h = shape.sh;
        switch (shape.shapeType) {
        case "ellipse":
            {
                var rx = w / 2, ry = h / 2;
                return "M " + w + "," + h / 2 + " A " + rx + "," + ry + " 0 1,0 0," + h / 2 + " A " + rx + "," + ry + " 0 1,0 " + w + "," + h / 2 + " Z";
            }
        case "rectangle":
            return shape.independentCorners ? shape.rectPath() : "";
        case "triangle":
            return shape.roundedPoly(shape.cornerPoints(), false);
        case "star":
            return shape.roundedPoly(shape.cornerPoints(), true);
        case "pen":
            return shape.penPath();
        default:
            return "";
        }
    }

    // Auto-size writeback: reports the content text size so the canvas
    // can grow click-created boxes with content. Fixed boxes and the
    // inline-editing item stay quiet (the editor measures instead).
    function reportMeasure() {
        if (shape.shapeType !== "text" || !shape.autoSize || shape.editing)
            return;
        if (!shape.measurePolicy)
            return;
        shape.measurePolicy(shape.uid, glyphs.contentWidth, glyphs.contentHeight);
    }

    // Press/move/release entry points for the MouseArea above.
    function pressAt(x, y, modifiers) {
        var g = mouse.mapToGlobal(x, y);
        shape.moving = true;
        shape.dragged = false;
        shape.refused = shape.shapeLocked;
        shape.lastGX = g.x;
        shape.lastGY = g.y;
        shape.startGX = g.x;
        shape.startGY = g.y;
        shape.remCX = 0;
        shape.remCY = 0;
        if (shape.refused) {
            if (shape.activatePolicy)
                shape.activatePolicy();
            return;
        }
        if (shape.activatePolicy)
            shape.activatePolicy();
        if (shape.pressPolicy)
            shape.pressPolicy(shape.uid, modifiers);
    }

    function moveAt(x, y) {
        if (!shape.moving || shape.refused)
            return;
        var g = mouse.mapToGlobal(x, y);
        var z = shape.zoom > 0 ? shape.zoom : 1;
        var rawX = (g.x - shape.lastGX) / z, rawY = (g.y - shape.lastGY) / z;
        if (rawX === 0 && rawY === 0)
            return;
        shape.lastGX = g.x;
        shape.lastGY = g.y;
        if (Math.hypot(g.x - shape.startGX, g.y - shape.startGY) >= 4)
            shape.dragged = true;
        // Bank the fractional travel, forward only whole screen pixels.
        shape.remCX += rawX;
        shape.remCY += rawY;
        var scrX = shape.remCX * z, scrY = shape.remCY * z;
        var stepSX = scrX > 0 ? Math.floor(scrX) : Math.ceil(scrX);
        var stepSY = scrY > 0 ? Math.floor(scrY) : Math.ceil(scrY);
        if (stepSX === 0 && stepSY === 0)
            return;
        shape.remCX -= stepSX / z;
        shape.remCY -= stepSY / z;
        shape.dragged = true;
        if (shape.movePolicy)
            shape.movePolicy(stepSX / z, stepSY / z);
    }

    function releaseAt(modifiers) {
        if (!shape.moving)
            return;
        shape.moving = false;
        if (shape.refused) {
            shape.refused = false;
            return;
        }
        if (shape.releasePolicy)
            shape.releasePolicy(shape.dragged, modifiers);
    }
}
