import QtQuick
import QtQuick.Shapes
import Totm

// Cubic-bezier editing canvas: live curve over a linear reference,
// handle arms and two draggable handles. Handle drags report through
// policies (begin/move/end) so the caller coalesces them into one doc
// transaction; the in-drag curve renders from local working values.
Item {
    id: bezier

    property var bezier: [0.25, 0.1, 0.25, 1]
    property string easeId: "easeOut"

    property var beginPolicy: null
    property var movePolicy: null
    property var endPolicy: null

    property var dragBezier: null

    readonly property real pad: 14

    function shown() {
        return bezier.dragBezier || bezier.bezier;
    }

    function toX(bx) {
        return bezier.pad + bx * (bezier.width - 2 * bezier.pad);
    }

    function toY(by) {
        return bezier.pad + (1 - by) * (bezier.height - 2 * bezier.pad);
    }

    function fromPoint(mx, my) {
        return [Math.min(1, Math.max(0, (mx - bezier.pad) / (bezier.width - 2 * bezier.pad))), Math.min(1.5, Math.max(-0.5, 1 - (my - bezier.pad) / (bezier.height - 2 * bezier.pad)))];
    }

    function curveD() {
        var b = bezier.shown();
        var d = "";
        for (var i = 0; i <= 32; i++) {
            var x = i / 32;
            var y = sampler.easeValue(bezier.easeId, b, x);
            var px = (bezier.pad + x * (bezier.width - 2 * bezier.pad)).toFixed(1);
            var py = (bezier.pad + (1 - y) * (bezier.height - 2 * bezier.pad)).toFixed(1);
            d += (i === 0 ? "M " : " L ") + px + "," + py;
        }
        return d;
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: AppTheme.canvas
        border.width: 1
        border.color: AppTheme.fieldBorder
    }

    // Linear reference diagonal. Leading PathMove matters: a path
    // starting with PathLine implicitly moves to (0, 0) first and
    // draws a stray line down the left edge.
    Shape {
        anchors.fill: parent
        antialiasing: true

        ShapePath {
            strokeColor: AppTheme.muted
            strokeWidth: 1
            fillColor: "transparent"

            PathMove {
                x: bezier.toX(0)
                y: bezier.toY(0)
            }

            PathLine {
                x: bezier.toX(1)
                y: bezier.toY(1)
            }
        }
    }

    // Eased curve, sampled live.
    Shape {
        anchors.fill: parent
        antialiasing: true

        ShapePath {
            strokeColor: AppTheme.foreground
            strokeWidth: 2
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: bezier.curveD()
            }
        }
    }

    // Handle arms (leading move for the same stray-line reason).
    Shape {
        anchors.fill: parent
        antialiasing: true

        ShapePath {
            strokeColor: AppTheme.muted
            strokeWidth: 1
            fillColor: "transparent"

            PathMove {
                x: bezier.toX(0)
                y: bezier.toY(0)
            }

            PathLine {
                x: bezier.toX(0)
                y: bezier.toY(0)
            }

            PathLine {
                x: bezier.toX(bezier.shown()[0])
                y: bezier.toY(bezier.shown()[1])
            }

            PathMove {
                x: bezier.toX(1)
                y: bezier.toY(1)
            }

            PathLine {
                x: bezier.toX(bezier.shown()[2])
                y: bezier.toY(bezier.shown()[3])
            }
        }
    }

    // Handles, one per bezier control point (static pair, never
    // reordered, so direct canvas bindings stay valid).
    Repeater {
        model: [1, 2]

        Rectangle {
            id: knob

            readonly property int handleIndex: modelData || 0
            readonly property real handleX: bezier.shown()[handleIndex === 1 ? 0 : 2]
            readonly property real handleY: bezier.shown()[handleIndex === 1 ? 1 : 3]

            x: bezier.toX(handleX) - 7
            y: bezier.toY(handleY) - 7
            width: 14
            height: 14
            radius: 7
            color: AppTheme.snapGuide
            border.width: 2
            border.color: "#ffffff"

            MouseArea {
                id: handleMouse

                anchors.fill: parent
                anchors.margins: -6
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                onPressed: bezier.beginDrag()
                onPositionChanged: m => bezier.moveDrag(knob.handleIndex, handleMouse, m.x, m.y)
                onReleased: bezier.endDrag()
            }
        }
    }

    AnimSample {
        id: sampler
    }

    function beginDrag() {
        bezier.dragBezier = bezier.bezier.slice();
        if (bezier.beginPolicy)
            bezier.beginPolicy();
    }

    function moveDrag(which, area, mx, my) {
        if (!bezier.dragBezier)
            return;
        var pt = bezier.mapFromItem(area, mx, my);
        var b = bezier.fromPoint(pt.x, pt.y);
        if (which === 1) {
            bezier.dragBezier[0] = b[0];
            bezier.dragBezier[1] = b[1];
        } else {
            bezier.dragBezier[2] = b[0];
            bezier.dragBezier[3] = b[1];
        }
        // Reassign so curve and handle bindings refresh mid-drag.
        bezier.dragBezier = bezier.dragBezier.slice();
        if (bezier.movePolicy)
            bezier.movePolicy(bezier.dragBezier);
    }

    function endDrag() {
        bezier.dragBezier = null;
        if (bezier.endPolicy)
            bezier.endPolicy();
    }
}
