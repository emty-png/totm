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
    property color fill: "#d9d9d9"
    property string fillType: "solid"
    property var fillGradient: null
    property color strokeColor: "#000000"
    property string strokeType: "solid"
    property var strokeGradient: null
    property real strokeWidth: 0
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

    // CPU paint path for effects the stock items cannot express
    // (ShapePath has fillGradient only, Rectangle borders stay solid,
    // MultiEffect has no spread). Vectors stack shadows and glows here;
    // text and images stack glows in their native branches (shadows
    // stay vector-only, like export).
    readonly property bool isVectorPaint: shape.shapeType === "rectangle" || shape.shapeType === "ellipse" || shape.shapeType === "triangle" || shape.shapeType === "star" || shape.shapeType === "pen"
    readonly property var enabledShadows: (shape.shadows || []).filter(s => s && s.enabled !== false)
    readonly property bool hasShadow: shape.enabledShadows.length > 0
    readonly property bool hasLayerBlur: shape.layerBlur !== null && shape.layerBlur !== undefined && shape.layerBlur.enabled === true && Number(shape.layerBlur.radius) > 0
    readonly property bool hasBackgroundBlur: shape.backgroundBlur !== null && shape.backgroundBlur !== undefined && shape.backgroundBlur.enabled === true && Number(shape.backgroundBlur.radius) > 0 && shape.shapeType !== "text"
    readonly property var enabledGlows: (shape.glows || []).filter(g => g && g.enabled !== false)
    // Inner has no glyph path: text renders every glow outer (same
    // rule as the video exporter, so preview matches export).
    readonly property var outerGlows: shape.shapeType === "text" ? shape.enabledGlows : shape.enabledGlows.filter(g => g.inner !== true)
    readonly property var innerGlows: shape.shapeType === "text" ? [] : shape.enabledGlows.filter(g => g.inner === true)
    readonly property bool hasGlow: shape.enabledGlows.length > 0
    readonly property bool hasGrain: shape.grain !== null && shape.grain !== undefined && shape.grain.enabled === true && Number((shape.grain ?? {}).amount || 0) > 0
    readonly property bool textGlowOuter: shape.hasGlow && shape.shapeType === "text"
    readonly property bool useEffectPaint: shape.isVectorPaint && (shape.fillType === "linear" || shape.strokeType === "linear" || shape.hasShadow || shape.hasLayerBlur || shape.hasGlow)

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
    Rectangle {
        anchors.fill: parent
        visible: shape.shapeType === "rectangle" && !shape.independentCorners && !shape.useEffectPaint
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
        visible: shape.useEffectPaint
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
        fill: shape.fill
        fillType: shape.fillType
        fillGradient: shape.fillGradient ?? ({
                "angle": 90,
                "stops": [
                    {
                        "color": "#000000",
                        "pos": 0
                    },
                    {
                        "color": "#ffffff",
                        "pos": 1
                    }
                ]
            })
        stroke: shape.strokeColor
        strokeType: shape.strokeType
        strokeGradient: shape.strokeGradient ?? ({
                "angle": 90,
                "stops": [
                    {
                        "color": "#000000",
                        "pos": 0
                    },
                    {
                        "color": "#ffffff",
                        "pos": 1
                    }
                ]
            })
        strokeWidth: shape.strokeWidth
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
        visible: shape.hasBackgroundBlur && shape.backdropItem !== null && !shape.isBackdropCapture
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
                blur: Math.min(1, Math.max(0, Number((shape.backgroundBlur ?? {}).radius || 0) * shape.zoom / 64))
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
        visible: ((shape.shapeType !== "rectangle" && shape.shapeType !== "text" && shape.shapeType !== "image") || (shape.shapeType === "rectangle" && shape.independentCorners)) && !shape.useEffectPaint
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
                path: shape.geometry.vectorPath(shape)
            }
        }
    }

    // Text: fill paints the glyphs; stroke is a native 1px outline
    // (Text has no outline-width API, so the width field only toggles
    // it on/off for text). Each glow rides a zero-offset GPU shadow
    // (glyph-shaped halo like export's ghost pass); inner stays outer
    // for text everywhere, so there is no silent fallback to chase.
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

        // Stacked outer glows behind the fill, bottom-first so index 0
        // paints topmost (closest to the glyphs).
        Repeater {
            model: shape.textGlowOuter ? shape.outerGlows.slice().reverse() : []

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: String((modelData ?? {}).color ?? "#cc00ffff")
                    shadowOpacity: 1
                    shadowBlur: Math.min(1, Math.max(0, Number((modelData ?? {}).blur || 0) * shape.zoom / 64))
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    blurMax: 64
                }

                // Spread dilates glyphs like the exporter's stamp pass.
                TextGlyphs {
                    anchors.fill: parent
                    visible: Number((modelData ?? {}).spread || 0) > 0
                    text: shape.textContent
                    color: String((modelData ?? {}).color ?? "#cc00ffff")
                    family: shape.fontFamily
                    weight: shape.fontWeight
                    size: shape.fontSize
                    spacingPct: shape.letterSpacing
                    halign: shape.hAlign
                    valign: shape.vAlign
                    wrap: !shape.autoSize
                    autoLeading: shape.lineHeightAuto
                    leading: shape.lineHeight
                    transform: Scale {
                        xScale: (shape.sw + 2 * Number((modelData ?? {}).spread || 0)) / Math.max(1, shape.sw)
                        yScale: (shape.sh + 2 * Number((modelData ?? {}).spread || 0)) / Math.max(1, shape.sh)
                        origin.x: shape.sw / 2
                        origin.y: shape.sh / 2
                    }
                }

                TextGlyphs {
                    anchors.fill: parent
                    text: shape.textContent
                    color: String((modelData ?? {}).color ?? "#cc00ffff")
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

    // Film grain confined to the glyphs: a white ghost copy masks the
    // tile (no outline, like the export ghost). Hidden while editing.
    GrainOverlay {
        anchors.fill: parent
        visible: shape.hasGrain && shape.shapeType === "text" && !shape.editing
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
        visible: shape.shapeType === "image"
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
                    blur: Math.min(1, Math.max(0, Number((modelData ?? {}).blur || 0) * shape.zoom / 64))
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
                            blur: Math.min(1, Math.max(0, Number((modelData ?? {}).blur || 0) * shape.zoom / 64))
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Math.max(0, shape.radius)
            color: "transparent"
            border.width: shape.strokeWidth
            border.color: shape.strokeWidth > 0 ? shape.strokeColor : "transparent"
        }
    }

    // Animated film grain over vectors and images (text confines to its
    // glyphs just below). Seed reseeds every transport frame; amount
    // scales dot alpha like the exporter.
    GrainOverlay {
        anchors.fill: parent
        visible: shape.hasGrain && shape.shapeType !== "text"
        opacity: shape.shapeOpacity
        uid: shape.uid
        frameNo: shape.grainFrame
        amount: Number((shape.grain ?? {}).amount ?? 0.5)
        grainSize: Number((shape.grain ?? {}).size ?? 2)
        maskKind: (shape.shapeType === "rectangle" && !shape.independentCorners) || shape.shapeType === "image" ? "rect" : "path"
        maskRadius: shape.radius
        maskPath: shape.geometry.vectorPath(shape)
        maskStroke: shape.strokeWidth
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
