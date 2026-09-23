import QtQuick

// Preset catalog and clip builders for one Document's animation.
// Builders capture nothing but explicit params: the sampler derives
// every frame from clip plus base snapshot, so clips stay valid when
// nodes move after being applied. Owned by DocAnim, which assigns clip ids.
QtObject {
    id: presets
    required property var doc

    function catalog() {
        return [
            {
                id: "appear",
                name: qsTr("Appear"),
                category: qsTr("Basic"),
                defaultEasing: "linear"
            },
            {
                id: "fade",
                name: qsTr("Fade"),
                category: qsTr("Fade"),
                defaultEasing: "easeOut"
            },
            {
                id: "slide",
                name: qsTr("Slide"),
                category: qsTr("Fade"),
                defaultEasing: "easeOut"
            },
            {
                id: "grow",
                name: qsTr("Grow"),
                category: qsTr("Scale"),
                defaultEasing: "easeOut"
            },
            {
                id: "shrink",
                name: qsTr("Shrink"),
                category: qsTr("Scale"),
                defaultEasing: "easeOut"
            },
            {
                id: "spin",
                name: qsTr("Spin"),
                category: "",
                defaultEasing: "linear"
            },
            {
                id: "twist",
                name: qsTr("Twist"),
                category: "",
                defaultEasing: "easeInOut"
            },
            {
                id: "movescale",
                name: qsTr("Move & Scale"),
                category: "",
                defaultEasing: "easeOut"
            },
            {
                id: "type",
                name: qsTr("Type"),
                category: qsTr("Text"),
                defaultEasing: "linear"
            }
        ];
    }

    function presetIds() {
        return ["appear", "fade", "slide", "grow", "shrink", "spin", "twist", "movescale", "type", "customScale", "customRotate", "customMove", "customOpacity", "customColor", "customGradient", "customHide", "customResize", "customCorner", "customStroke", "customStrokeColor", "customStrokeGradient", "customFontSize", "customFlip", "customShadow", "customLayerBlur", "customBackgroundBlur", "customGlow", "customGrain", "customPath"];
    }

    // Stepped presets switch state instead of interpolating (bools or
    // hard pops): they render as one diamond at t0 with a locked 0.1s
    // duration, never a span bar.
    function isStepped(presetId) {
        return presetId === "appear" || presetId === "customHide" || presetId === "customFlip";
    }

    // Custom from-to clips reuse the preset pipeline (timeline, undo,
    // easing, video-safe plain data). Later clips win per property like
    // presets, matching Figma Smart Animate merge behavior.
    function isCustom(presetId) {
        return String(presetId).slice(0, 6) === "custom";
    }

    function presetName(presetId) {
        if (presetId === "appear")
            return qsTr("Appear");
        if (presetId === "slide")
            return qsTr("Slide");
        if (presetId === "grow")
            return qsTr("Grow");
        if (presetId === "shrink")
            return qsTr("Shrink");
        if (presetId === "spin")
            return qsTr("Spin");
        if (presetId === "twist")
            return qsTr("Twist");
        if (presetId === "movescale")
            return qsTr("Move & Scale");
        if (presetId === "type")
            return qsTr("Type");
        if (presetId === "customScale")
            return qsTr("Scale");
        if (presetId === "customRotate")
            return qsTr("Rotate");
        if (presetId === "customMove")
            return qsTr("Move");
        if (presetId === "customOpacity")
            return qsTr("Opacity");
        if (presetId === "customColor")
            return qsTr("Color");
        if (presetId === "customGradient")
            return qsTr("Gradient");
        if (presetId === "customHide")
            return qsTr("Hide / Show");
        if (presetId === "customResize")
            return qsTr("Resize");
        if (presetId === "customCorner")
            return qsTr("Corner Radius");
        if (presetId === "customStroke")
            return qsTr("Stroke");
        if (presetId === "customStrokeColor")
            return qsTr("Stroke color");
        if (presetId === "customStrokeGradient")
            return qsTr("Stroke gradient");
        if (presetId === "customFontSize")
            return qsTr("Font size");
        if (presetId === "customFlip")
            return qsTr("Flip");
        if (presetId === "customShadow")
            return qsTr("Shadow");
        if (presetId === "customLayerBlur")
            return qsTr("Layer Blur");
        if (presetId === "customBackgroundBlur")
            return qsTr("Background Blur");
        if (presetId === "customGlow")
            return qsTr("Glow");
        if (presetId === "customGrain")
            return qsTr("Grain");
        if (presetId === "customPath")
            return qsTr("Path");
        return qsTr("Fade");
    }

    function defaultEasingFor(presetId) {
        var all = catalog();
        for (var i = 0; i < all.length; i++) {
            if (all[i].id === presetId)
                return all[i].defaultEasing;
        }
        return "easeOut";
    }

    function defaultsFor(presetId) {
        if (presetId === "slide")
            return {
                direction: "left",
                distance: 200,
                fade: true
            };
        if (presetId === "spin")
            return {
                direction: "cw",
                turns: 1
            };
        if (presetId === "twist")
            return {
                direction: "cw"
            };
        if (presetId === "movescale")
            return {
                direction: "left",
                distance: 200,
                scale: 0
            };
        if (presetId === "type")
            return {
                unit: "letters",
                cps: 20,
                cursor: false
            };
        if (presetId === "customScale")
            return {
                from: 0,
                to: 1
            };
        if (presetId === "customRotate")
            return {
                from: 0,
                to: 90
            };
        if (presetId === "customMove")
            return {
                fromX: 0,
                fromY: 0,
                toX: 200,
                toY: 0
            };
        if (presetId === "customOpacity")
            return {
                from: 0,
                to: 1
            };
        if (presetId === "customColor")
            return {
                from: "#000000",
                to: "#ff0000",
                fromOpacity: 1,
                toOpacity: 1,
                fillIndex: 0
            };
        if (presetId === "customGradient")
            return {
                fromC1: "#000000",
                toC1: "#000000",
                fromC2: "#ffffff",
                toC2: "#ff0000",
                fromAngle: 90,
                toAngle: 90,
                fromOpacity: 1,
                toOpacity: 1,
                fillIndex: 0
            };
        if (presetId === "customHide")
            return {
                fromVisible: true,
                toVisible: false
            };
        if (presetId === "customResize")
            return {
                fromW: 100,
                fromH: 100,
                toW: 200,
                toH: 200
            };
        if (presetId === "customCorner")
            return {
                from: 0,
                to: 24
            };
        if (presetId === "customStroke")
            return {
                from: 0,
                to: 4,
                fromOpacity: 1,
                toOpacity: 1,
                fromDash: 0,
                toDash: 0,
                fromGap: 0,
                toGap: 0,
                fromPosition: "center",
                toPosition: "center",
                strokeIndex: 0
            };
        if (presetId === "customStrokeColor")
            return {
                from: "#000000",
                to: "#ff0000",
                fromOpacity: 1,
                toOpacity: 1,
                strokeIndex: 0
            };
        if (presetId === "customStrokeGradient")
            return {
                fromC1: "#000000",
                toC1: "#000000",
                fromC2: "#ffffff",
                toC2: "#ff0000",
                fromAngle: 90,
                toAngle: 90,
                fromOpacity: 1,
                toOpacity: 1,
                from: 1,
                to: 1,
                fromDash: 0,
                toDash: 0,
                fromGap: 0,
                toGap: 0,
                fromPosition: "center",
                toPosition: "center",
                strokeIndex: 0
            };
        if (presetId === "customFontSize")
            return {
                from: 16,
                to: 32
            };
        if (presetId === "customFlip")
            return {
                axis: "h"
            };
        if (presetId === "customShadow")
            return {
                fromColor: "#80000000",
                toColor: "#80000000",
                fromX: 0,
                toX: 0,
                fromY: 4,
                toY: 12,
                fromBlur: 8,
                toBlur: 16,
                fromSpread: 0,
                toSpread: 0,
                fromInner: false,
                toInner: false,
                shadowIndex: 0
            };
        if (presetId === "customLayerBlur")
            return {
                fromRadius: 0,
                toRadius: 12,
                fromOpacity: 1,
                toOpacity: 1
            };
        if (presetId === "customBackgroundBlur")
            return {
                fromRadius: 0,
                toRadius: 16,
                fromOpacity: 0.7,
                toOpacity: 0.7
            };
        if (presetId === "customGlow")
            return {
                fromColor: "#cc00ffff",
                toColor: "#cc00ffff",
                fromBlur: 16,
                toBlur: 28,
                fromSpread: 4,
                toSpread: 4,
                fromInner: false,
                toInner: false,
                glowIndex: 0
            };
        if (presetId === "customGrain")
            return {
                fromAmount: 0,
                toAmount: 0.5,
                fromSize: 2,
                toSize: 2
            };
        if (presetId === "customPath")
            return {
                pts: [],
                closed: false,
                orient: false
            };
        return {};
    }

    function slideDirection(v) {
        return v === "right" || v === "up" || v === "down" ? v : "left";
    }

    function spinDirection(v) {
        return v === "ccw" ? "ccw" : "cw";
    }

    function typeUnit(v) {
        return v === "words" || v === "lines" ? v : "letters";
    }

    function clampNum(v, fallback, lo, hi) {
        var n = Number(v);
        if (isNaN(n))
            return fallback;
        return Math.min(hi, Math.max(lo, n));
    }

    function normalizeStrokePosition(v) {
        return v === "inside" || v === "outside" ? v : "center";
    }

    // Stack entry index for style clips (0 = top). Capped so a
    // hand-edited scene can never stage a silly index; targets with
    // fewer entries pad with defaults at sample time.
    function normalizeEntryIndex(v) {
        var n = Math.round(Number(v));
        if (isNaN(n))
            return 0;
        return Math.min(32, Math.max(0, n));
    }

    function normalizeOpacity(v, fallback) {
        var n = Number(v);
        if (isNaN(n))
            return fallback;
        return Math.min(1, Math.max(0, n));
    }

    function normalizeHex(v, fallback) {
        var t = String(v !== undefined ? v : "").trim().toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (/^[0-9a-f]{3}$/.test(t))
            t = t.charAt(0) + t.charAt(0) + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2);
        if (/^[0-9a-f]{6}$/.test(t))
            return "#" + t;
        return fallback;
    }

    // Alpha-aware twin for shadow colors: preserves #aarrggbb so
    // opacity animates; opaque stays #rrggbb.
    function normalizeHexA(v, fallback) {
        var t = String(v !== undefined ? v : "").trim().toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (/^[0-9a-f]{3}$/.test(t))
            t = t.charAt(0) + t.charAt(0) + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2);
        if (/^[0-9a-f]{8}$/.test(t) || /^[0-9a-f]{6}$/.test(t))
            return "#" + t;
        return fallback;
    }

    function normalizePathPts(raw) {
        var out = [];
        var list = raw || [];
        for (var i = 0; i < list.length; i++) {
            var p = list[i] || {};
            out.push({
                x: clampNum(p.x, 0, -4000, 4000),
                y: clampNum(p.y, 0, -4000, 4000),
                smooth: p.smooth === true,
                inX: clampNum(p.inX !== undefined ? p.inX : p.x, 0, -4000, 4000),
                inY: clampNum(p.inY !== undefined ? p.inY : p.y, 0, -4000, 4000),
                outX: clampNum(p.outX !== undefined ? p.outX : p.x, 0, -4000, 4000),
                outY: clampNum(p.outY !== undefined ? p.outY : p.y, 0, -4000, 4000)
            });
        }
        return out;
    }

    // Merges user options over defaults, coercing enums and ranges so
    // stored clips are always backend-safe (plain values only).
    function normalizeOptions(presetId, raw) {
        var r = raw || {};
        if (presetId === "slide")
            return {
                direction: slideDirection(r.direction !== undefined ? r.direction : "left"),
                distance: clampNum(r.distance !== undefined ? r.distance : 200, 200, 0, 2000),
                fade: r.fade !== false
            };
        if (presetId === "spin")
            return {
                direction: spinDirection(r.direction !== undefined ? r.direction : "cw"),
                turns: clampNum(r.turns !== undefined ? r.turns : 1, 1, 0.25, 10)
            };
        if (presetId === "twist")
            return {
                direction: spinDirection(r.direction !== undefined ? r.direction : "cw")
            };
        if (presetId === "movescale")
            return {
                direction: slideDirection(r.direction !== undefined ? r.direction : "left"),
                distance: clampNum(r.distance !== undefined ? r.distance : 200, 200, 0, 2000),
                scale: clampNum(r.scale !== undefined ? r.scale : 0, 0, 0, 150)
            };
        if (presetId === "type")
            return {
                unit: typeUnit(r.unit !== undefined ? r.unit : "letters"),
                cps: clampNum(r.cps !== undefined ? r.cps : 20, 20, 1, 120),
                cursor: r.cursor === true
            };
        if (presetId === "customScale")
            return {
                from: clampNum(r.from !== undefined ? r.from : 0, 0, 0, 10),
                to: clampNum(r.to !== undefined ? r.to : 1, 1, 0, 10)
            };
        if (presetId === "customRotate")
            return {
                from: clampNum(r.from !== undefined ? r.from : 0, 0, -1440, 1440),
                to: clampNum(r.to !== undefined ? r.to : 90, 90, -1440, 1440)
            };
        if (presetId === "customMove")
            return {
                fromX: clampNum(r.fromX !== undefined ? r.fromX : 0, 0, -2000, 2000),
                fromY: clampNum(r.fromY !== undefined ? r.fromY : 0, 0, -2000, 2000),
                toX: clampNum(r.toX !== undefined ? r.toX : 200, 200, -2000, 2000),
                toY: clampNum(r.toY !== undefined ? r.toY : 0, 0, -2000, 2000)
            };
        if (presetId === "customOpacity")
            return {
                from: clampNum(r.from !== undefined ? r.from : 0, 0, 0, 1),
                to: clampNum(r.to !== undefined ? r.to : 1, 1, 0, 1)
            };
        if (presetId === "customColor") {
            var co = {
                from: normalizeHex(r.from !== undefined ? r.from : "#000000", "#000000"),
                to: normalizeHex(r.to !== undefined ? r.to : "#ff0000", "#ff0000")
            };
            // Extended keys are opt-in: old clips without them stay
            // color-only so they never stomp entry opacity.
            if (r.fromOpacity !== undefined || r.toOpacity !== undefined) {
                co.fromOpacity = normalizeOpacity(r.fromOpacity !== undefined ? r.fromOpacity : 1, 1);
                co.toOpacity = normalizeOpacity(r.toOpacity !== undefined ? r.toOpacity : 1, 1);
            }
            if (r.fillIndex !== undefined)
                co.fillIndex = normalizeEntryIndex(r.fillIndex);
            return co;
        }
        if (presetId === "customGradient") {
            var cg = {
                fromC1: normalizeHex(r.fromC1 !== undefined ? r.fromC1 : "#000000", "#000000"),
                toC1: normalizeHex(r.toC1 !== undefined ? r.toC1 : "#000000", "#000000"),
                fromC2: normalizeHex(r.fromC2 !== undefined ? r.fromC2 : "#ffffff", "#ffffff"),
                toC2: normalizeHex(r.toC2 !== undefined ? r.toC2 : "#ff0000", "#ff0000"),
                fromAngle: clampNum(r.fromAngle !== undefined ? r.fromAngle : 90, 90, 0, 360),
                toAngle: clampNum(r.toAngle !== undefined ? r.toAngle : 90, 90, 0, 360)
            };
            if (r.fromOpacity !== undefined || r.toOpacity !== undefined) {
                cg.fromOpacity = normalizeOpacity(r.fromOpacity !== undefined ? r.fromOpacity : 1, 1);
                cg.toOpacity = normalizeOpacity(r.toOpacity !== undefined ? r.toOpacity : 1, 1);
            }
            if (r.fillIndex !== undefined)
                cg.fillIndex = normalizeEntryIndex(r.fillIndex);
            return cg;
        }
        if (presetId === "customHide")
            return {
                fromVisible: r.fromVisible === undefined ? true : !!r.fromVisible,
                toVisible: r.toVisible === undefined ? false : !!r.toVisible
            };
        if (presetId === "customResize")
            return {
                fromW: clampNum(r.fromW !== undefined ? r.fromW : 100, 100, 1, 4000),
                fromH: clampNum(r.fromH !== undefined ? r.fromH : 100, 100, 1, 4000),
                toW: clampNum(r.toW !== undefined ? r.toW : 200, 200, 1, 4000),
                toH: clampNum(r.toH !== undefined ? r.toH : 200, 200, 1, 4000)
            };
        if (presetId === "customCorner")
            return {
                from: clampNum(r.from !== undefined ? r.from : 0, 0, 0, 500),
                to: clampNum(r.to !== undefined ? r.to : 24, 24, 0, 500)
            };
        if (presetId === "customStroke") {
            var cs = {
                from: clampNum(r.from !== undefined ? r.from : 0, 0, 0, 100),
                to: clampNum(r.to !== undefined ? r.to : 4, 4, 0, 100)
            };
            // Extended keys are opt-in (see customColor): old
            // width-only clips never gain them on rebuild.
            if (r.fromOpacity !== undefined || r.toOpacity !== undefined) {
                cs.fromOpacity = normalizeOpacity(r.fromOpacity !== undefined ? r.fromOpacity : 1, 1);
                cs.toOpacity = normalizeOpacity(r.toOpacity !== undefined ? r.toOpacity : 1, 1);
            }
            if (r.fromDash !== undefined || r.toDash !== undefined || r.fromGap !== undefined || r.toGap !== undefined) {
                cs.fromDash = clampNum(r.fromDash !== undefined ? r.fromDash : 0, 0, 0, 100);
                cs.toDash = clampNum(r.toDash !== undefined ? r.toDash : 0, 0, 0, 100);
                cs.fromGap = clampNum(r.fromGap !== undefined ? r.fromGap : 0, 0, 0, 100);
                cs.toGap = clampNum(r.toGap !== undefined ? r.toGap : 0, 0, 0, 100);
            }
            if (r.fromPosition !== undefined || r.toPosition !== undefined) {
                cs.fromPosition = normalizeStrokePosition(r.fromPosition !== undefined ? r.fromPosition : "center");
                cs.toPosition = normalizeStrokePosition(r.toPosition !== undefined ? r.toPosition : "center");
            }
            if (r.strokeIndex !== undefined)
                cs.strokeIndex = normalizeEntryIndex(r.strokeIndex);
            return cs;
        }
        if (presetId === "customStrokeColor") {
            var cc2 = {
                from: normalizeHex(r.from !== undefined ? r.from : "#000000", "#000000"),
                to: normalizeHex(r.to !== undefined ? r.to : "#ff0000", "#ff0000")
            };
            if (r.fromOpacity !== undefined || r.toOpacity !== undefined) {
                cc2.fromOpacity = normalizeOpacity(r.fromOpacity !== undefined ? r.fromOpacity : 1, 1);
                cc2.toOpacity = normalizeOpacity(r.toOpacity !== undefined ? r.toOpacity : 1, 1);
            }
            if (r.strokeIndex !== undefined)
                cc2.strokeIndex = normalizeEntryIndex(r.strokeIndex);
            return cc2;
        }
        if (presetId === "customStrokeGradient") {
            var sg = {
                fromC1: normalizeHex(r.fromC1 !== undefined ? r.fromC1 : "#000000", "#000000"),
                toC1: normalizeHex(r.toC1 !== undefined ? r.toC1 : "#000000", "#000000"),
                fromC2: normalizeHex(r.fromC2 !== undefined ? r.fromC2 : "#ffffff", "#ffffff"),
                toC2: normalizeHex(r.toC2 !== undefined ? r.toC2 : "#ff0000", "#ff0000"),
                fromAngle: clampNum(r.fromAngle !== undefined ? r.fromAngle : 90, 90, 0, 360),
                toAngle: clampNum(r.toAngle !== undefined ? r.toAngle : 90, 90, 0, 360),
                fromOpacity: normalizeOpacity(r.fromOpacity !== undefined ? r.fromOpacity : 1, 1),
                toOpacity: normalizeOpacity(r.toOpacity !== undefined ? r.toOpacity : 1, 1)
            };
            // Width/dash/position ride along only when the clip carries
            // them (new clips seed them; old gradient-only clips stay
            // gradient-only so custom width/dash/position survive).
            if (r.from !== undefined || r.to !== undefined) {
                sg.from = clampNum(r.from !== undefined ? r.from : 1, 1, 0, 100);
                sg.to = clampNum(r.to !== undefined ? r.to : 1, 1, 0, 100);
            }
            if (r.fromDash !== undefined || r.toDash !== undefined || r.fromGap !== undefined || r.toGap !== undefined) {
                sg.fromDash = clampNum(r.fromDash !== undefined ? r.fromDash : 0, 0, 0, 100);
                sg.toDash = clampNum(r.toDash !== undefined ? r.toDash : 0, 0, 0, 100);
                sg.fromGap = clampNum(r.fromGap !== undefined ? r.fromGap : 0, 0, 0, 100);
                sg.toGap = clampNum(r.toGap !== undefined ? r.toGap : 0, 0, 0, 100);
            }
            if (r.fromPosition !== undefined || r.toPosition !== undefined) {
                sg.fromPosition = normalizeStrokePosition(r.fromPosition !== undefined ? r.fromPosition : "center");
                sg.toPosition = normalizeStrokePosition(r.toPosition !== undefined ? r.toPosition : "center");
            }
            if (r.strokeIndex !== undefined)
                sg.strokeIndex = normalizeEntryIndex(r.strokeIndex);
            return sg;
        }
        if (presetId === "customFontSize")
            return {
                from: clampNum(r.from !== undefined ? r.from : 16, 16, 1, 500),
                to: clampNum(r.to !== undefined ? r.to : 32, 32, 1, 500)
            };
        if (presetId === "customFlip")
            return {
                axis: r.axis === "v" ? "v" : "h"
            };
        if (presetId === "customShadow") {
            var sh = {
                fromColor: normalizeHexA(r.fromColor !== undefined ? r.fromColor : "#80000000", "#80000000"),
                toColor: normalizeHexA(r.toColor !== undefined ? r.toColor : "#80000000", "#80000000"),
                fromX: clampNum(r.fromX !== undefined ? r.fromX : 0, 0, -500, 500),
                toX: clampNum(r.toX !== undefined ? r.toX : 0, 0, -500, 500),
                fromY: clampNum(r.fromY !== undefined ? r.fromY : 4, 4, -500, 500),
                toY: clampNum(r.toY !== undefined ? r.toY : 12, 12, -500, 500),
                fromBlur: clampNum(r.fromBlur !== undefined ? r.fromBlur : 8, 8, 0, 100),
                toBlur: clampNum(r.toBlur !== undefined ? r.toBlur : 16, 16, 0, 100),
                fromSpread: clampNum(r.fromSpread !== undefined ? r.fromSpread : 0, 0, 0, 50),
                toSpread: clampNum(r.toSpread !== undefined ? r.toSpread : 0, 0, 0, 50),
                fromInner: r.fromInner === undefined ? false : !!r.fromInner,
                toInner: r.toInner === undefined ? false : !!r.toInner
            };
            if (r.shadowIndex !== undefined)
                sh.shadowIndex = normalizeEntryIndex(r.shadowIndex);
            return sh;
        }
        if (presetId === "customLayerBlur")
            return {
                fromRadius: clampNum(r.fromRadius !== undefined ? r.fromRadius : 0, 0, 0, 100),
                toRadius: clampNum(r.toRadius !== undefined ? r.toRadius : 12, 12, 0, 100),
                fromOpacity: clampNum(r.fromOpacity !== undefined ? r.fromOpacity : 1, 1, 0, 1),
                toOpacity: clampNum(r.toOpacity !== undefined ? r.toOpacity : 1, 1, 0, 1)
            };
        if (presetId === "customBackgroundBlur")
            return {
                fromRadius: clampNum(r.fromRadius !== undefined ? r.fromRadius : 0, 0, 0, 100),
                toRadius: clampNum(r.toRadius !== undefined ? r.toRadius : 16, 16, 0, 100),
                fromOpacity: clampNum(r.fromOpacity !== undefined ? r.fromOpacity : 0.7, 0.7, 0, 1),
                toOpacity: clampNum(r.toOpacity !== undefined ? r.toOpacity : 0.7, 0.7, 0, 1)
            };
        if (presetId === "customGlow") {
            var gl = {
                fromColor: normalizeHexA(r.fromColor !== undefined ? r.fromColor : "#cc00ffff", "#cc00ffff"),
                toColor: normalizeHexA(r.toColor !== undefined ? r.toColor : "#cc00ffff", "#cc00ffff"),
                fromBlur: clampNum(r.fromBlur !== undefined ? r.fromBlur : 16, 16, 0, 100),
                toBlur: clampNum(r.toBlur !== undefined ? r.toBlur : 28, 28, 0, 100),
                fromSpread: clampNum(r.fromSpread !== undefined ? r.fromSpread : 4, 4, 0, 50),
                toSpread: clampNum(r.toSpread !== undefined ? r.toSpread : 4, 4, 0, 50),
                fromInner: r.fromInner === undefined ? false : !!r.fromInner,
                toInner: r.toInner === undefined ? false : !!r.toInner
            };
            if (r.glowIndex !== undefined)
                gl.glowIndex = normalizeEntryIndex(r.glowIndex);
            return gl;
        }
        if (presetId === "customGrain")
            return {
                fromAmount: clampNum(r.fromAmount !== undefined ? r.fromAmount : 0, 0, 0, 1),
                toAmount: clampNum(r.toAmount !== undefined ? r.toAmount : 0.5, 0.5, 0, 1),
                fromSize: clampNum(r.fromSize !== undefined ? r.fromSize : 2, 2, 1, 10),
                toSize: clampNum(r.toSize !== undefined ? r.toSize : 2, 2, 1, 10)
            };
        if (presetId === "customPath")
            return {
                pts: normalizePathPts(r.pts),
                closed: r.closed === true,
                orient: r.orient === true
            };
        return {};
    }

    function normalizeMode(mode) {
        return mode === "out" ? "out" : "in";
    }

    // Clip loop: none holds the end state (current behavior), loop
    // restarts each cycle, pingpong runs forward then backward.
    // Stored top-level on the clip (not in options) so edits that
    // rebuild options never drop it; old scenes miss it and read none.
    function normalizeLoop(loop) {
        return loop === "loop" || loop === "pingpong" ? loop : "none";
    }

    // Easing presets for the graph editor. Bezier values are the
    // CSS-equivalent handles for display and dragging; the sampler keeps
    // exact cubics for the named ids and uses bezier only for custom.
    function easingPresets() {
        return [
            {
                id: "linear",
                name: qsTr("Linear"),
                bezier: [0, 0, 1, 1]
            },
            {
                id: "easeIn",
                name: qsTr("Ease In"),
                bezier: [0.42, 0, 1, 1]
            },
            {
                id: "easeOut",
                name: qsTr("Ease Out"),
                bezier: [0, 0, 0.58, 1]
            },
            {
                id: "easeInOut",
                name: qsTr("Ease In-Out"),
                bezier: [0.42, 0, 0.58, 1]
            },
            {
                id: "slowDown",
                name: qsTr("Slow down"),
                bezier: [0.22, 1, 0.36, 1]
            },
            {
                id: "backOut",
                name: qsTr("Pop"),
                bezier: [0.34, 1.56, 0.64, 1]
            },
            {
                id: "backInOut",
                name: qsTr("Pop in-out"),
                bezier: [0.68, -0.4, 0.32, 1.4]
            },
            {
                id: "bounceOut",
                name: qsTr("Bounce"),
                bezier: [0.34, 1.3, 0.64, 1]
            },
            {
                id: "elasticOut",
                name: qsTr("Elastic"),
                bezier: [0.3, 1.2, 0.4, 1]
            }
        ];
    }

    function easingName(id) {
        var all = easingPresets();
        for (var i = 0; i < all.length; i++) {
            if (all[i].id === id)
                return all[i].name;
        }
        return qsTr("Custom");
    }

    function easingBezier(id) {
        var all = easingPresets();
        for (var j = 0; j < all.length; j++) {
            if (all[j].id === id)
                return all[j].bezier.slice();
        }
        return [0.25, 0.1, 0.25, 1];
    }

    function buildClip(presetId, clipId, targetUid, t0, duration, mode, options, easing, loop) {
        var ez = easing || {};
        var ct0 = Math.max(0, Number(t0) || 0);
        // Clips never stage past the composition end (applying near the
        // tail yields a shorter clip, never an overhanging one).
        // Stepped clips are instants: locked to the 0.1s floor so the
        // switch reads as one keyframe at t0 on every surface.
        var comp = presets.doc && presets.doc.anim ? presets.doc.anim.duration : 60;
        var cd = Math.min(60, Math.max(0.1, Number(duration) || 0.8));
        cd = Math.min(cd, Math.max(0.1, comp - ct0));
        if (isStepped(presetId))
            cd = 0.1;
        return {
            id: clipId,
            targetUid: targetUid,
            preset: presetId,
            t0: ct0,
            duration: cd,
            mode: normalizeMode(mode),
            loop: normalizeLoop(loop),
            options: normalizeOptions(presetId, options),
            easing: {
                id: typeof ez.id === "string" && ez.id !== "" ? ez.id : defaultEasingFor(presetId),
                bezier: ez.bezier
            }
        };
    }
}
