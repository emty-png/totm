import QtQuick

// Preset catalog and clip builders for one Document's animation.
// Builders capture nothing but explicit params: the sampler derives
// every frame from clip plus live tree, so clips stay valid when nodes
// move after being applied. Owned by DocAnim, which assigns clip ids.
QtObject {
    id: presets
    required property var doc

    function catalog() {
        return [
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
        return ["fade", "slide", "grow", "shrink", "spin", "twist", "movescale"];
    }

    function presetName(presetId) {
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
