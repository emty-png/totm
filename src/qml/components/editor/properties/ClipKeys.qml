import QtQuick
import QtQuick.Layouts
import Totm

// Generic keyframe rows for keyframeable clips (basic fade/slide/
// scale/spin/type, custom from-to clips plus mask reveals). Keys hold canonical per-preset values at
// clip-local t, so moving the target later leaves existing keys where
// they were. One key stores but only 2+ drive interpolation; shorter
// lists read as plain from-to, so old clips never change behavior.
// Commits flow through DocAnim (undoable).
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    // Key-graph opener (provided by the clip editor): opens the shared
    // Animation-type popup scoped to one stored key.
    property var graphKeyPolicy: null

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property string preset: section.clip ? String(section.clip.preset || "") : ""
    readonly property var keyList: section.copyKeys(section.clip ? section.clip.options || {} : {})

    spacing: 8

    Repeater {
        model: section.keyList

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: qsTr("%1% · %2").arg(Math.round(Number(modelData.t || 0) * 100)).arg(section.keySummary(section.preset, modelData.value || {}))
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    color: AppTheme.foreground
                }

                PanelIconButton {
                    iconKind: "close"
                    filled: false
                    iconSize: 12
                    onClicked: section.deleteKey(index)
                }
            }

            PanelDropdown {
                Layout.fillWidth: true
                options: section.easingOptions()
                currentId: String((modelData.easing || {}).id || "easeOut")
                onPicked: id => section.pickKeyEasing(index, id)
            }

            // Hold steps instead of easing and labels itself; the first
            // key opens no span, so only later Hold keys label.
            Text {
                Layout.fillWidth: true
                visible: index > 0 && String((modelData.easing || {}).id || "easeOut") === "hold"
                text: qsTr("Hold — keeps the previous value, steps at the next key")
                font.pixelSize: 11
                elide: Text.ElideRight
                color: AppTheme.muted
            }
        }
    }

    function copyKeys(opts) {
        var src = (opts || {}).keys;
        var out = [];
        if (!src || typeof src.length !== "number")
            return out;
        for (var i = 0; i < src.length; i++) {
            var k = src[i] || {};
            out.push({
                t: k.t,
                value: k.value || {},
                easing: k.easing || {}
            });
        }
        return out;
    }

    function round2(v) {
        return Math.round(Number(v) * 100) / 100;
    }

    // Lightweight per-key value preview so keys stay distinguishable.
    // Reads canonical fields only; unknown shapes fall back to "key".
    function keySummary(preset, v) {
        if (preset === "maskWipe" || preset === "maskIris") {
            var parts = [];
            if (v.x !== undefined || v.w !== undefined)
                parts.push(qsTr("box"));
            if (v.rotation !== undefined)
                parts.push(qsTr("rot"));
            if (v.opacity !== undefined)
                parts.push(qsTr("op"));
            if (v.feather !== undefined)
                parts.push(qsTr("feather"));
            if (v.invert !== undefined)
                parts.push(qsTr("inv"));
            return parts.length > 0 ? parts.join(" ") : qsTr("key");
        }
        if (preset === "fade")
            return qsTr("op %1").arg(section.round2(v.v));
        if (preset === "slide") {
            var s = qsTr("dx %1 dy %2").arg(section.round2(v.dx)).arg(section.round2(v.dy));
            if (v.v !== undefined)
                s += qsTr(" op %1").arg(section.round2(v.v));
            return s;
        }
        if (preset === "grow" || preset === "shrink" || preset === "customScale")
            return qsTr("× %1").arg(section.round2(v.s));
        if (preset === "spin" || preset === "customRotate")
            return qsTr("%1°").arg(section.round2(v.r));
        if (preset === "movescale") {
            var m = qsTr("dx %1 dy %2 × %3").arg(section.round2(v.dx)).arg(section.round2(v.dy)).arg(section.round2(v.s));
            if (v.v !== undefined)
                m += qsTr(" op %1").arg(section.round2(v.v));
            return m;
        }
        if (preset === "type")
            return qsTr("%1%").arg(Math.round(Number(v.frac || 0) * 100));
        if (preset === "customHide")
            return v.v === true ? qsTr("visible") : qsTr("hidden");
        if (preset === "customFlip")
            return (v.v === true ? qsTr("flipped") : qsTr("normal")) + (v.axis ? " " + String(v.axis) : "");
        if (preset === "customMove")
            return qsTr("dx %1 dy %2").arg(section.round2(v.dx !== undefined ? v.dx : v.x)).arg(section.round2(v.dy !== undefined ? v.dy : v.y));
        if (preset === "customOpacity")
            return qsTr("op %1").arg(section.round2(v.v));
        if (preset === "customResize")
            return qsTr("%1 × %2").arg(Math.round(Number(v.w) || 0)).arg(Math.round(Number(v.h) || 0));
        if (preset === "customCorner")
            return qsTr("%1px").arg(section.round2(v.v));
        if (preset === "customFontSize")
            return qsTr("%1px").arg(section.round2(v.v));
        if (preset === "customFontWeight")
            return qsTr("w%1").arg(Math.min(1000, Math.max(1, Math.round(Number(v.v) || 400))));
        if (preset === "customColor" || preset === "customStrokeColor")
            return String(v.color || qsTr("key"));
        if (preset === "customGradient" || preset === "customStrokeGradient")
            return qsTr("%1 → %2").arg(String(v.c1 || "?")).arg(String(v.c2 || "?"));
        if (preset === "customStroke")
            return qsTr("%1px").arg(section.round2(v.width));
        if (preset === "customShadow")
            return qsTr("%1 %2,%3").arg(String(v.color || qsTr("shadow"))).arg(section.round2(v.x)).arg(section.round2(v.y));
        if (preset === "customGlow")
            return qsTr("%1 b%2").arg(String(v.color || qsTr("glow"))).arg(section.round2(v.blur));
        if (preset === "customLayerBlur" || preset === "customBackgroundBlur")
            return qsTr("r%1").arg(section.round2(v.radius));
        if (preset === "customGrain")
            return qsTr("a%1").arg(section.round2(v.amount));
        return qsTr("key");
    }

    // Captures the live look at the playhead on this clip (shared
    // DocAnim path, undoable). Replaces any key within 1% of the
    // same t.
    function addKey() {
        if (!section.doc)
            return;
        section.doc.anim.addKeyAtPlayhead(section.clipId);
    }

    function deleteKey(index) {
        var cur = section.keyList;
        var kept = [];
        for (var i = 0; i < cur.length; i++) {
            if (i === index)
                continue;
            kept.push({
                t: cur[i].t,
                value: JSON.parse(JSON.stringify(cur[i].value || {})),
                easing: section.copyEasing(cur[i].easing)
            });
        }
        section.setKeys(kept);
    }

    // Easing deep-copy for key rebuilds: custom handles survive deletes
    // and dropdown edits instead of resetting to the named default.
    function copyEasing(ez) {
        var e = ez || {};
        return {
            id: e.id || "easeOut",
            bezier: e.bezier ? e.bezier.slice() : e.bezier
        };
    }

    // Named easing presets for the per-key dropdowns (bezier rides
    // along untouched; the samplers use exact curves for named ids):
    // Hold freezes the segment, Custom opens the graph popup so the
    // user draws the curve there instead of an inline strip.
    function easingOptions() {
        if (!section.doc)
            return [];
        var opts = section.doc.anim.presets.easingPresets().slice();
        opts.push({
            id: "hold",
            name: qsTr("Hold")
        });
        opts.push({
            id: "custom",
            name: qsTr("Custom")
        });
        return opts;
    }

    // Shared Animation-type popup scoped to one stored key
    // (dropdown picks and handle drags land on the key's easing).
    function openKeyGraph(index) {
        if (section.graphKeyPolicy)
            section.graphKeyPolicy(index);
    }

    // Dropdown pick: Custom stores the custom id and opens the shared
    // Animation-type popup scoped to the key; every other pick commits
    // in place like before.
    function pickKeyEasing(index, id) {
        section.setKeyEasing(index, id);
        if (String(id || "") === "custom")
            section.openKeyGraph(index);
    }

    function setKeyEasing(index, id) {
        var cur = section.keyList;
        if (index < 0 || index >= cur.length)
            return;
        var kept = [];
        for (var i = 0; i < cur.length; i++) {
            var keptEasing = section.copyEasing(cur[i].easing);
            if (i === index)
                keptEasing.id = String(id || "easeOut");
            kept.push({
                t: cur[i].t,
                value: JSON.parse(JSON.stringify(cur[i].value || {})),
                easing: keptEasing
            });
        }
        section.setKeys(kept);
    }

    function setKeys(keys) {
        if (!section.doc)
            return;
        section.doc.setClipOptions(section.clipId, {
            keys: keys
        });
    }
}
