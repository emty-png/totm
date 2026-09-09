import QtQuick
import Totm

// Screen-space canvas visuals. All 1px lines stay crisp at any zoom
// via screen = offset + content * zoom. Static guide pool keeps
// bindings resolvable without a Repeater.
Item {
    id: overlays

    anchors.fill: parent

    required property var doc
    required property var draft
    required property real zoom
    required property real offsetX
    required property real offsetY
    required property bool marqueeActive
    required property rect marqueeRect
    required property var snapXGuides
    required property var snapYGuides
    // Live measurement state (content coords unless noted).
    required property var snapXGap
    required property var snapYGap
    required property var measureBox
    required property real cursorX
    required property real cursorY

    // Draft types whose paint is not their bbox (need the ghost above).
    function draftIsPointed() {
        var t = overlays.draft ? overlays.draft.type : "";
        return t === "ellipse" || t === "triangle" || t === "star";
    }

    // Bbox wash while dragging rectangles and text boxes (their real
    // paint is a box too). Pointed shapes get a true-shape ghost below.
    Rectangle {
        visible: overlays.draft !== null && !overlays.draftIsPointed()
        x: overlays.draft ? overlays.offsetX + overlays.draft.x * overlays.zoom : 0
        y: overlays.draft ? overlays.offsetY + overlays.draft.y * overlays.zoom : 0
        width: overlays.draft ? overlays.draft.w * overlays.zoom : 0
        height: overlays.draft ? overlays.draft.h * overlays.zoom : 0
        color: "#140d99ff"
        border.width: 1
        border.color: AppTheme.selection
    }

    // True-shape drag ghost for ellipse/triangle/star: reuses ShapeItem
    // paint (same vectorPath as the committed shape) in content space so
    // it lands 1:1 at any zoom. Wash fill + 1px selection stroke like the
    // bbox draft; blind input so the draw gesture passes through.
    Item {
        visible: overlays.draft !== null && overlays.draftIsPointed()
        x: overlays.offsetX
        y: overlays.offsetY
        scale: overlays.zoom
        transformOrigin: Item.TopLeft

        ShapeItem {
            shapeType: overlays.draft ? overlays.draft.type : "ellipse"
            sx: overlays.draft ? overlays.draft.x : 0
            sy: overlays.draft ? overlays.draft.y : 0
            sw: overlays.draft ? Math.max(1, overlays.draft.w) : 1
            sh: overlays.draft ? Math.max(1, overlays.draft.h) : 1
            fill: "#140d99ff"
            strokeColor: AppTheme.selection
            strokeWidth: 1 / (overlays.zoom > 0 ? overlays.zoom : 1)
            interactive: false
            zoom: overlays.zoom
        }
    }

    Rectangle {
        visible: overlays.doc !== null
        x: overlays.offsetX - 1
        y: overlays.offsetY - 1
        width: (overlays.doc ? overlays.doc.sceneWidth : 0) * overlays.zoom + 2
        height: (overlays.doc ? overlays.doc.sceneHeight : 0) * overlays.zoom + 2
        color: "transparent"
        border.width: 1
        border.color: AppTheme.sceneFrame
    }

    Rectangle {
        visible: overlays.marqueeActive
        x: overlays.marqueeRect.x
        y: overlays.marqueeRect.y
        width: overlays.marqueeRect.width
        height: overlays.marqueeRect.height
        color: "#140d99ff"
        border.width: 1
        border.color: AppTheme.selection
    }

    Item {
        anchors.fill: parent
        visible: overlays.snapXGuides.length > 0 || overlays.snapYGuides.length > 0

        Rectangle {
            visible: overlays.snapXGuides.length > 0
            x: Math.round(overlays.offsetX + overlays.snapXGuides[0] * overlays.zoom)
            width: 1
            height: parent.height
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapXGuides.length > 1
            x: Math.round(overlays.offsetX + overlays.snapXGuides[1] * overlays.zoom)
            width: 1
            height: parent.height
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapXGuides.length > 2
            x: Math.round(overlays.offsetX + overlays.snapXGuides[2] * overlays.zoom)
            width: 1
            height: parent.height
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapXGuides.length > 3
            x: Math.round(overlays.offsetX + overlays.snapXGuides[3] * overlays.zoom)
            width: 1
            height: parent.height
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapXGuides.length > 4
            x: Math.round(overlays.offsetX + overlays.snapXGuides[4] * overlays.zoom)
            width: 1
            height: parent.height
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapXGuides.length > 5
            x: Math.round(overlays.offsetX + overlays.snapXGuides[5] * overlays.zoom)
            width: 1
            height: parent.height
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapXGuides.length > 6
            x: Math.round(overlays.offsetX + overlays.snapXGuides[6] * overlays.zoom)
            width: 1
            height: parent.height
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapXGuides.length > 7
            x: Math.round(overlays.offsetX + overlays.snapXGuides[7] * overlays.zoom)
            width: 1
            height: parent.height
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapYGuides.length > 0
            y: Math.round(overlays.offsetY + overlays.snapYGuides[0] * overlays.zoom)
            height: 1
            width: parent.width
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapYGuides.length > 1
            y: Math.round(overlays.offsetY + overlays.snapYGuides[1] * overlays.zoom)
            height: 1
            width: parent.width
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapYGuides.length > 2
            y: Math.round(overlays.offsetY + overlays.snapYGuides[2] * overlays.zoom)
            height: 1
            width: parent.width
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapYGuides.length > 3
            y: Math.round(overlays.offsetY + overlays.snapYGuides[3] * overlays.zoom)
            height: 1
            width: parent.width
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapYGuides.length > 4
            y: Math.round(overlays.offsetY + overlays.snapYGuides[4] * overlays.zoom)
            height: 1
            width: parent.width
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapYGuides.length > 5
            y: Math.round(overlays.offsetY + overlays.snapYGuides[5] * overlays.zoom)
            height: 1
            width: parent.width
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapYGuides.length > 6
            y: Math.round(overlays.offsetY + overlays.snapYGuides[6] * overlays.zoom)
            height: 1
            width: parent.width
            color: AppTheme.snapGuide
        }
        Rectangle {
            visible: overlays.snapYGuides.length > 7
            y: Math.round(overlays.offsetY + overlays.snapYGuides[7] * overlays.zoom)
            height: 1
            width: parent.width
            color: AppTheme.snapGuide
        }
    }

    // Size pill at the cursor while resizing or drawing.
    MeasurePill {
        id: sizePill

        label: overlays.measureBox ? Math.round(overlays.measureBox.w) + " × " + Math.round(overlays.measureBox.h) : ""
        shown: overlays.measureBox !== null
        x: Math.min(Math.max(overlays.cursorX + 14, 4), Math.max(4, parent.width - width - 4))
        y: Math.min(Math.max(overlays.cursorY + 18, 4), Math.max(4, parent.height - height - 4))
    }

    // Equal-gap measurement: red span across the gap with its value.
    Item {
        visible: overlays.snapXGap !== null

        Rectangle {
            x: overlays.snapXGap ? Math.round(overlays.offsetX + overlays.snapXGap.x0 * overlays.zoom) : 0
            y: overlays.snapXGap ? Math.round(overlays.offsetY + overlays.snapXGap.y * overlays.zoom) : 0
            width: overlays.snapXGap ? Math.max(1, Math.round((overlays.snapXGap.x1 - overlays.snapXGap.x0) * overlays.zoom)) : 0
            height: 1
            color: AppTheme.snapGuide
        }

        MeasurePill {
            label: overlays.snapXGap ? String(Math.round(overlays.snapXGap.x1 - overlays.snapXGap.x0)) : ""
            shown: overlays.snapXGap !== null
            x: overlays.snapXGap ? Math.round(overlays.offsetX + (overlays.snapXGap.x0 + overlays.snapXGap.x1) / 2 * overlays.zoom) - width / 2 : 0
            y: overlays.snapXGap ? Math.round(overlays.offsetY + overlays.snapXGap.y * overlays.zoom) - height / 2 : 0
        }
    }

    Item {
        visible: overlays.snapYGap !== null

        Rectangle {
            x: overlays.snapYGap ? Math.round(overlays.offsetX + overlays.snapYGap.x * overlays.zoom) : 0
            y: overlays.snapYGap ? Math.round(overlays.offsetY + overlays.snapYGap.y0 * overlays.zoom) : 0
            width: 1
            height: overlays.snapYGap ? Math.max(1, Math.round((overlays.snapYGap.y1 - overlays.snapYGap.y0) * overlays.zoom)) : 0
            color: AppTheme.snapGuide
        }

        MeasurePill {
            label: overlays.snapYGap ? String(Math.round(overlays.snapYGap.y1 - overlays.snapYGap.y0)) : ""
            shown: overlays.snapYGap !== null
            x: overlays.snapYGap ? Math.round(overlays.offsetX + overlays.snapYGap.x * overlays.zoom) - width / 2 : 0
            y: overlays.snapYGap ? Math.round(overlays.offsetY + (overlays.snapYGap.y0 + overlays.snapYGap.y1) / 2 * overlays.zoom) - height / 2 : 0
        }
    }
}
