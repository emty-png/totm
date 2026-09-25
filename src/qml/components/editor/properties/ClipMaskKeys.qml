import QtQuick
import QtQuick.Layouts
import Totm

// Mask keyframe rows for the Keyframes panel section (the header plus
// its add button live on the section itself). Keys hold absolute mask
// geometry at clip-local t, so moving the mask later leaves existing
// keys where they were. Commits flow through DocAnim (undoable).
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
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
                    text: qsTr("%1% · %2").arg(Math.round(Number(modelData.t || 0) * 100)).arg(section.keySummary(modelData.value || {}))
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
                onPicked: id => section.setKeyEasing(index, id)
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

    function keySummary(v) {
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

    // Captures the live mask box at the playhead (sampled frame while
    // previewing, base otherwise) as an absolute key. Replaces any key
    // within 1% of the same t.
    function addKey() {
        var c = section.clip;
        if (!c || !section.doc)
            return;
        var n = section.doc.findNode(c.targetUid);
        if (!n || n.kind !== "shape")
            return;
        var t = (section.doc.anim.currentTime - c.t0) / Math.max(0.001, c.duration);
        t = Math.round(Math.min(1, Math.max(0, t)) * 1000) / 1000;
        var kept = [];
        var cur = section.keyList;
        for (var i = 0; i < cur.length; i++) {
            if (Math.abs(Number(cur[i].t) - t) > 0.01)
                kept.push({
                    t: cur[i].t,
                    value: JSON.parse(JSON.stringify(cur[i].value || {})),
                    easing: {
                        id: (cur[i].easing || {}).id || "easeOut"
                    }
                });
        }
        kept.push({
            t: t,
            value: {
                x: Math.round(Number(n.x) * 100) / 100,
                y: Math.round(Number(n.y) * 100) / 100,
                w: Math.max(0.01, Math.round(Number(n.w) * 100) / 100),
                h: Math.max(0.01, Math.round(Number(n.h) * 100) / 100),
                rotation: Math.round(Number(n.rotation) * 100) / 100,
                opacity: Math.min(1, Math.max(0, Number(n.opacity))),
                feather: Math.max(0, Number(n.maskFeather) || 0),
                invert: n.maskInverted === true
            },
            easing: {
                id: "easeOut"
            }
        });
        section.setKeys(kept);
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
                easing: {
                    id: (cur[i].easing || {}).id || "easeOut"
                }
            });
        }
        section.setKeys(kept);
    }

    // Named easing presets for the per-key dropdowns (bezier rides
    // along untouched; the samplers use exact curves for named ids).
    function easingOptions() {
        if (!section.doc)
            return [];
        return section.doc.anim.presets.easingPresets();
    }

    function setKeyEasing(index, id) {
        var cur = section.keyList;
        if (index < 0 || index >= cur.length)
            return;
        var kept = [];
        for (var i = 0; i < cur.length; i++) {
            kept.push({
                t: cur[i].t,
                value: JSON.parse(JSON.stringify(cur[i].value || {})),
                easing: {
                    id: i === index ? String(id || "easeOut") : ((cur[i].easing || {}).id || "easeOut")
                }
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
