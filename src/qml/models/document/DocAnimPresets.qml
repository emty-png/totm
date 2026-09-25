import QtQuick

// Preset catalog and clip builders for one Document's animation.
// Frames derive from clip plus base snapshot, so clips stay valid when
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
            },
            {
                id: "maskWipe",
                name: qsTr("Mask Wipe"),
                category: qsTr("Mask"),
                defaultEasing: "easeOut"
            },
            {
                id: "maskIris",
                name: qsTr("Mask Iris"),
                category: qsTr("Mask"),
                defaultEasing: "easeOut"
            }
        ];
    }

    function presetIds() {
        return ["appear", "fade", "slide", "grow", "shrink", "spin", "twist", "movescale", "type", "maskWipe", "maskIris", "customScale", "customRotate", "customMove", "customOpacity", "customColor", "customGradient", "customHide", "customResize", "customCorner", "customStroke", "customStrokeColor", "customStrokeGradient", "customFontSize", "customFlip", "customShadow", "customLayerBlur", "customBackgroundBlur", "customGlow", "customGrain", "customPath"];
    }

    // Stepped presets render as one diamond at t0 with a locked 0.1s
    // duration (see buildClip), never a span bar.
    function isStepped(presetId) {
        return presetId === "appear" || presetId === "customHide" || presetId === "customFlip";
    }

    // Keyframeable presets: custom from-to clips plus mask reveals.
    // Stepped clips (appear/hide/flip), path clips (own pts geometry)
    // and non-custom presets stay from-to only.
    function isKeyframeable(presetId) {
        if (presetId === "maskWipe" || presetId === "maskIris")
            return true;
        if (!isCustom(presetId))
            return false;
        return presetId !== "customHide" && presetId !== "customFlip" && presetId !== "customPath";
    }

    // Custom from-to clips reuse the preset pipeline; later clips win
    // per property, matching Figma Smart Animate merge behavior.
    function isCustom(presetId) {
        return String(presetId).slice(0, 6) === "custom";
    }

    function presetName(presetId) {
        var names = {
            "appear": qsTr("Appear"),
            "slide": qsTr("Slide"),
            "grow": qsTr("Grow"),
            "shrink": qsTr("Shrink"),
            "spin": qsTr("Spin"),
            "twist": qsTr("Twist"),
            "movescale": qsTr("Move & Scale"),
            "type": qsTr("Type"),
            "maskWipe": qsTr("Mask Wipe"),
            "maskIris": qsTr("Mask Iris"),
            "customScale": qsTr("Scale"),
            "customRotate": qsTr("Rotate"),
            "customMove": qsTr("Move"),
            "customOpacity": qsTr("Opacity"),
            "customColor": qsTr("Color"),
            "customGradient": qsTr("Gradient"),
            "customHide": qsTr("Hide / Show"),
            "customResize": qsTr("Resize"),
            "customCorner": qsTr("Corner Radius"),
            "customStroke": qsTr("Stroke"),
            "customStrokeColor": qsTr("Stroke color"),
            "customStrokeGradient": qsTr("Stroke gradient"),
            "customFontSize": qsTr("Font size"),
            "customFlip": qsTr("Flip"),
            "customShadow": qsTr("Shadow"),
            "customLayerBlur": qsTr("Layer Blur"),
            "customBackgroundBlur": qsTr("Background Blur"),
            "customGlow": qsTr("Glow"),
            "customGrain": qsTr("Grain"),
            "customPath": qsTr("Path")
        };
        return names[presetId] !== undefined ? names[presetId] : qsTr("Fade");
    }

    // Entry suffix for style/effect clips (" · Fill 2"): 1-based, shown
    // only when the clip carries its index key so old clips stay clean.
    function entrySuffix(presetId, options) {
        var o = options || {};
        if (presetId === "customColor" || presetId === "customGradient") {
            if (o.fillIndex === undefined)
                return "";
            return " · " + qsTr("Fill %1").arg(normalizeEntryIndex(o.fillIndex) + 1);
        }
        if (presetId === "customStroke" || presetId === "customStrokeColor" || presetId === "customStrokeGradient") {
            if (o.strokeIndex === undefined)
                return "";
            return " · " + qsTr("Stroke %1").arg(normalizeEntryIndex(o.strokeIndex) + 1);
        }
        if (presetId === "customShadow") {
            if (o.shadowIndex === undefined)
                return "";
            return " · " + qsTr("Shadow %1").arg(normalizeEntryIndex(o.shadowIndex) + 1);
        }
        if (presetId === "customGlow") {
            if (o.glowIndex === undefined)
                return "";
            return " · " + qsTr("Glow %1").arg(normalizeEntryIndex(o.glowIndex) + 1);
        }
        return "";
    }

    function defaultEasingFor(presetId) {
        var all = catalog();
        for (var i = 0; i < all.length; i++) {
            if (all[i].id === presetId)
                return all[i].defaultEasing;
        }
        return "easeOut";
    }

    // Fresh defaults per call (callers mutate the result).
    readonly property var _defaultOptions: {
        "slide": {
            direction: "left",
            distance: 200,
            fade: true
        },
        "spin": {
            direction: "cw",
            turns: 1
        },
        "twist": {
            direction: "cw"
        },
        "movescale": {
            direction: "left",
            distance: 200,
            scale: 0
        },
        "type": {
            unit: "letters",
            cps: 20,
            cursor: false
        },
        "maskWipe": {
            direction: "left",
            feather: 0,
            invert: false
        },
        "maskIris": {
            feather: 0,
            invert: false
        },
        "customScale": {
            from: 0,
            to: 1
        },
        "customRotate": {
            from: 0,
            to: 90
        },
        "customMove": {
            fromX: 0,
            fromY: 0,
            toX: 200,
            toY: 0
        },
        "customOpacity": {
            from: 0,
            to: 1
        },
        "customColor": {
            from: "#000000",
            to: "#ff0000",
            fromOpacity: 1,
            toOpacity: 1,
            fillIndex: 0
        },
        "customGradient": {
            fromC1: "#000000",
            toC1: "#000000",
            fromC2: "#ffffff",
            toC2: "#ff0000",
            fromAngle: 90,
            toAngle: 90,
            fromOpacity: 1,
            toOpacity: 1,
            fillIndex: 0
        },
        "customHide": {
            fromVisible: true,
            toVisible: false
        },
        "customResize": {
            fromW: 100,
            fromH: 100,
            toW: 200,
            toH: 200
        },
        "customCorner": {
            from: 0,
            to: 24
        },
        "customStroke": {
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
        },
        "customStrokeColor": {
            from: "#000000",
            to: "#ff0000",
            fromOpacity: 1,
            toOpacity: 1,
            strokeIndex: 0
        },
        "customStrokeGradient": {
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
        },
        "customFontSize": {
            from: 16,
            to: 32
        },
        "customFlip": {
            axis: "h"
        },
        "customShadow": {
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
        },
        "customLayerBlur": {
            fromRadius: 0,
            toRadius: 12,
            fromOpacity: 1,
            toOpacity: 1
        },
        "customBackgroundBlur": {
            fromRadius: 0,
            toRadius: 16,
            fromOpacity: 0.7,
            toOpacity: 0.7
        },
        "customGlow": {
            fromColor: "#cc00ffff",
            toColor: "#cc00ffff",
            fromBlur: 16,
            toBlur: 28,
            fromSpread: 4,
            toSpread: 4,
            fromInner: false,
            toInner: false,
            glowIndex: 0
        },
        "customGrain": {
            fromAmount: 0,
            toAmount: 0.5,
            fromSize: 2,
            toSize: 2
        },
        "customPath": {
            pts: [],
            closed: false,
            orient: false
        }
    }

    function defaultsFor(presetId) {
        var t = presets._defaultOptions[presetId];
        return t !== undefined ? JSON.parse(JSON.stringify(t)) : {};
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

    // Stack entry index (0 = top), capped so hand-edited scenes stay sane;
    // short stacks pad with defaults at sample time.
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

    // Alpha-aware twin for shadow colors: preserves #aarrggbb so opacity
    // animates; opaque stays #rrggbb.
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

    // Stored clips stay backend-safe (plain values only). Extended keys
    // are opt-in: old clips without them never gain them on rebuild, so
    // they can't stomp values the old editor never wrote.
    function normalizeOptions(presetId, raw) {
        var f = presets._normalizerFor(presetId);
        return f ? f(raw || {}) : {};
    }

    function _normalizerFor(presetId) {
        var table = {
            "slide": presets._normalizeSlide,
            "spin": presets._normalizeSpin,
            "twist": presets._normalizeTwist,
            "movescale": presets._normalizeMovescale,
            "type": presets._normalizeType,
            "maskWipe": presets._normalizeMaskWipe,
            "maskIris": presets._normalizeMaskIris,
            "customScale": presets._normalizeCustomScale,
            "customRotate": presets._normalizeCustomRotate,
            "customMove": presets._normalizeCustomMove,
            "customOpacity": presets._normalizeCustomOpacity,
            "customColor": presets._normalizeCustomColor,
            "customGradient": presets._normalizeCustomGradient,
            "customHide": presets._normalizeCustomHide,
            "customResize": presets._normalizeCustomResize,
            "customCorner": presets._normalizeCustomCorner,
            "customStroke": presets._normalizeCustomStroke,
            "customStrokeColor": presets._normalizeCustomStrokeColor,
            "customStrokeGradient": presets._normalizeCustomStrokeGradient,
            "customFontSize": presets._normalizeCustomFontSize,
            "customFlip": presets._normalizeCustomFlip,
            "customShadow": presets._normalizeCustomShadow,
            "customLayerBlur": presets._normalizeCustomLayerBlur,
            "customBackgroundBlur": presets._normalizeCustomBackgroundBlur,
            "customGlow": presets._normalizeCustomGlow,
            "customGrain": presets._normalizeCustomGrain,
            "customPath": presets._normalizeCustomPath
        };
        return table[presetId];
    }

    function _normalizeSlide(r) {
        return {
            direction: slideDirection(r.direction !== undefined ? r.direction : "left"),
            distance: clampNum(r.distance !== undefined ? r.distance : 200, 200, 0, 2000),
            fade: r.fade !== false
        };
    }

    function _normalizeSpin(r) {
        return {
            direction: spinDirection(r.direction !== undefined ? r.direction : "cw"),
            turns: clampNum(r.turns !== undefined ? r.turns : 1, 1, 0.25, 10)
        };
    }

    function _normalizeTwist(r) {
        return {
            direction: spinDirection(r.direction !== undefined ? r.direction : "cw")
        };
    }

    function _normalizeMovescale(r) {
        return {
            direction: slideDirection(r.direction !== undefined ? r.direction : "left"),
            distance: clampNum(r.distance !== undefined ? r.distance : 200, 200, 0, 2000),
            scale: clampNum(r.scale !== undefined ? r.scale : 0, 0, 0, 150)
        };
    }

    function _normalizeType(r) {
        return {
            unit: typeUnit(r.unit !== undefined ? r.unit : "letters"),
            cps: clampNum(r.cps !== undefined ? r.cps : 20, 20, 1, 120),
            cursor: r.cursor === true
        };
    }

    function maskWipeDirection(v) {
        return v === "right" || v === "up" || v === "down" ? v : "left";
    }

    // Keyframe lists for keyframeable clips: [{t, value:{...},
    // easing:{id,bezier}}]. t is clip-local 0..1, values are canonical
    // per-preset fields (see _normalizeKeyValue). Sorted by t, capped
    // at 32; entries missing t/value drop. One key stores (so the first
    // + press shows a row) but only 2+ drive interpolation; shorter
    // lists read as plain from-to, so old clips without keys never gain
    // them on rebuild.
    function normalizeMaskKeys(r) {
        return normalizeKeysFor("maskWipe", r);
    }

    function normalizeKeysFor(presetId, r) {
        var raw = r && r.keys;
        if (!raw || typeof raw.length !== "number" || raw.length < 1)
            return undefined;
        var out = [];
        for (var i = 0; i < raw.length && out.length < 32; i++) {
            var k = raw[i] || {};
            var t = Number(k.t);
            if (isNaN(t))
                continue;
            t = Math.min(1, Math.max(0, t));
            var v = presets._normalizeKeyValue(presetId, k.value || {});
            if (!v)
                continue;
            var ez = k.easing || {};
            out.push({
                t: Math.round(t * 1000) / 1000,
                value: v,
                easing: {
                    id: typeof ez.id === "string" && ez.id !== "" ? ez.id : "easeOut",
                    bezier: ez.bezier
                }
            });
        }
        if (out.length < 1)
            return undefined;
        out.sort((a, b) => a.t - b.t);
        return out;
    }

    function _keyNum(v, fallback, lo, hi) {
        if (v === undefined)
            return undefined;
        var n = Number(v);
        if (isNaN(n))
            return fallback;
        return Math.min(hi, Math.max(lo, n));
    }

    // Per-preset canonical key value. Only known fields survive; partial
    // values are fine (missing fields fall back at sample time). Returns
    // null when nothing usable was stored.
    function _normalizeKeyValue(presetId, v) {
        var o = {};
        var n = 0;
        function put(k, val) {
            if (val !== undefined) {
                o[k] = val;
                n++;
            }
        }
        if (presetId === "maskWipe" || presetId === "maskIris") {
            put("x", _keyNum(v.x, 0, -4000, 4000));
            put("y", _keyNum(v.y, 0, -4000, 4000));
            put("w", v.w !== undefined ? clampNum(v.w, 10, 0.01, 4000) : undefined);
            put("h", v.h !== undefined ? clampNum(v.h, 10, 0.01, 4000) : undefined);
            put("rotation", _keyNum(v.rotation, 0, -1440, 1440));
            put("opacity", v.opacity !== undefined ? normalizeOpacity(v.opacity, 1) : undefined);
            put("feather", v.feather !== undefined ? clampNum(v.feather, 0, 0, 100) : undefined);
            if (v.invert !== undefined) {
                o.invert = v.invert === true;
                n++;
            }
        } else if (presetId === "customMove") {
            put("dx", _keyNum(v.dx !== undefined ? v.dx : v.x, 0, -2000, 2000));
            put("dy", _keyNum(v.dy !== undefined ? v.dy : v.y, 0, -2000, 2000));
            // Accept legacy absolute-style captures storing x/y offsets.
            if (o.dx === undefined && o.dy === undefined)
                return null;
            if (o.dx === undefined) {
                o.dx = 0;
                n++;
            }
            if (o.dy === undefined) {
                o.dy = 0;
                n++;
            }
        } else if (presetId === "customScale") {
            put("s", v.s !== undefined ? clampNum(v.s, 0.001, 0.001, 10) : undefined);
        } else if (presetId === "customRotate") {
            put("r", v.r !== undefined ? clampNum(v.r, 0, -1440, 1440) : undefined);
        } else if (presetId === "customOpacity") {
            put("v", v.v !== undefined ? clampNum(v.v, 0, 0, 1) : undefined);
        } else if (presetId === "customResize") {
            put("w", v.w !== undefined ? clampNum(v.w, 10, 1, 4000) : undefined);
            put("h", v.h !== undefined ? clampNum(v.h, 10, 1, 4000) : undefined);
        } else if (presetId === "customCorner" || presetId === "customFontSize") {
            put("v", v.v !== undefined ? clampNum(v.v, 0, presetId === "customFontSize" ? 1 : 0, presetId === "customFontSize" ? 500 : 500) : undefined);
        } else if (presetId === "customColor" || presetId === "customStrokeColor") {
            if (v.color !== undefined)
                put("color", normalizeHex(v.color, "#000000"));
            put("opacity", v.opacity !== undefined ? normalizeOpacity(v.opacity, 1) : undefined);
        } else if (presetId === "customGradient" || presetId === "customStrokeGradient") {
            if (v.c1 !== undefined)
                put("c1", normalizeHex(v.c1, "#000000"));
            if (v.c2 !== undefined)
                put("c2", normalizeHex(v.c2, "#ffffff"));
            put("angle", v.angle !== undefined ? clampNum(v.angle, 90, 0, 360) : undefined);
            put("opacity", v.opacity !== undefined ? normalizeOpacity(v.opacity, 1) : undefined);
            if (presetId === "customStrokeGradient") {
                put("width", v.width !== undefined ? clampNum(v.width, 0, 0, 100) : undefined);
                put("dash", v.dash !== undefined ? clampNum(v.dash, 0, 0, 100) : undefined);
                put("gap", v.gap !== undefined ? clampNum(v.gap, 0, 0, 100) : undefined);
                if (v.position !== undefined)
                    put("position", normalizeStrokePosition(v.position));
            }
        } else if (presetId === "customStroke") {
            put("width", v.width !== undefined ? clampNum(v.width, 0, 0, 100) : undefined);
            put("opacity", v.opacity !== undefined ? normalizeOpacity(v.opacity, 1) : undefined);
            put("dash", v.dash !== undefined ? clampNum(v.dash, 0, 0, 100) : undefined);
            put("gap", v.gap !== undefined ? clampNum(v.gap, 0, 0, 100) : undefined);
            if (v.position !== undefined)
                put("position", normalizeStrokePosition(v.position));
        } else if (presetId === "customShadow" || presetId === "customGlow") {
            if (v.color !== undefined)
                put("color", normalizeHexA(v.color, presetId === "customShadow" ? "#80000000" : "#cc00ffff"));
            if (presetId === "customShadow") {
                put("x", _keyNum(v.x, 0, -500, 500));
                put("y", _keyNum(v.y, 0, -500, 500));
            }
            put("blur", v.blur !== undefined ? clampNum(v.blur, 0, 0, 100) : undefined);
            put("spread", v.spread !== undefined ? clampNum(v.spread, 0, 0, 50) : undefined);
            if (v.inner !== undefined) {
                o.inner = v.inner === true;
                n++;
            }
        } else if (presetId === "customLayerBlur" || presetId === "customBackgroundBlur") {
            put("radius", v.radius !== undefined ? clampNum(v.radius, 0, 0, 100) : undefined);
            put("opacity", v.opacity !== undefined ? normalizeOpacity(v.opacity, 1) : undefined);
        } else if (presetId === "customGrain") {
            put("amount", v.amount !== undefined ? clampNum(v.amount, 0, 0, 1) : undefined);
            put("size", v.size !== undefined ? clampNum(v.size, 2, 1, 10) : undefined);
        } else {
            return null;
        }
        return n > 0 ? o : null;
    }

    function _withKeys(presetId, o, r) {
        if (!isKeyframeable(presetId))
            return o;
        var keys = normalizeKeysFor(presetId, r);
        if (keys !== undefined)
            o.keys = keys;
        return o;
    }

    function _normalizeMaskWipe(r) {
        var o = {
            direction: maskWipeDirection(r.direction !== undefined ? r.direction : "left"),
            feather: clampNum(r.feather !== undefined ? r.feather : 0, 0, 0, 100),
            invert: r.invert === true
        };
        return _withKeys("maskWipe", o, r);
    }

    function _normalizeMaskIris(r) {
        var o = {
            feather: clampNum(r.feather !== undefined ? r.feather : 0, 0, 0, 100),
            invert: r.invert === true
        };
        return _withKeys("maskIris", o, r);
    }

    function _normalizeCustomScale(r) {
        var o = {
            from: clampNum(r.from !== undefined ? r.from : 0, 0, 0, 10),
            to: clampNum(r.to !== undefined ? r.to : 1, 1, 0, 10)
        };
        return _withKeys("customScale", o, r);
    }

    function _normalizeCustomRotate(r) {
        var o = {
            from: clampNum(r.from !== undefined ? r.from : 0, 0, -1440, 1440),
            to: clampNum(r.to !== undefined ? r.to : 90, 90, -1440, 1440)
        };
        return _withKeys("customRotate", o, r);
    }

    function _normalizeCustomMove(r) {
        var o = {
            fromX: clampNum(r.fromX !== undefined ? r.fromX : 0, 0, -2000, 2000),
            fromY: clampNum(r.fromY !== undefined ? r.fromY : 0, 0, -2000, 2000),
            toX: clampNum(r.toX !== undefined ? r.toX : 200, 200, -2000, 2000),
            toY: clampNum(r.toY !== undefined ? r.toY : 0, 0, -2000, 2000)
        };
        return _withKeys("customMove", o, r);
    }

    function _normalizeCustomOpacity(r) {
        var o = {
            from: clampNum(r.from !== undefined ? r.from : 0, 0, 0, 1),
            to: clampNum(r.to !== undefined ? r.to : 1, 1, 0, 1)
        };
        return _withKeys("customOpacity", o, r);
    }

    function _normalizeCustomColor(r) {
        var co = {
            from: normalizeHex(r.from !== undefined ? r.from : "#000000", "#000000"),
            to: normalizeHex(r.to !== undefined ? r.to : "#ff0000", "#ff0000")
        };
        if (r.fromOpacity !== undefined || r.toOpacity !== undefined) {
            co.fromOpacity = normalizeOpacity(r.fromOpacity !== undefined ? r.fromOpacity : 1, 1);
            co.toOpacity = normalizeOpacity(r.toOpacity !== undefined ? r.toOpacity : 1, 1);
        }
        if (r.fillIndex !== undefined)
            co.fillIndex = normalizeEntryIndex(r.fillIndex);
        return _withKeys("customColor", co, r);
    }

    function _normalizeCustomGradient(r) {
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
        return _withKeys("customGradient", cg, r);
    }

    function _normalizeCustomHide(r) {
        return {
            fromVisible: r.fromVisible === undefined ? true : !!r.fromVisible,
            toVisible: r.toVisible === undefined ? false : !!r.toVisible
        };
    }

    function _normalizeCustomResize(r) {
        var o = {
            fromW: clampNum(r.fromW !== undefined ? r.fromW : 100, 100, 1, 4000),
            fromH: clampNum(r.fromH !== undefined ? r.fromH : 100, 100, 1, 4000),
            toW: clampNum(r.toW !== undefined ? r.toW : 200, 200, 1, 4000),
            toH: clampNum(r.toH !== undefined ? r.toH : 200, 200, 1, 4000)
        };
        return _withKeys("customResize", o, r);
    }

    function _normalizeCustomCorner(r) {
        var o = {
            from: clampNum(r.from !== undefined ? r.from : 0, 0, 0, 500),
            to: clampNum(r.to !== undefined ? r.to : 24, 24, 0, 500)
        };
        return _withKeys("customCorner", o, r);
    }

    function _normalizeCustomStroke(r) {
        var cs = {
            from: clampNum(r.from !== undefined ? r.from : 0, 0, 0, 100),
            to: clampNum(r.to !== undefined ? r.to : 4, 4, 0, 100)
        };
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
        return _withKeys("customStroke", cs, r);
    }

    function _normalizeCustomStrokeColor(r) {
        var cc = {
            from: normalizeHex(r.from !== undefined ? r.from : "#000000", "#000000"),
            to: normalizeHex(r.to !== undefined ? r.to : "#ff0000", "#ff0000")
        };
        if (r.fromOpacity !== undefined || r.toOpacity !== undefined) {
            cc.fromOpacity = normalizeOpacity(r.fromOpacity !== undefined ? r.fromOpacity : 1, 1);
            cc.toOpacity = normalizeOpacity(r.toOpacity !== undefined ? r.toOpacity : 1, 1);
        }
        if (r.strokeIndex !== undefined)
            cc.strokeIndex = normalizeEntryIndex(r.strokeIndex);
        return _withKeys("customStrokeColor", cc, r);
    }

    function _normalizeCustomStrokeGradient(r) {
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
        return _withKeys("customStrokeGradient", sg, r);
    }

    function _normalizeCustomFontSize(r) {
        var o = {
            from: clampNum(r.from !== undefined ? r.from : 16, 16, 1, 500),
            to: clampNum(r.to !== undefined ? r.to : 32, 32, 1, 500)
        };
        return _withKeys("customFontSize", o, r);
    }

    function _normalizeCustomFlip(r) {
        return {
            axis: r.axis === "v" ? "v" : "h"
        };
    }

    function _normalizeCustomShadow(r) {
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
        return _withKeys("customShadow", sh, r);
    }

    function _normalizeCustomLayerBlur(r) {
        var o = {
            fromRadius: clampNum(r.fromRadius !== undefined ? r.fromRadius : 0, 0, 0, 100),
            toRadius: clampNum(r.toRadius !== undefined ? r.toRadius : 12, 12, 0, 100),
            fromOpacity: clampNum(r.fromOpacity !== undefined ? r.fromOpacity : 1, 1, 0, 1),
            toOpacity: clampNum(r.toOpacity !== undefined ? r.toOpacity : 1, 1, 0, 1)
        };
        return _withKeys("customLayerBlur", o, r);
    }

    function _normalizeCustomBackgroundBlur(r) {
        var o = {
            fromRadius: clampNum(r.fromRadius !== undefined ? r.fromRadius : 0, 0, 0, 100),
            toRadius: clampNum(r.toRadius !== undefined ? r.toRadius : 16, 16, 0, 100),
            fromOpacity: clampNum(r.fromOpacity !== undefined ? r.fromOpacity : 0.7, 0.7, 0, 1),
            toOpacity: clampNum(r.toOpacity !== undefined ? r.toOpacity : 0.7, 0.7, 0, 1)
        };
        return _withKeys("customBackgroundBlur", o, r);
    }

    function _normalizeCustomGlow(r) {
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
        return _withKeys("customGlow", gl, r);
    }

    function _normalizeCustomGrain(r) {
        var o = {
            fromAmount: clampNum(r.fromAmount !== undefined ? r.fromAmount : 0, 0, 0, 1),
            toAmount: clampNum(r.toAmount !== undefined ? r.toAmount : 0.5, 0.5, 0, 1),
            fromSize: clampNum(r.fromSize !== undefined ? r.fromSize : 2, 2, 1, 10),
            toSize: clampNum(r.toSize !== undefined ? r.toSize : 2, 2, 1, 10)
        };
        return _withKeys("customGrain", o, r);
    }

    function _normalizeCustomPath(r) {
        return {
            pts: normalizePathPts(r.pts),
            closed: r.closed === true,
            orient: r.orient === true
        };
    }

    function normalizeMode(mode) {
        return mode === "out" ? "out" : "in";
    }

    // Clip loop lives top-level on the clip (not in options) so option
    // rebuilds never drop it; old scenes miss it and read none.
    function normalizeLoop(loop) {
        return loop === "loop" || loop === "pingpong" ? loop : "none";
    }

    // Bezier values are CSS-equivalent handles for display and dragging;
    // the sampler keeps exact cubics for the named ids, bezier for custom.
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
        // Clips never stage past the composition end; stepped clips lock
        // to the 0.1s floor so the switch reads as one keyframe at t0.
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
