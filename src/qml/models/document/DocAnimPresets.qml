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
            }
        ];
    }

    function presetIds() {
        return ["appear", "fade", "slide", "grow", "shrink", "spin", "twist", "movescale", "customScale", "customRotate", "customMove", "customOpacity", "customColor", "customHide", "customResize", "customCorner", "customStroke", "customPath"];
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
        if (presetId === "customHide")
            return qsTr("Hide / Show");
        if (presetId === "customResize")
            return qsTr("Resize");
        if (presetId === "customCorner")
            return qsTr("Corner Radius");
        if (presetId === "customStroke")
            return qsTr("Stroke");
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
                to: "#ff0000"
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
                to: 4
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

    function clampNum(v, fallback, lo, hi) {
        var n = Number(v);
        if (isNaN(n))
            return fallback;
        return Math.min(hi, Math.max(lo, n));
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
        if (presetId === "customColor")
            return {
                from: normalizeHex(r.from !== undefined ? r.from : "#000000", "#000000"),
                to: normalizeHex(r.to !== undefined ? r.to : "#ff0000", "#ff0000")
            };
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
        if (presetId === "customStroke")
            return {
                from: clampNum(r.from !== undefined ? r.from : 0, 0, 0, 100),
                to: clampNum(r.to !== undefined ? r.to : 4, 4, 0, 100)
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

    function buildClip(presetId, clipId, targetUid, t0, duration, mode, options, easing) {
        var ez = easing || {};
        var ct0 = Math.max(0, Number(t0) || 0);
        // Clips never stage past the composition end (applying near the
        // tail yields a shorter clip, never an overhanging one).
        var comp = presets.doc && presets.doc.anim ? presets.doc.anim.duration : 60;
        var cd = Math.min(60, Math.max(0.1, Number(duration) || 0.8));
        cd = Math.min(cd, Math.max(0.1, comp - ct0));
        return {
            id: clipId,
            targetUid: targetUid,
            preset: presetId,
            t0: ct0,
            duration: cd,
            mode: normalizeMode(mode),
            options: normalizeOptions(presetId, options),
            easing: {
                id: typeof ez.id === "string" && ez.id !== "" ? ez.id : defaultEasingFor(presetId),
                bezier: ez.bezier
            }
        };
    }
}
