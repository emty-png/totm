import QtQuick

// One document node: either a leaf shape or a group container.
// Groups hold child nodes in `children` (array of DocNode, top-first).
// Geometry lives only on shapes; group bbox is derived in Document.
// All props are notifiable so canvas/layers delegates update in place
// without list rebuilds on geometry moves.
QtObject {
    id: node

    property int uid: -1
    // "shape" | "group"
    property string kind: "shape"
    property string name: ""

    // Shape geometry/style (meaningful when kind === "shape").
    property string shapeType: "rectangle"
    property real x: 0
    property real y: 0
    property real w: 10
    property real h: 10
    property real rotation: 0
    property color fill: "#d9d9d9"
    property color stroke: "#000000"
    property real strokeWidth: 0
    property real opacity: 1
    property real radius: 0
    // Independent corners (rectangle/triangle/star). When true the
    // renderer reads cornerRadii per vertex in paint order; toggling on
    // prefills from radius, toggling off folds back to corners[0].
    property bool independentCorners: false
    property var cornerRadii: []
    // Star tips; only meaningful when shapeType === "star".
    property int points: 5
    // Pen paths; only meaningful when shapeType === "pen". Absolute
    // content coords so moves/scales stay in one space with x/y. Each
    // subpath holds its own closed flag for multi-part vectors.
    // [{closed: bool, pts: [{x, y, smooth, inX, inY, outX, outY}]}]
    property var pathData: []
    // Text content/style; only meaningful when shapeType === "text".
    // fill paints the glyphs. lineHeight is a factor (1 = 100%);
    // lineHeightAuto renders natural spacing. letterSpacing is percent
    // of font size. autoSize grows the box with content (click-created);
    // fixed boxes wrap instead (drag-created).
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
    // Local-space mirror flags: paint mirrors about the shape center,
    // geometry and bbox stay untouched.
    property bool flipH: false
    property bool flipV: false
    // Image blob name under LibraryStore images/ (meaningful when
    // shapeType === "image"). Empty means missing; canvas shows a
    // placeholder and export paints a neutral box.
    property string imageSource: ""
    // Canvas paint order, assigned by Document.renumberZ (top-first DFS).
    property int zOrder: 0

    // Common state.
    property bool visible: true
    property bool locked: false
    property bool selected: false
    property bool renaming: false
    // Groups only: layers collapse (no canvas effect).
    property bool expanded: true

    // Group children (array of DocNode, top-first). Empty for shapes.
    property var children: []
}
