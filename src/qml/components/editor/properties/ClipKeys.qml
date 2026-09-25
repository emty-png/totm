import QtQuick
import QtQuick.Layouts
import Totm

// Generic keyframe rows for keyframeable clips (custom from-to clips
// plus mask reveals). Keys hold canonical per-preset values at
// clip-local t, so moving the target later leaves existing keys where
// they were. One key stores but only 2+ drive interpolation; shorter
// lists read as plain from-to, so old clips never change behavior.
// Commits flow through DocAnim (undoable).
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

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

    function round2(v) {
        return Math.round(Number(v) * 100) / 100;
    }

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
        if (preset === "customMove")
            return qsTr("dx %1 dy %2").arg(section.round2(v.dx !== undefined ? v.dx : v.x)).arg(section.round2(v.dy !== undefined ? v.dy : v.y));
        if (preset === "customScale")
            return qsTr("× %1").arg(section.round2(v.s));
        if (preset === "customRotate")
            return qsTr("%1°").arg(section.round2(v.r));
        if (preset === "customOpacity")
            return qsTr("op %1").arg(section.round2(v.v));
        if (preset === "customResize")
            return qsTr("%1 × %2").arg(Math.round(Number(v.w) || 0)).arg(Math.round(Number(v.h) || 0));
        if (preset === "customCorner")
            return qsTr("%1px").arg(section.round2(v.v));
        if (preset === "customFontSize")
            return qsTr("%1px").arg(section.round2(v.v));
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

    // First shape leaf under the clip target (groups animate per leaf;
    // keys capture the first leaf so group clips still record).
    function targetLeaf() {
        if (!section.doc || !section.clip)
            return null;
        var n = section.doc.findNode(section.clip.targetUid);
        if (!n)
            return null;
        if (n.kind === "shape")
            return n;
        var leaves = section.doc._leavesUnder(n);
        return leaves.length > 0 ? leaves[0] : null;
    }

    function baseFor(leaf) {
        if (!leaf)
            return null;
        var pb = section.doc && section.doc.anim ? section.doc.anim.playBase : null;
        if (pb && pb[leaf.uid])
            return pb[leaf.uid];
        return leaf;
    }

    function stackEntry(list, idx) {
        var arr = list || [];
        var i = Math.min(32, Math.max(0, Math.round(Number(idx) || 0)));
        return i < arr.length ? (arr[i] ?? {}) : {};
    }

    // Captures the live look at the playhead (sampled frame while
    // previewing, base otherwise) as a canonical key value. Replaces
    // any key within 1% of the same t.
    function addKey() {
        var c = section.clip;
        if (!c || !section.doc)
            return;
        if (!section.doc.anim.presets.isKeyframeable(section.preset))
            return;
        var leaf = section.targetLeaf();
        if (!leaf)
            return;
        var t = (section.doc.anim.currentTime - c.t0) / Math.max(0.001, c.duration);
        t = Math.round(Math.min(1, Math.max(0, t)) * 1000) / 1000;
        var v = section.captureValue(section.preset, leaf, c.options || {});
        if (!v)
            return;
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
            value: v,
            easing: {
                id: "easeOut"
            }
        });
        section.setKeys(kept);
    }

    function captureValue(preset, leaf, opts) {
        var base = section.baseFor(leaf);
        if (!base)
            return null;
        if (preset === "maskWipe" || preset === "maskIris") {
            return {
                x: section.round2(leaf.x),
                y: section.round2(leaf.y),
                w: Math.max(0.01, section.round2(leaf.w)),
                h: Math.max(0.01, section.round2(leaf.h)),
                rotation: section.round2(leaf.rotation),
                opacity: Math.min(1, Math.max(0, Number(leaf.opacity))),
                feather: Math.max(0, Number(leaf.maskFeather) || 0),
                invert: leaf.maskInverted === true
            };
        }
        if (preset === "customMove") {
            return {
                dx: section.round2((Number(leaf.x) || 0) - (Number(base.x) || 0)),
                dy: section.round2((Number(leaf.y) || 0) - (Number(base.y) || 0))
            };
        }
        if (preset === "customScale") {
            var bw = Number(base.w) || 0, lw = Number(leaf.w) || 0;
            var bh = Number(base.h) || 0, lh = Number(leaf.h) || 0;
            var s = bw > 0.001 ? lw / bw : (bh > 0.001 ? lh / bh : 1);
            return {
                s: Math.min(10, Math.max(0.001, section.round2(s)))
            };
        }
        if (preset === "customRotate") {
            return {
                r: section.round2((Number(leaf.rotation) || 0) - (Number(base.rotation) || 0))
            };
        }
        if (preset === "customOpacity") {
            return {
                v: Math.min(1, Math.max(0, Number(leaf.opacity)))
            };
        }
        if (preset === "customResize") {
            return {
                w: Math.max(1, Math.round(Number(leaf.w) || 1)),
                h: Math.max(1, Math.round(Number(leaf.h) || 1))
            };
        }
        if (preset === "customCorner") {
            return {
                v: Math.max(0, section.round2(leaf.radius))
            };
        }
        if (preset === "customFontSize") {
            return {
                v: Math.min(500, Math.max(1, Math.round(Number(leaf.fontSize) || 16)))
            };
        }
        if (preset === "customColor") {
            var fi = Number(opts.fillIndex) || 0;
            var fe = section.stackEntry(leaf.fills, fi);
            return {
                color: String(fe.color ?? leaf.fill ?? "#000000"),
                opacity: Math.min(1, Math.max(0, Number(fe.opacity ?? 1)))
            };
        }
        if (preset === "customGradient") {
            var gi = Number(opts.fillIndex) || 0;
            var ge = section.stackEntry(leaf.fills, gi);
            var gg = ge.gradient ?? {};
            var stops = gg.stops ?? [];
            return {
                c1: String((stops[0] ?? {}).color ?? "#000000"),
                c2: String((stops[1] ?? {}).color ?? "#ffffff"),
                angle: section.round2(gg.angle ?? 90),
                opacity: Math.min(1, Math.max(0, Number(ge.opacity ?? 1)))
            };
        }
        if (preset === "customStroke") {
            var si = Number(opts.strokeIndex) || 0;
            var se = section.stackEntry(leaf.strokes, si);
            var dash = (se.dash && typeof se.dash.length === "number") ? se.dash : [];
            return {
                width: Math.max(0, section.round2(se.width ?? 0)),
                opacity: Math.min(1, Math.max(0, Number(se.opacity ?? 1))),
                dash: Math.max(0, section.round2(dash.length > 0 ? dash[0] : 0)),
                gap: Math.max(0, section.round2(dash.length > 1 ? dash[1] : 0)),
                position: (se.position === "inside" || se.position === "outside") ? se.position : "center"
            };
        }
        if (preset === "customStrokeColor") {
            var sci = Number(opts.strokeIndex) || 0;
            var sce = section.stackEntry(leaf.strokes, sci);
            return {
                color: String(sce.color ?? leaf.stroke ?? "#000000"),
                opacity: Math.min(1, Math.max(0, Number(sce.opacity ?? 1)))
            };
        }
        if (preset === "customStrokeGradient") {
            var sgi = Number(opts.strokeIndex) || 0;
            var sge = section.stackEntry(leaf.strokes, sgi);
            var sgg = sge.gradient ?? {};
            var sstops = sgg.stops ?? [];
            var sdash = (sge.dash && typeof sge.dash.length === "number") ? sge.dash : [];
            return {
                c1: String((sstops[0] ?? {}).color ?? "#000000"),
                c2: String((sstops[1] ?? {}).color ?? "#ffffff"),
                angle: section.round2(sgg.angle ?? 90),
                opacity: Math.min(1, Math.max(0, Number(sge.opacity ?? 1))),
                width: Math.max(0, section.round2(sge.width ?? 0)),
                dash: Math.max(0, section.round2(sdash.length > 0 ? sdash[0] : 0)),
                gap: Math.max(0, section.round2(sdash.length > 1 ? sdash[1] : 0)),
                position: (sge.position === "inside" || sge.position === "outside") ? sge.position : "center"
            };
        }
        if (preset === "customShadow") {
            var shi = Number(opts.shadowIndex) || 0;
            var she = section.stackEntry(leaf.shadows, shi);
            return {
                color: String(she.color ?? "#80000000"),
                x: section.round2(she.x ?? 0),
                y: section.round2(she.y ?? 4),
                blur: Math.max(0, section.round2(she.blur ?? 8)),
                spread: Math.max(0, section.round2(she.spread ?? 0)),
                inner: she.inner === true
            };
        }
        if (preset === "customGlow") {
            var gli = Number(opts.glowIndex) || 0;
            var gle = section.stackEntry(leaf.glows, gli);
            return {
                color: String(gle.color ?? "#cc00ffff"),
                blur: Math.max(0, section.round2(gle.blur ?? 16)),
                spread: Math.max(0, section.round2(gle.spread ?? 4)),
                inner: gle.inner === true
            };
        }
        if (preset === "customLayerBlur" || preset === "customBackgroundBlur") {
            var b = preset === "customLayerBlur" ? (leaf.layerBlur ?? {}) : (leaf.backgroundBlur ?? {});
            return {
                radius: Math.max(0, section.round2(b.radius ?? 0)),
                opacity: Math.min(1, Math.max(0, Number(b.opacity ?? (preset === "customLayerBlur" ? 1 : 0.7))))
            };
        }
        if (preset === "customGrain") {
            var gn = leaf.grain ?? {};
            return {
                amount: Math.min(1, Math.max(0, Number(gn.amount ?? 0))),
                size: Math.min(10, Math.max(1, section.round2(gn.size ?? 2)))
            };
        }
        return null;
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
