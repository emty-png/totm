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
    // Stacked paints (index 0 paints topmost):
    // fills: [{enabled, color, type ("solid"|"linear"), gradient {angle,
    //   stops:[{color,pos} x2..8, sorted]}, opacity 0..1}]. Final fill alpha =
    //   color alpha * opacity * leaf opacity. Empty = no fill.
    // strokes: [{enabled, color, type, gradient, width, dash [d,g] in
    //   width units, position ("center"|"inside"|"outside"), opacity}].
    // Cap/join stay per-shape (pen section); dash/width/position are
    // per entry. All strokes paint above all fills.
    property var fills: []
    property var strokes: []
    property real opacity: 1
    // Pen-only paint switches. penFill toggles the path fill (open
    // strokes usually want line-art only); strokeCap/strokeJoin pick the
    // line ends and bends ("round" default matches the old hardcoded
    // paint, so other shapes render identically).
    property bool penFill: true
    property string strokeCap: "round"
    property string strokeJoin: "round"
    // Stacked effects: shadows and glows are lists (index 0 paints
    // topmost, like layers), blurs and grain are singletons. Render
    // order is fixed: backgroundBlur (backdrop) -> outer shadows ->
    // outer glows -> fill -> inner shadows -> inner glows -> stroke ->
    // layerBlur (whole stack) -> grain on top.
    property var shadows: []
    property var glows: []
    property var layerBlur: ({
            enabled: false,
            radius: 8,
            opacity: 1
        })
    property var backgroundBlur: ({
            enabled: false,
            radius: 16,
            opacity: 0.7
        })
    // Animated film grain. Dots derive from (cell, seed) with
    // seed = uid * 73856093 ^ frame * 19349663; preview and export
    // share the formula, so the shimmer matches exactly.
    property var grain: ({
            enabled: false,
            amount: 0.5,
            size: 2
        })
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
    property bool fontItalic: false
    property bool fontUnderline: false
    property bool fontStrike: false
    property string fontCaps: "none"
    // Rich spans: [{start, len, bold, italic, underline, strike, color}]
    // over textContent (UTF-16 offsets); empty = single box style.
    // Run color ("") paints box fills; set colors paint solid instead.
    // Bold maps to weight 700, otherwise the box weight applies.
    property var textRuns: []
    property bool lineHeightAuto: true
    property real lineHeight: 1.2
    property real letterSpacing: 0
    property string hAlign: "left"
    property string vAlign: "top"
    property bool autoSize: true
    // Sampler-driven karaoke/sweep reveal (plain data, backend-readable):
    // {fx, fxReveal 0..1, fxStagger 0..1, fxRise px, fxHighlight color,
    //  fxSweep bool, fxUnit letters|words|lines}. Null = full glyphs.
    property var textFx: null
    // Local-space mirror flags: paint mirrors about the shape center,
    // geometry and bbox stay untouched.
    property bool flipH: false
    property bool flipV: false
    // Image blob name under LibraryStore images/ (meaningful when
    // shapeType === "image"). Empty means missing; canvas shows a
    // placeholder and export paints a neutral box.
    property string imageSource: ""
    // Video blob name under LibraryStore videos/ (meaningful when
    // shapeType === "video"). Legacy absolute paths still resolve while
    // the file exists. Empty means missing; canvas shows a placeholder
    // and export paints the poster/neutral box. videoDuration is the
    // probed file length in seconds (0 = unknown, no looping math).
    property string videoSource: ""
    property real videoDuration: 0
    property real videoOffset: 0
    property bool videoMuted: false
    property real videoVolume: 1
    property real playbackRate: 1
    property bool videoLoop: true
    // Object-fit for the decoded frame inside the shape box: "fit"
    // preserves aspect with transparent letterbox, "cover" crops to fill,
    // "fill" stretches (legacy). Missing normalizes to "fit".
    property string videoFit: "fit"
    // Timeline placement in composition seconds: the video is hidden
    // before videoStart, then plays offset + (t - start) * rate.
    // Default 0 reproduces the legacy always-from-zero behavior.
    property real videoStart: 0
    // Transient footage-time override in footage seconds, written by
    // customVideoTime clips during preview (-1 = off, legacy
    // offset/rate/loop math applies). Never snapshotted: snapshotNode
    // whitelists persisted fields, and restoreBaseValues resets it.
    property real videoTime: -1
    // Transient content-zoom override, written by customVideoZoom clips
    // during preview (1 = off). Focal rides 0..1 of the frame. Same
    // transient contract as videoTime: never snapshotted, always reset.
    property real videoZoom: 1
    property real videoZoomX: 0.5
    property real videoZoomY: 0.5
    // Mask role (layer masks): when true on a shape inside a
    // group, it clips siblings above it in the same group and never
    // paints itself. maskFeather softens the edge (content px),
    // maskInverted flips the alpha, maskMode reserves luminance.
    property bool isMask: false
    property string maskMode: "alpha"
    property real maskFeather: 0
    property bool maskInverted: false
    // Canvas paint order, assigned by Document.renumberZ (top-first DFS).
    property int zOrder: 0

    // Common state.
    property bool visible: true
    property bool locked: false
    property bool selected: false
    property bool renaming: false
    // Groups only: layers collapse (no canvas effect).
    property bool expanded: true
    // Live boolean op for groups ("none" = plain group). When set to
    // union|subtract|intersect|exclude the group paints one combined
    // silhouette (see ShapePath) with the group's own fills/strokes/
    // effects, while children stay editable via drill-in. Plain groups
    // keep empty stacks and never paint.
    property string boolOp: "none"

    // Group children (array of DocNode, top-first). Empty for shapes.
    property var children: []
}
