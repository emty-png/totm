import QtQuick
import QtQuick.Effects
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
    // Injected names stay undeclared: `required` breaks sibling
    // initializer bindings at runtime.
    // Paint follows the sidebar order via depth (renumbered by the
    // document after every reorder); uid order must never drive paint.
    property int uid: -1
    property string shapeType: "rectangle"
    property real sx: 0
    property real sy: 0
    property real sw: 10
    property real sh: 10
    property real shapeRotation: 0
    // Stacked paints (Figma-style, index 0 paints topmost). Each fill:
    // {enabled, color, type, gradient, opacity}; each stroke: {enabled,
    // color, type, gradient, width, dash, position, opacity}. Bound
    // from model roles by the repeater (see ShapeLayer).
    property var fills: []
    property var strokes: []
    // Pen-only paint switches (meaningful for pen): fill on/off plus
    // line cap/join. Defaults match the old hardcoded paint (filled,
    // round caps/joins), so every other shape renders identically.
    property bool penFill: true
    property string strokeCap: "round"
    property string strokeJoin: "round"
    property var shadows: []
    property var layerBlur: null
    property var backgroundBlur: null
    property var glows: []
    property var grain: null
    property var backdropItem: null
    // Frame number for animated grain (floor(seconds * 60), shared with
    // the exporter so the shimmer matches; static while paused).
    property int grainFrame: 0
    // True inside the hidden backdrop duplicate: blurred shapes hide
    // so frosted panels sample only content behind them.
    property bool isBackdropCapture: false
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
    // Stored blob name under LibraryStore images/ (meaningful when
    // shapeType === "image"). Stretch fills the box per tool choice.
    property string imageSource: ""
    // True while the canvas inline editor owns this text: the static
    // glyphs hide so they never double-draw under the editor.
    property bool editing: false
    property bool selected: false
    property bool shapeVisible: true
    property bool shapeLocked: false
    property int paintDepth: 0
    property real zoom: 1
    // Mask role: never paints (export skips isMask leaves too), but
    // stays hit-testable so the shape remains selectable/editable.
    // Masked content hides its GPU paint the same way and lands on
    // the CPU MaskLeafItem instead, so preview matches export.
    property bool isMaskShape: false
    property bool isMaskedContent: false
    readonly property bool paintHidden: shape.isMaskShape === true || shape.isMaskedContent === true
    // False for non-interactive paint reuse (drag-preview ghost): the
    // MouseArea below goes blind so canvas gestures pass through.
    property bool interactive: true

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

    // Vector path builders (pure geometry, mirrored by the C++ video
    // renderer).
    readonly property var geometry: ShapeGeometry {}

    // Pen line ends/bends. Other shapes keep the historic round paint;
    // unknown values fall back to round on both renderers.
    function capFor() {
        if (shape.shapeType !== "pen")
            return ShapePath.RoundCap;
        if (shape.strokeCap === "square")
            return ShapePath.SquareCap;
        if (shape.strokeCap === "flat")
            return ShapePath.FlatCap;
        return ShapePath.RoundCap;
    }

    function joinFor() {
        if (shape.shapeType !== "pen")
            return ShapePath.RoundJoin;
        if (shape.strokeJoin === "bevel")
            return ShapePath.BevelJoin;
        if (shape.strokeJoin === "miter")
            return ShapePath.MiterJoin;
        return ShapePath.RoundJoin;
    }

    // CPU paint path for effects the stock items cannot express
    // (ShapePath has fillGradient only, Rectangle borders stay solid
    // and dashless, MultiEffect has no spread). Vectors stack shadows
    // and glows here; text and images stack glows in their native
    // branches (shadows stay vector-only, like export).
    readonly property bool isVectorPaint: shape.shapeType === "rectangle" || shape.shapeType === "ellipse" || shape.shapeType === "triangle" || shape.shapeType === "star" || shape.shapeType === "pen"
    readonly property var enabledFills: (shape.fills || []).filter(f => f && f.enabled !== false)
    readonly property var enabledStrokes: (shape.strokes || []).filter(s => s && s.enabled !== false && Number(s.width) > 0)
    // First enabled entries drive the fast GPU branches and text.
    readonly property var firstFill: shape.enabledFills.length > 0 ? shape.enabledFills[0] : null
    readonly property var firstStroke: shape.enabledStrokes.length > 0 ? shape.enabledStrokes[0] : null
    readonly property color firstFillColor: shape.firstFill ? shape.firstFill.color : "transparent"
    readonly property color firstStrokeColor: shape.firstStroke ? shape.firstStroke.color : "transparent"
    readonly property real maxStrokeWidth: {
        var w = 0;
        for (var i = 0; i < shape.enabledStrokes.length; i++)
            w = Math.max(w, Number(shape.enabledStrokes[i].width) || 0);
        return w;
    }
    readonly property bool hasLinearFill: shape.enabledFills.some(f => (f.type || "solid") === "linear")
    readonly property bool hasLinearStroke: shape.enabledStrokes.some(s => (s.type || "solid") === "linear")
    // Per-entry opacity below 1 routes through the CPU painter (which
    // folds color alpha * entry opacity exactly); fast branches keep
    // the historic raw-color paint.
    readonly property bool hasFillOpacity: shape.enabledFills.some(f => Number(f.opacity ?? 1) < 0.999)
    readonly property bool hasStrokeOpacity: shape.enabledStrokes.some(s => Number(s.opacity ?? 1) < 0.999)
    readonly property var enabledShadows: (shape.shadows || []).filter(s => s && s.enabled !== false)
    readonly property bool hasShadow: shape.enabledShadows.length > 0
    readonly property bool hasLayerBlur: shape.layerBlur !== null && shape.layerBlur !== undefined && shape.layerBlur.enabled === true && Number(shape.layerBlur.radius) > 0
    readonly property bool hasBackgroundBlur: shape.backgroundBlur !== null && shape.backgroundBlur !== undefined && shape.backgroundBlur.enabled === true && Number(shape.backgroundBlur.radius) > 0 && shape.shapeType !== "text"
    readonly property var enabledGlows: (shape.glows || []).filter(g => g && g.enabled !== false)
    readonly property var outerGlows: shape.enabledGlows.filter(g => g.inner !== true)
    readonly property var innerGlows: shape.enabledGlows.filter(g => g.inner === true)
    readonly property bool hasGlow: shape.enabledGlows.length > 0
    readonly property bool hasGrain: shape.grain !== null && shape.grain !== undefined && shape.grain.enabled === true && Number((shape.grain ?? {}).amount || 0) > 0
    // Dashed strokes route through the CPU painter too: stock borders
    // and ShapePaths cannot dash. Both entries must be positive,
    // mirroring the backend rule, so half-cleared pairs stay solid.
    readonly property bool hasStrokeDash: {
        for (var i = 0; i < shape.enabledStrokes.length; i++) {
            var d = shape.enabledStrokes[i].dash;
            if (!d || typeof d.length !== "number" || d.length < 2)
                continue;
            if (Number(d[0]) > 0 && Number(d[1]) > 0)
                return true;
        }
        return false;
    }
    // Non-center strokes need the CPU clipper (inside/outside); the
    // native border straddles (Shape) or sits inside (Rectangle).
    readonly property bool hasNonCenterStroke: shape.enabledStrokes.some(s => (s.position || "center") !== "center")
    // Native Rectangle borders paint inside, so the fast branch only
    // holds for solid inside strokes (or no stroke); everything else
    // rides the shared CPU painter like export.
    readonly property bool rectFastStroke: shape.enabledStrokes.length === 0 || (shape.enabledStrokes.length === 1 && (shape.firstStroke.type || "solid") !== "linear" && (shape.firstStroke.position || "center") === "inside" && !shape.hasStrokeDash)
    readonly property bool useEffectPaint: shape.isVectorPaint && (shape.enabledFills.length > 1 || shape.hasLinearFill || shape.hasFillOpacity || shape.enabledStrokes.length > 1 || shape.hasLinearStroke || shape.hasStrokeOpacity || shape.hasStrokeDash || shape.hasNonCenterStroke || (shape.shapeType === "rectangle" && !shape.independentCorners && !shape.rectFastStroke && shape.enabledStrokes.length > 0) || shape.hasShadow || shape.hasLayerBlur || shape.hasGlow)
    // Effected text paints the glyph stack on the CPU (same code export
    // calls); plain text stays on the fast GPU glyphs. Grain rides its
    // own overlay either way; background blur stays off for text.
    readonly property bool useTextEffectPaint: shape.shapeType === "text" && (shape.enabledFills.length > 1 || shape.hasLinearFill || shape.hasFillOpacity || shape.enabledStrokes.length > 1 || shape.hasStrokeOpacity || shape.hasShadow || shape.hasGlow || shape.hasLayerBlur)

    x: shape.sx
    y: shape.sy
    width: shape.sw
    height: shape.sh
    z: shape.paintDepth
    rotation: shape.shapeRotation
    transformOrigin: Item.Center
    visible: shape.shapeVisible && !(shape.isBackdropCapture && shape.hasBackgroundBlur)

    // Rectangle: native item (radius + stroke border built in).
    // Flip mirrors paint about the center in local space, under the
    // root rotation; geometry, outline and hit area keep the bbox.
    // Fast only for solid inside strokes (native borders paint
    // inside); center/outside/gradient/dashed stacks ride EffectItem.
    Rectangle {
        anchors.fill: parent
        visible: shape.shapeType === "rectangle" && !shape.independentCorners && !shape.useEffectPaint && !shape.paintHidden
        color: shape.firstFill ? shape.firstFillColor : "transparent"
        radius: shape.radius
        border.width: shape.firstStroke && shape.rectFastStroke ? Number(shape.firstStroke.width) || 0 : 0
        border.color: shape.firstStroke && shape.rectFastStroke && Number(shape.firstStroke.width) > 0 ? shape.firstStrokeColor : "transparent"
        opacity: shape.shapeOpacity
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: shape.sw / 2
            origin.y: shape.sh / 2
        }
    }

    // Effected vectors via the shared CPU painter (same code export
    // will call, so preview matches video). The item pads itself by
    // shadow spread/blur/offset so nothing clips; the shape paints at
    // (pad,pad). Flip mirrors about the shape center like above.
    EffectItem {
        id: effectPaint

        x: -effectPaint.pad
        y: -effectPaint.pad
        width: shape.sw + effectPaint.pad * 2
        height: shape.sh + effectPaint.pad * 2
        visible: shape.useEffectPaint && !shape.paintHidden
        opacity: shape.shapeOpacity
        shapeType: shape.shapeType
        boxW: shape.sw
        boxH: shape.sh
        radius: shape.radius
        independentCorners: shape.independentCorners
        cornerRadii: shape.cornerRadii
        points: shape.points
        pathData: shape.pathData
        // Node origin feeds pen paths only (absolute coords resolve
        // against it); other kinds ignore it in paint, so moves skip
        // the CPU repaint entirely and ride the parent transform.
        nodeX: shape.shapeType === "pen" ? shape.sx : 0
        nodeY: shape.shapeType === "pen" ? shape.sy : 0
        fills: shape.fills ?? []
        strokes: shape.strokes ?? []
        penFill: shape.penFill !== false
        strokeCap: shape.strokeCap || "round"
        strokeJoin: shape.strokeJoin || "round"
        shadows: shape.shadows ?? []
        glows: shape.glows ?? []
        layerBlur: shape.layerBlur ?? ({
                "enabled": false,
                "radius": 0,
                "opacity": 1
            })
        backgroundBlur: shape.backgroundBlur ?? ({
                "enabled": false,
                "radius": 0,
                "opacity": 0.7
            })
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: effectPaint.pad + shape.sw / 2
            origin.y: effectPaint.pad + shape.sh / 2
        }
    }

    // Background blur (frosted glass): a scene-sized rig samples the
    // backdrop sibling layer directly and blurs it, clipped to this
    // shape's bbox; a silhouette mask applies only where corners or
    // curves actually cut (plain sharp rects need none). The live scene
    // underneath supplies the sharp half of the opacity mix, so one
    // tile suffices. Export repeats the same values on the CPU. Only
    // visible with a translucent fill over content behind the shape.
    Item {
        id: backdropRoot

        anchors.fill: parent
        z: -1
        visible: shape.hasBackgroundBlur && shape.backdropItem !== null && !shape.isBackdropCapture && !shape.paintHidden
        clip: true
        // Leaf opacity applies to the fill above, never the backdrop
        // (matches the exporter, which resets opacity for the tile).
        opacity: 1

        readonly property real sceneW: shape.backdropItem && shape.backdropItem.doc ? Number(shape.backdropItem.doc.sceneWidth) || 1920 : 1920
        readonly property real sceneH: shape.backdropItem && shape.backdropItem.doc ? Number(shape.backdropItem.doc.sceneHeight) || 1080 : 1080
        readonly property bool plainRect: shape.shapeType === "rectangle" && !shape.independentCorners
        readonly property bool needsMask: !((backdropRoot.plainRect || shape.shapeType === "image") && !(Number(shape.radius) > 0))

        // Scene-sized rig, offset so scene coords register under the shape.
        Item {
            id: blurRig

            x: -shape.sx
            y: -shape.sy
            width: backdropRoot.sceneW
            height: backdropRoot.sceneH

            MultiEffect {
                anchors.fill: parent
                source: shape.backdropItem
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                // Content-space radius: the scaled ancestor already maps
                // local px to screen px, so no zoom factor here (it would
                // grow screen blur as zoom-squared and pin blur at 1.0
                // deep in, stalling weak GPUs on scene-sized tiles).
                blur: Math.min(1, Math.max(0, Number((shape.backgroundBlur ?? {}).radius || 0) / 64))
                opacity: Math.min(1, Math.max(0, Number((shape.backgroundBlur ?? {}).opacity ?? 0.7)))
                maskEnabled: backdropRoot.needsMask
                maskSource: rigMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            // White silhouette at the shape position (mask space is the
            // rig). Mirrors the fill flip so asymmetric paths register.
            Item {
                id: rigMask

                anchors.fill: parent
                visible: false
                layer.enabled: true
                layer.smooth: true

                Item {
                    x: shape.sx
                    y: shape.sy
                    width: Math.max(1, shape.sw)
                    height: Math.max(1, shape.sh)

                    transform: Scale {
                        xScale: shape.flipH ? -1 : 1
                        yScale: shape.flipV ? -1 : 1
                        origin.x: shape.sw / 2
                        origin.y: shape.sh / 2
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: backdropRoot.plainRect || shape.shapeType === "image"
                        radius: shape.shapeType === "image" ? Math.max(0, shape.radius) : Math.min(shape.radius, Math.min(shape.sw, shape.sh) / 2)
                        color: "white"
                    }

                    Shape {
                        anchors.fill: parent
                        visible: !(backdropRoot.plainRect || shape.shapeType === "image" || shape.shapeType === "text")
                        antialiasing: true
                        ShapePath {
                            fillColor: "white"
                            strokeColor: "transparent"
                            PathSvg {
                                path: shape.geometry.vectorPath(shape)
                            }
                        }
                    }
                }
            }
        }
    }

    // Other types: stroked/filled vector path with round joins.
    // Independent rectangles join them so every corner keeps its own cut.
    // Images paint separately below, so they never reach the vector path.
    Shape {
        anchors.fill: parent
        visible: (((shape.shapeType !== "rectangle" && shape.shapeType !== "text" && shape.shapeType !== "image") || (shape.shapeType === "rectangle" && shape.independentCorners)) && !shape.useEffectPaint) && !shape.paintHidden
        antialiasing: true
        opacity: shape.shapeOpacity
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: shape.sw / 2
            origin.y: shape.sh / 2
        }
        ShapePath {
            fillColor: shape.shapeType === "pen" && shape.penFill !== true ? "transparent" : (shape.firstFill ? shape.firstFillColor : "transparent")
            strokeColor: shape.firstStroke ? shape.firstStrokeColor : "transparent"
            strokeWidth: shape.firstStroke ? Number(shape.firstStroke.width) || 0 : 0
            joinStyle: shape.joinFor()
            capStyle: shape.capFor()
            PathSvg {
                path: shape.geometry.vectorPath(shape)
            }
        }
    }

    // Text: plain glyphs paint on the GPU (fill plus a native 1px
    // outline toggle); effected glyphs paint the full CPU stack
    // (outer/inner shadows and glows, gradient fill, outline ring,
    // whole-stack layer blur) through the shared painter export calls.
    Item {
        id: textRoot

        anchors.fill: parent
        visible: shape.shapeType === "text" && !shape.editing && !shape.paintHidden
        opacity: shape.shapeOpacity
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: shape.sw / 2
            origin.y: shape.sh / 2
        }

        EffectItem {
            id: effectText

            x: -effectText.pad
            y: -effectText.pad
            width: shape.sw + effectText.pad * 2
            height: shape.sh + effectText.pad * 2
            visible: shape.useTextEffectPaint
            opacity: 1
            shapeType: "text"
            boxW: shape.sw
            boxH: shape.sh
            fills: shape.fills ?? []
            strokes: shape.strokes ?? []
            shadows: shape.shadows ?? []
            glows: shape.glows ?? []
            layerBlur: shape.layerBlur ?? ({
                    "enabled": false,
                    "radius": 0,
                    "opacity": 1
                })
            textStyle: ({
                    "content": shape.textContent,
                    "family": shape.fontFamily,
                    "weight": shape.fontWeight,
                    "size": shape.fontSize,
                    "spacing": shape.letterSpacing,
                    "halign": shape.hAlign,
                    "valign": shape.vAlign,
                    "autoSize": shape.autoSize,
                    "lineAuto": shape.lineHeightAuto,
                    "leading": shape.lineHeight,
                    "boxW": shape.sw,
                    "boxH": shape.sh,
                    "outlinePx": shape.maxStrokeWidth
                })
            transform: Scale {
                xScale: shape.flipH ? -1 : 1
                yScale: shape.flipV ? -1 : 1
                origin.x: effectText.pad + shape.sw / 2
                origin.y: effectText.pad + shape.sh / 2
            }
        }

        TextGlyphs {
            id: glyphs

            anchors.fill: parent
            visible: !shape.useTextEffectPaint
            text: shape.textContent
            color: shape.firstFill ? shape.firstFillColor : "transparent"
            style: shape.firstStroke ? Text.Outline : Text.Normal
            styleColor: shape.firstStroke ? shape.firstStrokeColor : "#000000"
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

    // Film grain confined to the glyphs: a white ghost copy masks the
    // tile (no outline, like the export ghost). Hidden while editing.
    GrainOverlay {
        anchors.fill: parent
        visible: shape.hasGrain && shape.shapeType === "text" && !shape.editing && !shape.paintHidden
        opacity: shape.shapeOpacity
        uid: shape.uid
        frameNo: shape.grainFrame
        amount: Number((shape.grain ?? {}).amount ?? 0.5)
        grainSize: Number((shape.grain ?? {}).size ?? 2)
        maskKind: "custom"
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: shape.sw / 2
            origin.y: shape.sh / 2
        }

        TextGlyphs {
            anchors.fill: parent
            text: shape.textContent
            color: "white"
            family: shape.fontFamily
            weight: shape.fontWeight
            size: shape.fontSize
            spacingPct: shape.letterSpacing
            halign: shape.hAlign
            valign: shape.vAlign
            wrap: !shape.autoSize
            autoLeading: shape.lineHeightAuto
            leading: shape.lineHeight
        }
    }

    // Image: stretched blob with uniform radius mask plus an optional
    // stroke border. Rectangle clip stays rectangular, so rounding goes
    // through a MultiEffect mask (smooth edges via threshold/spread).
    // Missing blobs show a neutral tile so broken imports never vanish.
    Item {
        id: imageRoot

        anchors.fill: parent
        visible: shape.shapeType === "image" && !shape.paintHidden
        opacity: shape.shapeOpacity
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: shape.sw / 2
            origin.y: shape.sh / 2
        }

        Rectangle {
            anchors.fill: parent
            radius: Math.max(0, shape.radius)
            color: AppTheme.surface
            visible: imageObj.status !== Image.Ready
        }

        AppIcon {
            anchors.centerIn: parent
            kind: "image"
            iconColor: AppTheme.muted
            visible: shape.shapeType === "image" && imageObj.status !== Image.Ready
        }

        // Outer glows: grown silhouettes in glow colors, blurred behind
        // the pixels (spread grows the rect like the stroker dilate).
        // Bottom-first so index 0 paints topmost.
        Repeater {
            model: shape.shapeType === "image" ? shape.outerGlows.slice().reverse() : []

            Rectangle {
                anchors.fill: parent
                anchors.margins: -Number((modelData ?? {}).spread || 0)
                radius: Math.max(0, shape.radius) + Number((modelData ?? {}).spread || 0)
                color: String((modelData ?? {}).color ?? "#cc00ffff")
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 64
                    // Same content-space rule as the backdrop rig above:
                    // no zoom factor (ancestor scale already applies it).
                    blur: Math.min(1, Math.max(0, Number((modelData ?? {}).blur || 0) / 64))
                }
            }
        }

        Image {
            id: imageObj

            anchors.fill: parent
            source: shape.imageSource ? LibraryStore.imageUrl(shape.imageSource) : ""
            fillMode: Image.Stretch
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
            visible: status === Image.Ready
            layer.enabled: status === Image.Ready && (shape.radius > 0 || shape.hasLayerBlur)
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: shape.radius > 0
                maskSource: maskRect
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                blurEnabled: shape.hasLayerBlur
                blurMax: 64
                blur: shape.hasLayerBlur ? Math.min(1, Math.max(0, Number((shape.layerBlur ?? {}).radius || 0) / 64)) : 0
            }
            // Opacity mix for layer blur: sharp base stays, blurred copy
            // fades over it (export mixes the same values on the CPU).
            opacity: shape.hasLayerBlur ? 1 - Number((shape.layerBlur ?? {}).opacity ?? 1) : 1
        }

        Image {
            anchors.fill: parent
            visible: imageObj.status === Image.Ready && shape.hasLayerBlur
            source: imageObj.source
            fillMode: Image.Stretch
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
            opacity: Number((shape.layerBlur ?? {}).opacity ?? 1)
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: shape.radius > 0
                maskSource: maskRect
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                blurEnabled: true
                blurMax: 64
                blur: Math.min(1, Math.max(0, Number((shape.layerBlur ?? {}).radius || 0) / 64))
            }
        }

        Rectangle {
            id: maskRect

            anchors.fill: parent
            radius: Math.max(0, shape.radius)
            color: "white"
            visible: false
            layer.enabled: true
            layer.smooth: true
        }

        // Inner glows: glow washes over the pixels, each cut by its own
        // blurred inset silhouette (inverted mask) into an edge band.
        Repeater {
            model: shape.shapeType === "image" ? shape.innerGlows.slice().reverse() : []

            Item {
                anchors.fill: parent

                Rectangle {
                    anchors.fill: parent
                    radius: Math.max(0, shape.radius)
                    color: String((modelData ?? {}).color ?? "#cc00ffff")
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: erode
                        maskInverted: true
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }

                Item {
                    id: erode

                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    layer.smooth: true

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Number((modelData ?? {}).spread || 0)
                        radius: Math.max(0, Math.max(0, shape.radius) - Number((modelData ?? {}).spread || 0))
                        color: "white"
                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blurMax: 64
                            // Content-space radius, no zoom factor (see above).
                            blur: Math.min(1, Math.max(0, Number((modelData ?? {}).blur || 0) / 64))
                        }
                    }
                }
            }
        }

        // Stacked strokes as borders, bottom-first so index 0 paints
        // topmost. Inside rides the clip edge (native border), center
        // straddles it, outside grows past it. Gradient strokes fall
        // back to their first stop in v1; entry opacity rides the item.
        Repeater {
            model: shape.shapeType === "image" ? shape.enabledStrokes.slice().reverse() : []

            Rectangle {
                anchors.fill: parent
                anchors.margins: {
                    var pos = (modelData ?? {}).position || "center";
                    var w = Number((modelData ?? {}).width) || 0;
                    if (pos === "outside")
                        return -w;
                    if (pos === "center")
                        return -w / 2;
                    return 0;
                }
                radius: Math.max(0, shape.radius) + Math.max(0, -anchors.margins)
                color: "transparent"
                opacity: Math.min(1, Math.max(0, Number((modelData ?? {}).opacity ?? 1)))
                border.width: Number((modelData ?? {}).width) || 0
                border.color: String((modelData ?? {}).color ?? "#000000")
            }
        }
    }

    // Animated film grain over vectors and images (text confines to its
    // glyphs just below). Seed reseeds every transport frame; amount
    // scales dot alpha like the exporter.
    GrainOverlay {
        anchors.fill: parent
        visible: shape.hasGrain && shape.shapeType !== "text" && !shape.paintHidden
        opacity: shape.shapeOpacity
        uid: shape.uid
        frameNo: shape.grainFrame
        amount: Number((shape.grain ?? {}).amount ?? 0.5)
        grainSize: Number((shape.grain ?? {}).size ?? 2)
        maskKind: (shape.shapeType === "rectangle" && !shape.independentCorners) || shape.shapeType === "image" ? "rect" : "path"
        maskRadius: shape.radius
        maskPath: shape.geometry.vectorPath(shape)
        maskStroke: shape.maxStrokeWidth
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: shape.sw / 2
            origin.y: shape.sh / 2
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
        enabled: shape.interactive
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
