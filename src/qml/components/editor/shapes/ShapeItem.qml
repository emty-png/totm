import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtMultimedia
import Totm

// One canvas shape; root geometry IS the shape geometry. Reports
// press/move/release; the canvas owns selection policy. Hidden shapes
// vanish (no input); locked ones swallow presses so the marquee below
// never starts. Drag deltas run in window-stable global coords at whole
// screen pixels (local coords would judder as the item moves under the
// cursor); the document snaps to whole pixels on release.
Item {
    id: shape

    // Model-bound props set from roles (undeclared injected names:
    // `required` breaks sibling initializer bindings). Paint follows
    // sidebar order via depth, never uid order.
    property int uid: -1
    property string shapeType: "rectangle"
    property real sx: 0
    property real sy: 0
    property real sw: 10
    property real sh: 10
    property real shapeRotation: 0
    // Stacked paints, index 0 topmost (see ShapeLayer for role binding).
    property var fills: []
    property var strokes: []
    // Pen-only switches; defaults match the old hardcoded round paint.
    property bool penFill: true
    property string strokeCap: "round"
    property string strokeJoin: "round"
    property var shadows: []
    property var layerBlur: null
    property var backgroundBlur: null
    property var glows: []
    property var grain: null
    property var backdropItem: null
    // Animated-grain frame (floor(seconds * 60), shared with export).
    property int grainFrame: 0
    // True in the hidden backdrop duplicate (blurred shapes hide so
    // frosted panels sample only content behind them).
    property bool isBackdropCapture: false
    property real shapeOpacity: 1
    property real radius: 0
    property bool independentCorners: false
    property var cornerRadii: []
    property bool flipH: false
    property bool flipV: false
    // Star tips (document clamps 3..12 on edit).
    property int points: 5
    // Pen subpaths in absolute content coords.
    property var pathData: []
    // Text style (letterSpacing is percent of font size).
    property string textContent: ""
    property string fontFamily: "Inter"
    property int fontWeight: 400
    property real fontSize: 16
    property bool fontItalic: false
    property bool fontUnderline: false
    property bool fontStrike: false
    property string fontCaps: "none"
    property var textRuns: []
    property bool lineHeightAuto: true
    property real lineHeight: 1.2
    property real letterSpacing: 0
    property string hAlign: "left"
    property string vAlign: "top"
    property bool autoSize: true
    property var textFx: null
    // Stored blob name under LibraryStore images/.
    property string imageSource: ""
    // Stored blob name under LibraryStore videos/ (legacy absolute paths
    // still resolve). Empty means missing; preview shows a placeholder,
    // export paints a dark tile.
    property string videoSource: ""
    property real videoDuration: 0
    property real videoOffset: 0
    property bool videoMuted: false
    property real videoVolume: 1
    property real playbackRate: 1
    property bool videoLoop: true
    property string videoFit: "fit"
    // Timeline start in composition seconds (hidden before it).
    property real videoStart: 0
    // Transient footage-time override from Video time clips (-1 = off).
    // Written by the sampler during preview, reset on seeks/wraps.
    property real videoTime: -1
    // Composition clock for preview sync (from ShapeLayer): paused seeks
    // to the export frame, playing re-anchors past ~5 frames of drift.
    property real previewTime: 0
    property bool previewPlaying: false
    // True while the inline editor owns this text (glyphs hide to avoid
    // double-draw).
    property bool editing: false
    property bool selected: false
    property bool shapeVisible: true
    property bool shapeLocked: false
    property int paintDepth: 0
    property real zoom: 1
    // Masks never paint but stay hit-testable; masked content lands on
    // the CPU MaskLeafItem so preview matches export.
    property bool isMaskShape: false
    property bool isMaskedContent: false
    // Boolean children never paint individually (the combined delegate
    // paints them) but stay hit-testable so press/drag/drill resolve
    // to the boolean group like any other group.
    property bool isBooleanChild: false
    readonly property bool paintHidden: shape.isMaskShape === true || shape.isMaskedContent === true || shape.isBooleanChild === true
    // False for non-interactive reuse (drag ghost): gestures pass through.
    property bool interactive: true

    // Selection policy callbacks from the canvas (plain assignments stay
    // dynamic where item.customSignal() would fail lint).
    property var activatePolicy: null
    property var pressPolicy: null
    property var movePolicy: null
    property var releasePolicy: null
    property var doublePolicy: null
    // Auto-size writeback for text: the canvas clamps and commits.
    property var measurePolicy: null

    // Vector path builders (pure geometry, mirrored by export).
    readonly property var geometry: ShapeGeometry {}

    // Pen caps/joins; other shapes keep round, unknown falls back to round.
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

    // CPU path for what stock items can't express (gradients, dashes,
    // spread, multi-entry stacks).
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
    // Sub-1 entry opacity folds through the CPU painter exactly.
    readonly property bool hasFillOpacity: shape.enabledFills.some(f => Number(f.opacity ?? 1) < 0.999)
    readonly property bool hasStrokeOpacity: shape.enabledStrokes.some(s => Number(s.opacity ?? 1) < 0.999)
    readonly property var enabledShadows: (shape.shadows || []).filter(s => s && s.enabled !== false)
    readonly property bool hasShadow: shape.enabledShadows.length > 0
    readonly property bool hasLayerBlur: shape.layerBlur !== null && shape.layerBlur !== undefined && shape.layerBlur.enabled === true && Number(shape.layerBlur.radius) > 0
    readonly property bool hasBackgroundBlur: shape.backgroundBlur !== null && shape.backgroundBlur !== undefined && shape.backgroundBlur.enabled === true && Number(shape.backgroundBlur.radius) > 0
    readonly property var enabledGlows: (shape.glows || []).filter(g => g && g.enabled !== false)
    readonly property var outerGlows: shape.enabledGlows.filter(g => g.inner !== true)
    readonly property var innerGlows: shape.enabledGlows.filter(g => g.inner === true)
    readonly property var outerShadows: shape.enabledShadows.filter(s => s.inner !== true)
    readonly property var innerShadows: shape.enabledShadows.filter(s => s.inner === true)
    readonly property bool hasGlow: shape.enabledGlows.length > 0
    readonly property bool hasGrain: shape.grain !== null && shape.grain !== undefined && shape.grain.enabled === true && Number((shape.grain ?? {}).amount || 0) > 0
    // Dashes need the CPU painter (stock borders can't); both entries
    // must be positive, mirroring the backend rule.
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
    // Non-center strokes need the CPU clipper (native borders straddle/sit inside).
    readonly property bool hasNonCenterStroke: shape.enabledStrokes.some(s => (s.position || "center") !== "center")
    // Native Rectangle borders paint inside: fast branch holds for solid
    // inside strokes (or none), everything else rides the CPU painter.
    readonly property bool rectFastStroke: shape.enabledStrokes.length === 0 || (shape.enabledStrokes.length === 1 && (shape.firstStroke.type || "solid") !== "linear" && (shape.firstStroke.position || "center") === "inside" && !shape.hasStrokeDash)
    readonly property bool useEffectPaint: shape.isVectorPaint && (shape.enabledFills.length > 1 || shape.hasLinearFill || shape.hasFillOpacity || shape.enabledStrokes.length > 1 || shape.hasLinearStroke || shape.hasStrokeOpacity || shape.hasStrokeDash || shape.hasNonCenterStroke || (shape.shapeType === "rectangle" && !shape.independentCorners && !shape.rectFastStroke && shape.enabledStrokes.length > 0) || shape.hasShadow || shape.hasLayerBlur || shape.hasGlow)
    // Effected text/images ride the shared CPU painter (matches export);
    // plain variants stay on the fast GPU branches. Any text stroke,
    // rich run or karaoke/sweep reveal rides the CPU vector path.
    readonly property bool hasTextRuns: shape.shapeType === "text" && !!(shape.textRuns && shape.textRuns.length)
    readonly property bool useTextEffectPaint: shape.shapeType === "text" && (shape.enabledFills.length > 1 || shape.hasLinearFill || shape.hasFillOpacity || shape.enabledStrokes.length > 0 || shape.hasLinearStroke || shape.hasStrokeOpacity || shape.hasStrokeDash || shape.hasNonCenterStroke || shape.hasShadow || shape.hasGlow || shape.hasLayerBlur || shape.hasTextRuns || !!(shape.textFx && shape.textFx.fx === true))
    readonly property bool useImageEffectPaint: shape.shapeType === "image" && (shape.hasShadow || shape.hasGlow || shape.hasLayerBlur || shape.hasStrokeDash)
    readonly property bool useVideoEffectPaint: shape.shapeType === "video" && (shape.hasShadow || shape.hasGlow || shape.hasLayerBlur || shape.hasStrokeDash)

    x: shape.sx
    y: shape.sy
    width: shape.sw
    height: shape.sh
    z: shape.paintDepth
    rotation: shape.shapeRotation
    transformOrigin: Item.Center
    visible: shape.shapeVisible && !(shape.isBackdropCapture && shape.hasBackgroundBlur)

    // Rectangle: native item. Flip mirrors about the center; fast only
    // for solid inside strokes (native borders paint inside).
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

    // Effected vectors via the shared CPU painter. Padded for spread/
    // blur/offset; the shape paints at (pad,pad).
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
        // Pen paths resolve against the node origin; other kinds ignore
        // it, so their moves skip the CPU repaint.
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

    // Frosted glass: scene-sized rig blurs the siblings behind, clipped
    // to the bbox (silhouette mask only where corners/curves cut). Needs
    // translucent fill over content; export repeats it on the CPU.
    Item {
        id: backdropRoot

        anchors.fill: parent
        z: -1
        visible: shape.hasBackgroundBlur && shape.backdropItem !== null && !shape.isBackdropCapture && !shape.paintHidden
        clip: true
        opacity: 1 // fill above carries opacity, never the backdrop

        readonly property real sceneW: shape.backdropItem && shape.backdropItem.doc ? Number(shape.backdropItem.doc.sceneWidth) || 1920 : 1920
        readonly property real sceneH: shape.backdropItem && shape.backdropItem.doc ? Number(shape.backdropItem.doc.sceneHeight) || 1080 : 1080
        readonly property bool plainRect: shape.shapeType === "rectangle" && !shape.independentCorners
        readonly property bool needsMask: !((backdropRoot.plainRect || shape.shapeType === "image" || shape.shapeType === "video") && !(Number(shape.radius) > 0))

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
                // local to screen px (no zoom factor: it would square with
                // zoom and stall weak GPUs on scene-sized tiles).
                blur: Math.min(1, Math.max(0, Number((shape.backgroundBlur ?? {}).radius || 0) / 64))
                opacity: Math.min(1, Math.max(0, Number((shape.backgroundBlur ?? {}).opacity ?? 0.7)))
                maskEnabled: backdropRoot.needsMask
                maskSource: rigMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            // White silhouette as the mask (mirrors fill flip).
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
                        visible: backdropRoot.plainRect || shape.shapeType === "image" || shape.shapeType === "video"
                        radius: (shape.shapeType === "image" || shape.shapeType === "video") ? Math.max(0, shape.radius) : Math.min(shape.radius, Math.min(shape.sw, shape.sh) / 2)
                        color: "white"
                    }

                    Shape {
                        anchors.fill: parent
                        visible: !(backdropRoot.plainRect || shape.shapeType === "image" || shape.shapeType === "video" || shape.shapeType === "text")
                        antialiasing: true
                        ShapePath {
                            fillColor: "white"
                            strokeColor: "transparent"
                            PathSvg {
                                path: shape.geometry.vectorPath(shape)
                            }
                        }
                    }

                    TextGlyphs {
                        anchors.fill: parent
                        visible: shape.shapeType === "text"
                        text: shape.textContent
                        color: "white"
                        family: shape.fontFamily
                        weight: shape.fontWeight
                        size: shape.fontSize
                        italic: shape.fontItalic === true
                        underline: shape.fontUnderline === true
                        strike: shape.fontStrike === true
                        caps: shape.fontCaps || "none"
                        spacingPct: shape.letterSpacing
                        halign: shape.hAlign
                        valign: shape.vAlign
                        wrap: !shape.autoSize
                        autoLeading: shape.lineHeightAuto
                        leading: shape.lineHeight
                    }
                }
            }
        }
    }

    // Stroked/filled vector path (images/videos paint below, never here).
    Shape {
        anchors.fill: parent
        visible: (((shape.shapeType !== "rectangle" && shape.shapeType !== "text" && shape.shapeType !== "image" && shape.shapeType !== "video") || (shape.shapeType === "rectangle" && shape.independentCorners)) && !shape.useEffectPaint) && !shape.paintHidden
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

    // Text: fast GPU glyphs, or the full CPU stack when effected.
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
                    "outlinePx": shape.maxStrokeWidth,
                    "italic": shape.fontItalic === true,
                    "underline": shape.fontUnderline === true,
                    "strike": shape.fontStrike === true,
                    "join": shape.strokeJoin || "round",
                    "caps": shape.fontCaps || "none",
                    "runs": shape.textRuns ?? [],
                    "fx": !!(shape.textFx && shape.textFx.fx === true),
                    "fxReveal": Number((shape.textFx ?? {}).fxReveal ?? 1),
                    "fxStagger": Number((shape.textFx ?? {}).fxStagger ?? 0),
                    "fxRise": Number((shape.textFx ?? {}).fxRise ?? 0),
                    "fxHighlight": String((shape.textFx ?? {}).fxHighlight ?? ""),
                    "fxSweep": (shape.textFx ?? {}).fxSweep === true,
                    "fxUnit": String((shape.textFx ?? {}).fxUnit ?? "letters")
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
            family: shape.fontFamily
            weight: shape.fontWeight
            size: shape.fontSize
            italic: shape.fontItalic === true
            underline: shape.fontUnderline === true
            strike: shape.fontStrike === true
            caps: shape.fontCaps || "none"
            spacingPct: shape.letterSpacing
            halign: shape.hAlign
            valign: shape.vAlign
            wrap: !shape.autoSize
            autoLeading: shape.lineHeightAuto
            leading: shape.lineHeight
            onContentSizeChanged: shape.reportMeasure()
        }
    }

    // Text grain masked to the glyphs (hidden while editing).
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
            italic: shape.fontItalic === true
            underline: shape.fontUnderline === true
            strike: shape.fontStrike === true
            caps: shape.fontCaps || "none"
            spacingPct: shape.letterSpacing
            halign: shape.hAlign
            valign: shape.vAlign
            wrap: !shape.autoSize
            autoLeading: shape.lineHeightAuto
            leading: shape.lineHeight
        }
    }

    // Image: stretched blob, rounding via MultiEffect mask (Rectangle
    // clip can't round); missing blobs show a neutral tile.
    Item {
        id: imageRoot

        anchors.fill: parent
        visible: shape.shapeType === "image" && !shape.paintHidden && !shape.useImageEffectPaint
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

        // Outer shadows/glows: grown, blurred silhouettes behind the
        // pixels, bottom-first (index 0 topmost). Shadows paint first.
        Repeater {
            model: shape.shapeType === "image" && !shape.useImageEffectPaint ? shape.outerShadows.slice().reverse() : []

            Rectangle {
                anchors.fill: parent
                anchors.margins: -Number((modelData ?? {}).spread || 0)
                radius: Math.max(0, shape.radius) + Number((modelData ?? {}).spread || 0)
                color: String((modelData ?? {}).color ?? "#80000000")
                transform: Translate {
                    x: Number((modelData ?? {}).x || 0)
                    y: Number((modelData ?? {}).y || 0)
                }
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 64
                    // Content-space radius (no zoom factor, as above).
                    blur: Math.min(1, Math.max(0, Number((modelData ?? {}).blur || 0) / 64))
                }
            }
        }

        Repeater {
            model: shape.shapeType === "image" && !shape.useImageEffectPaint ? shape.outerGlows.slice().reverse() : []

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
                    // Content-space radius (no zoom factor, as above).
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
            // Layer blur mixes sharp base with the blurred copy above.
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

        // Inner shadows/glows: washes cut by blurred inset silhouettes
        // into edge bands, below outer paint (stack order).
        Repeater {
            model: shape.shapeType === "image" && !shape.useImageEffectPaint ? shape.innerShadows.slice().reverse() : []

            Item {
                anchors.fill: parent

                Rectangle {
                    anchors.fill: parent
                    radius: Math.max(0, shape.radius)
                    color: String((modelData ?? {}).color ?? "#80000000")
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: erodeShadow
                        maskInverted: true
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }

                Item {
                    id: erodeShadow

                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    layer.smooth: true

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Number((modelData ?? {}).spread || 0)
                        radius: Math.max(0, Math.max(0, shape.radius) - Number((modelData ?? {}).spread || 0))
                        color: "white"
                        transform: Translate {
                            x: Number((modelData ?? {}).x || 0)
                            y: Number((modelData ?? {}).y || 0)
                        }
                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blurMax: 64
                            // Content-space radius (no zoom factor, as above).
                            blur: Math.min(1, Math.max(0, Number((modelData ?? {}).blur || 0) / 64))
                        }
                    }
                }
            }
        }

        Repeater {
            model: shape.shapeType === "image" && !shape.useImageEffectPaint ? shape.innerGlows.slice().reverse() : []

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
                            // Content-space radius (no zoom factor, as above).
                            blur: Math.min(1, Math.max(0, Number((modelData ?? {}).blur || 0) / 64))
                        }
                    }
                }
            }
        }

        // Stacked strokes, bottom-first; inside rides the edge, center
        // straddles, outside grows past. Gradients fall back to first stop.
        Repeater {
            model: shape.shapeType === "image" && !shape.useImageEffectPaint ? shape.enabledStrokes.slice().reverse() : []

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

    // Effected images via the shared CPU painter (pads like EffectItem).
    ImageEffectItem {
        id: imageEffectPaint

        x: -imageEffectPaint.pad
        y: -imageEffectPaint.pad
        width: shape.sw + imageEffectPaint.pad * 2
        height: shape.sh + imageEffectPaint.pad * 2
        visible: shape.useImageEffectPaint && !shape.paintHidden
        opacity: shape.shapeOpacity
        boxW: shape.sw
        boxH: shape.sh
        radius: shape.radius
        imageSource: shape.imageSource
        shadows: shape.shadows ?? []
        glows: shape.glows ?? []
        layerBlur: shape.layerBlur ?? ({
                "enabled": false,
                "radius": 0,
                "opacity": 1
            })
        grain: shape.grain ?? ({
                "enabled": false,
                "amount": 0.5,
                "size": 2
            })
        strokes: shape.strokes ?? []
        uid: shape.uid
        frameNo: shape.grainFrame
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: imageEffectPaint.pad + shape.sw / 2
            origin.y: imageEffectPaint.pad + shape.sh / 2
        }
    }

    // Video: linked file preview via MediaPlayer. Paused seeks to the
    // export frame (previewTime clock); while playing a 100ms poll
    // re-anchors past ~5 frames of drift so preview tracks the export
    // clock (unknown durations free-run until Replace probes them).
    // Missing files show a dark tile with a play glyph.
    Item {
        id: videoRoot

        anchors.fill: parent
        visible: shape.shapeType === "video" && !shape.paintHidden && !shape.useVideoEffectPaint
        opacity: shape.shapeOpacity
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: shape.sw / 2
            origin.y: shape.sh / 2
        }

        readonly property url videoFileUrl: shape.videoSource ? LibraryStore.videoUrl(shape.videoSource) : ""
        readonly property bool hasFile: videoFileUrl.toString() !== ""
        readonly property double wantTime: {
            // Sampler override wins while a Video time clip covers the
            // playhead (freeze/scrub/reverse/ramp); else legacy math.
            if (Number(shape.videoTime) >= 0)
                return Math.max(0, Number(shape.videoTime));
            var t = Math.max(0, Number(shape.previewTime) || 0);
            var off = Math.max(0, Number(shape.videoOffset) || 0);
            var start = Math.max(0, Number(shape.videoStart) || 0);
            var rate = Number(shape.playbackRate) || 1;
            if (!(rate > 0))
                rate = 1;
            rate = Math.min(4, Math.max(0.25, rate));
            var vt = off + Math.max(0, t - start) * rate;
            var dur = Math.max(0, Number(shape.videoDuration) || 0);
            if (dur > 0.05 && shape.videoLoop !== false)
                vt = vt % dur;
            return Math.max(0, vt);
        }

        Rectangle {
            anchors.fill: parent
            radius: Math.min(Math.max(0, shape.radius), Math.min(shape.sw, shape.sh) / 2)
            color: "#1a1a1a"
            visible: !videoRoot.hasFile || videoPlayer.error !== MediaPlayer.NoError || videoPlayer.mediaStatus === MediaPlayer.NoMedia
        }

        AppIcon {
            anchors.centerIn: parent
            kind: "play"
            iconColor: AppTheme.muted
            visible: !videoRoot.hasFile || videoPlayer.error !== MediaPlayer.NoError || videoPlayer.mediaStatus === MediaPlayer.NoMedia
        }

        MediaPlayer {
            id: videoPlayer
            source: videoRoot.videoFileUrl
            // Never autoplay: the picture only moves while the
            // composition plays (see previewPlaying below); paused
            // seeks to the export frame instead.
            autoPlay: false
            loops: shape.videoLoop !== false ? MediaPlayer.Infinite : 1
            audioOutput: AudioOutput {
                // Hidden leaves stay silent (eye/group/hide clip);
                // fades keep sound by design. Backdrop duplicates
                // (frosted-glass sampling) never contribute audio.
                muted: shape.videoMuted === true || shape.shapeVisible !== true || shape.isBackdropCapture
                volume: {
                    var vv = Number(shape.videoVolume);
                    if (!(vv >= 0))
                        vv = 1;
                    return Math.min(1, Math.max(0, vv));
                }
            }
            playbackRate: Math.min(4, Math.max(0.25, Number(shape.playbackRate) || 1))
            videoOutput: videoOut
            onHasVideoChanged: {
                if (!hasVideo || !videoRoot.hasFile || shape.isBackdropCapture)
                    return;
                if (shape.previewPlaying) {
                    if (videoPlayer.seekable)
                        videoPlayer.position = Math.round(videoRoot.wantTime * 1000);
                    videoPlayer.play();
                } else if (videoPlayer.seekable) {
                    videoPlayer.position = Math.round(videoRoot.wantTime * 1000);
                }
            }
        }

        VideoOutput {
            id: videoOut
            anchors.fill: parent
            visible: videoRoot.hasFile && videoPlayer.hasVideo
            fillMode: shape.videoFit === "cover" ? VideoOutput.PreserveAspectCrop : (shape.videoFit === "fill" ? VideoOutput.Stretch : VideoOutput.PreserveAspectFit)
            // Rounded corners + layer blur mask in place (mirrors the
            // image branch): a separate masked MultiEffect copy would
            // double-draw the raw square frame underneath and leak
            // square corners through the transparent mask.
            layer.enabled: videoPlayer.hasVideo && (shape.radius > 0 || shape.hasLayerBlur)
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: shape.radius > 0
                maskSource: videoMaskRect
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                blurEnabled: shape.hasLayerBlur
                blurMax: 64
                blur: shape.hasLayerBlur ? Math.min(1, Math.max(0, Number((shape.layerBlur ?? {}).radius || 0) / 64)) : 0
            }
        }

        // White silhouette as the mask (mirrors the image maskRect).
        // Radius clamps to half the smallest side like export
        // (FramePaint roundedClipPath) so oversized values can't
        // overflow the mask and look lopsided.
        Rectangle {
            id: videoMaskRect
            anchors.fill: parent
            radius: Math.min(Math.max(0, shape.radius), Math.min(shape.sw, shape.sh) / 2)
            color: "white"
            visible: false
            layer.enabled: true
            layer.smooth: true
        }

        // Stacked strokes, bottom-first (mirrors the image branch);
        // plain strokes paint here, dashed ride the effect painter.
        Repeater {
            model: shape.shapeType === "video" && !shape.useVideoEffectPaint ? shape.enabledStrokes.slice().reverse() : []

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
                radius: Math.min(Math.max(0, shape.radius), Math.min(shape.sw, shape.sh) / 2) + Math.max(0, -anchors.margins)
                color: "transparent"
                opacity: Math.min(1, Math.max(0, Number((modelData ?? {}).opacity ?? 1)))
                border.width: Number((modelData ?? {}).width) || 0
                border.color: String((modelData ?? {}).color ?? "#000000")
            }
        }

        Connections {
            target: shape
            function onPreviewTimeChanged() {
                if (!shape.previewPlaying && videoPlayer.hasVideo && videoPlayer.seekable) {
                    var want = Math.round(videoRoot.wantTime * 1000);
                    if (Math.abs(videoPlayer.position - want) > 120)
                        videoPlayer.position = want;
                }
            }
            function onPreviewPlayingChanged() {
                if (!videoRoot.hasFile || shape.isBackdropCapture)
                    return;
                if (shape.previewPlaying) {
                    if (videoPlayer.hasVideo && videoPlayer.seekable)
                        videoPlayer.position = Math.round(videoRoot.wantTime * 1000);
                    videoPlayer.play();
                } else {
                    videoPlayer.pause();
                    if (videoPlayer.hasVideo && videoPlayer.seekable)
                        videoPlayer.position = Math.round(videoRoot.wantTime * 1000);
                }
            }
        }

        // Drift repair while playing: the media clock and the
        // composition clock diverge (rate rounding, loop-wrap timing,
        // decode stalls), so re-anchor when past ~5 frames. Skipped
        // while the duration is unknown (no loop math to anchor to):
        // free-run until Replace probes it. Mirrors AudioPreview's
        // poll-repair at a tighter visual threshold.
        Timer {
            interval: 100
            repeat: true
            running: videoRoot.visible && shape.previewPlaying && videoRoot.hasFile && !shape.isBackdropCapture
            onTriggered: {
                if (!videoPlayer.hasVideo || !videoPlayer.seekable)
                    return;
                if (videoPlayer.playbackState !== MediaPlayer.PlayingState) {
                    videoPlayer.play();
                    return;
                }
                if (!(Number(shape.videoDuration) > 0.05))
                    return;
                var want = Math.round(videoRoot.wantTime * 1000);
                if (Math.abs(videoPlayer.position - want) > 150)
                    videoPlayer.position = want;
            }
        }
    }

    // Effected videos via the shared CPU painter (same pad rule).
    ImageEffectItem {
        id: videoEffectPaint

        x: -videoEffectPaint.pad
        y: -videoEffectPaint.pad
        width: shape.sw + videoEffectPaint.pad * 2
        height: shape.sh + videoEffectPaint.pad * 2
        visible: shape.useVideoEffectPaint && !shape.paintHidden
        opacity: shape.shapeOpacity
        boxW: shape.sw
        boxH: shape.sh
        radius: shape.radius
        videoSource: shape.videoSource
        videoDuration: shape.videoDuration
        videoOffset: shape.videoOffset
        playbackRate: shape.playbackRate
        videoLoop: shape.videoLoop !== false
        videoFit: (shape.videoFit === "cover" || shape.videoFit === "fill") ? shape.videoFit : "fit"
        videoTime: (shape.videoTime !== undefined && Number(shape.videoTime) >= 0) ? Number(shape.videoTime) : -1
        shadows: shape.shadows ?? []
        glows: shape.glows ?? []
        layerBlur: shape.layerBlur ?? ({
                "enabled": false,
                "radius": 0,
                "opacity": 1
            })
        grain: shape.grain ?? ({
                "enabled": false,
                "amount": 0.5,
                "size": 2
            })
        strokes: shape.strokes ?? []
        uid: shape.uid
        frameNo: shape.grainFrame
        transform: Scale {
            xScale: shape.flipH ? -1 : 1
            yScale: shape.flipV ? -1 : 1
            origin.x: videoEffectPaint.pad + shape.sw / 2
            origin.y: videoEffectPaint.pad + shape.sh / 2
        }
    }

    // Film grain over vectors/images/videos (text has its own glyph-masked copy).
    GrainOverlay {
        anchors.fill: parent
        visible: shape.hasGrain && shape.shapeType !== "text" && !shape.paintHidden && !shape.useImageEffectPaint && !shape.useVideoEffectPaint
        opacity: shape.shapeOpacity
        uid: shape.uid
        frameNo: shape.grainFrame
        amount: Number((shape.grain ?? {}).amount ?? 0.5)
        grainSize: Number((shape.grain ?? {}).size ?? 2)
        maskKind: (shape.shapeType === "rectangle" && !shape.independentCorners) || shape.shapeType === "image" || shape.shapeType === "video" ? "rect" : "path"
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

    // Selection outline: constant screen size at any zoom (selection bbox).
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

    // Move state: global-anchored drag with sub-pixel banking (no travel
    // lost; only whole screen pixels move shapes). `refused` claims
    // locked-shape presses so the marquee never starts.
    property bool moving: false
    property bool dragged: false
    property bool refused: false
    property real lastGX: 0
    property real lastGY: 0
    property real startGX: 0
    property real startGY: 0
    property real remCX: 0
    property real remCY: 0

    // Auto-size writeback for click-created text boxes (fixed boxes and
    // the inline editor stay quiet).
    function reportMeasure() {
        if (shape.shapeType !== "text" || !shape.autoSize || shape.editing)
            return;
        if (!shape.measurePolicy)
            return;
        shape.measurePolicy(shape.uid, glyphs.contentWidth, glyphs.contentHeight);
    }

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
        // Bank fractional travel, forward whole screen pixels only.
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
