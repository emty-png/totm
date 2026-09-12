import QtQuick
import QtQuick.Layouts
import Totm

// Stacked effects: shadows and glows list (index 0 paints topmost),
// blurs and grain are singletons. Fixed render order: backgroundBlur
// (backdrop) -> outer shadows -> outer glows -> fill -> inner shadows
// -> inner glows -> stroke -> layerBlur (whole stack) -> grain on top.
// + opens the picker any time; each card edits live with scrub-
// coalesced undo. Groups never see this section.
PanelSection {
    id: section

    required property var snapshot

    title: qsTr("Effects")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup && section.effectable()
    enabled: !section.snapshot.allLocked
    compact: !section.hasAnyEffect()
    showAdd: true
    showRemove: section.hasAnyEffect()
    onAddClicked: picker.openAt(section)
    onRemoveClicked: section.clearAllEffects()

    property int shadowCount: section.maxShadows()
    property int glowCount: section.maxGlows()
    property var layerCommon: section.collectBlur("layerBlur", 8, 1)
    property var backgroundCommon: section.collectBlur("backgroundBlur", 16, 0.7)
    property var grainCommon: section.collectGrain()
    property int pickerShadowIndex: -1
    property int pickerGlowIndex: -1

    Repeater {
        model: section.shadowCount

        onItemAdded: (at, item) => {
            item.section = section;
            item.entryIndex = at;
        }

        EffectShadowCard {
            Layout.fillWidth: true
        }
    }

    Repeater {
        model: section.glowCount

        onItemAdded: (at, item) => {
            item.section = section;
            item.entryIndex = at;
        }

        EffectGlowCard {
            Layout.fillWidth: true
        }
    }

    ColumnLayout {
        visible: section.layerCommon.value.enabled === true
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: qsTr("Layer Blur")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: AppTheme.foreground
                elide: Text.ElideRight
            }

            PanelIconButton {
                iconKind: "close"
                filled: false
                iconSize: 12
                onClicked: section.removeBlur("layerBlur")
            }
        }

        EffectBlurFields {
            Layout.fillWidth: true
            radiusValue: section.layerCommon.value.radius
            radiusMixed: section.layerCommon.mixedRadius
            opacityValue: section.layerCommon.value.opacity
            opacityMixed: section.layerCommon.mixedOpacity
            onRadiusCommitted: v => section.patchBlur("layerBlur", "radius", v)
            onOpacityCommitted: v => section.patchBlur("layerBlur", "opacity", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    ColumnLayout {
        visible: section.backgroundCommon.value.enabled === true
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: qsTr("Background Blur")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: AppTheme.foreground
                elide: Text.ElideRight
            }

            PanelIconButton {
                iconKind: "close"
                filled: false
                iconSize: 12
                onClicked: section.removeBlur("backgroundBlur")
            }
        }

        EffectBlurFields {
            Layout.fillWidth: true
            radiusValue: section.backgroundCommon.value.radius
            radiusMixed: section.backgroundCommon.mixedRadius
            opacityValue: section.backgroundCommon.value.opacity
            opacityMixed: section.backgroundCommon.mixedOpacity
            onRadiusCommitted: v => section.patchBlur("backgroundBlur", "radius", v)
            onOpacityCommitted: v => section.patchBlur("backgroundBlur", "opacity", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    ColumnLayout {
        visible: section.grainCommon.value.enabled === true
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: qsTr("Grain")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: AppTheme.foreground
                elide: Text.ElideRight
            }

            PanelIconButton {
                iconKind: "close"
                filled: false
                iconSize: 12
                onClicked: section.removeGrain()
            }
        }

        EffectBlurFields {
            Layout.fillWidth: true
            sizePrefix: "S"
            sizeMaximum: 10
            radiusValue: section.grainCommon.value.size
            radiusMixed: section.grainCommon.mixedSize
            opacityValue: section.grainCommon.value.amount
            opacityMixed: section.grainCommon.mixedAmount
            onRadiusCommitted: v => section.patchGrain("size", v)
            onOpacityCommitted: v => section.patchGrain("amount", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    // Every shape kind including text; groups excluded by visible.
    function effectable() {
        var leaves = section.snapshot.selLeaves;
        if (leaves.length === 0)
            return false;
        for (var i = 0; i < leaves.length; i++) {
            var t = leaves[i].type;
            if (t !== "rectangle" && t !== "ellipse" && t !== "triangle" && t !== "star" && t !== "pen" && t !== "image" && t !== "text")
                return false;
        }
        return true;
    }

    function hasText() {
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            if (leaves[i].type === "text")
                return true;
        }
        return false;
    }

    function hasAnyEffect() {
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            var l = leaves[i];
            var sh = l.shadows || [];
            for (var a = 0; a < sh.length; a++) {
                if (sh[a] && sh[a].enabled !== false)
                    return true;
            }
            var gl = l.glows || [];
            for (var b = 0; b < gl.length; b++) {
                if (gl[b] && gl[b].enabled !== false)
                    return true;
            }
            if (l.layerBlur && l.layerBlur.enabled === true)
                return true;
            if (l.backgroundBlur && l.backgroundBlur.enabled === true)
                return true;
            if (l.grain && l.grain.enabled === true)
                return true;
        }
        return false;
    }

    function maxShadows() {
        var leaves = section.snapshot.selLeaves;
        var m = 0;
        for (var i = 0; i < leaves.length; i++) {
            var n = (leaves[i].shadows || []).length;
            if (n > m)
                m = n;
        }
        return m;
    }

    function maxGlows() {
        var leaves = section.snapshot.selLeaves;
        var m = 0;
        for (var i = 0; i < leaves.length; i++) {
            var n = (leaves[i].glows || []).length;
            if (n > m)
                m = n;
        }
        return m;
    }

    // Per-index common shadow (maps never === by ref). Leaves missing
    // the index are skipped: edits apply where the entry exists, adds
    // and removes apply to every leaf.
    function collectShadowAt(at) {
        var leaves = section.snapshot.selLeaves;
        var base = {
            enabled: true,
            inner: false,
            color: "#80000000",
            x: 0,
            y: 4,
            blur: 8,
            spread: 0
        };
        var first = null;
        for (var i = 0; i < leaves.length; i++) {
            var list = leaves[i].shadows || [];
            if (at < list.length) {
                first = list[at];
                break;
            }
        }
        if (!first)
            return {
                value: base,
                mixedColor: true,
                mixedX: true,
                mixedY: true,
                mixedBlur: true,
                mixedSpread: true,
                mixedInner: true
            };
        var mc = false, mx = false, my = false, mb = false, ms = false, mi = false, me = false;
        for (var j = 0; j < leaves.length; j++) {
            var cur = (leaves[j].shadows || [])[at];
            if (!cur)
                continue;
            if (String(cur.color) !== String(first.color))
                mc = true;
            if (Number(cur.x) !== Number(first.x))
                mx = true;
            if (Number(cur.y) !== Number(first.y))
                my = true;
            if (Number(cur.blur) !== Number(first.blur))
                mb = true;
            if (Number(cur.spread) !== Number(first.spread))
                ms = true;
            if ((cur.inner === true) !== (first.inner === true))
                mi = true;
            if ((cur.enabled !== false) !== (first.enabled !== false))
                me = true;
        }
        return {
            value: {
                enabled: first.enabled !== false,
                inner: first.inner === true,
                color: String(first.color ?? "#80000000"),
                x: Number(first.x) || 0,
                y: first.y !== undefined ? (Number(first.y) || 0) : 4,
                blur: first.blur !== undefined ? Math.max(0, Number(first.blur) || 0) : 8,
                spread: first.spread !== undefined ? Math.max(0, Number(first.spread) || 0) : 0
            },
            mixedColor: mc,
            mixedX: mx,
            mixedY: my,
            mixedBlur: mb,
            mixedSpread: ms,
            mixedInner: mi,
            mixedEnabled: me
        };
    }

    function collectGlowAt(at) {
        var leaves = section.snapshot.selLeaves;
        var base = {
            enabled: true,
            inner: false,
            color: "#cc00ffff",
            blur: 16,
            spread: 4
        };
        var first = null;
        for (var i = 0; i < leaves.length; i++) {
            var list = leaves[i].glows || [];
            if (at < list.length) {
                first = list[at];
                break;
            }
        }
        if (!first)
            return {
                value: base,
                mixedColor: true,
                mixedBlur: true,
                mixedSpread: true,
                mixedInner: true
            };
        var mc = false, mb = false, ms = false, mi = false, me = false;
        for (var j = 0; j < leaves.length; j++) {
            var cur = (leaves[j].glows || [])[at];
            if (!cur)
                continue;
            if (String(cur.color) !== String(first.color))
                mc = true;
            if (Number(cur.blur) !== Number(first.blur))
                mb = true;
            if (Number(cur.spread) !== Number(first.spread))
                ms = true;
            if ((cur.inner === true) !== (first.inner === true))
                mi = true;
            if ((cur.enabled !== false) !== (first.enabled !== false))
                me = true;
        }
        return {
            value: {
                enabled: first.enabled !== false,
                inner: first.inner === true,
                color: String(first.color ?? "#cc00ffff"),
                blur: first.blur !== undefined ? Math.max(0, Number(first.blur) || 0) : 16,
                spread: first.spread !== undefined ? Math.max(0, Number(first.spread) || 0) : 4
            },
            mixedColor: mc,
            mixedBlur: mb,
            mixedSpread: ms,
            mixedInner: mi,
            mixedEnabled: me
        };
    }

    // Common blur with mixed flags (radius px, opacity 0..1).
    function collectBlur(role, defRadius, defOpacity) {
        var leaves = section.snapshot.selLeaves;
        var base = {
            enabled: false,
            radius: defRadius,
            opacity: defOpacity
        };
        if (leaves.length === 0) {
            return {
                value: base,
                mixedRadius: true,
                mixedOpacity: true
            };
        }
        var first = leaves[0][role] ?? base;
        var mr = false, mo = false;
        for (var i = 1; i < leaves.length; i++) {
            var s = leaves[i][role] ?? base;
            if (Number(s.radius) !== Number(first.radius))
                mr = true;
            if (Number(s.opacity) !== Number(first.opacity))
                mo = true;
        }
        return {
            value: {
                enabled: first.enabled === true,
                radius: first.radius !== undefined ? Math.max(0, Number(first.radius) || 0) : defRadius,
                opacity: first.opacity !== undefined ? Math.min(1, Math.max(0, Number(first.opacity))) : defOpacity
            },
            mixedRadius: mr,
            mixedOpacity: mo
        };
    }

    // Common grain with mixed flags (amount 0..1, size px).
    function collectGrain() {
        var leaves = section.snapshot.selLeaves;
        var base = {
            enabled: false,
            amount: 0.5,
            size: 2
        };
        if (leaves.length === 0) {
            return {
                value: base,
                mixedAmount: true,
                mixedSize: true
            };
        }
        var first = leaves[0].grain ?? base;
        var ma = false, mz = false;
        for (var i = 1; i < leaves.length; i++) {
            var s = leaves[i].grain ?? base;
            if (Number(s.amount) !== Number(first.amount))
                ma = true;
            if (Number(s.size) !== Number(first.size))
                mz = true;
        }
        return {
            value: {
                enabled: first.enabled === true,
                amount: first.amount !== undefined ? Math.min(1, Math.max(0, Number(first.amount))) : 0.5,
                size: first.size !== undefined ? Math.min(10, Math.max(1, Number(first.size) || 0)) : 2
            },
            mixedAmount: ma,
            mixedSize: mz
        };
    }

    // Shadow color picker: solid only. The pad edits opaque rgb; the
    // row's opacity field owns alpha, so picks keep current alpha.
    ColorPickerPopup {
        id: colorPicker

        onScrubStarted: section.snapshot.beginScrub()
        onCommitted: c => {
            if (section.pickerShadowIndex >= 0)
                section.patchShadowAt(section.pickerShadowIndex, "color", section.withAlpha(String(c), section.alphaOf(section.collectShadowAt(section.pickerShadowIndex).value.color)));
        }
        onScrubFinished: section.snapshot.endScrub()
    }

    // Glow color picker: solid only, alpha owned by the % field like
    // the shadow rows, so picks keep current opacity.
    ColorPickerPopup {
        id: glowPicker

        onScrubStarted: section.snapshot.beginScrub()
        onCommitted: c => {
            if (section.pickerGlowIndex >= 0)
                section.patchGlowAt(section.pickerGlowIndex, "color", section.withAlpha(String(c), section.alphaOf(section.collectGlowAt(section.pickerGlowIndex).value.color)));
        }
        onScrubFinished: section.snapshot.endScrub()
    }

    EffectsPopup {
        id: picker

        textSelected: section.hasText()
        onOuterShadowClicked: section.addShadow(false)
        onInnerShadowClicked: section.addShadow(true)
        onLayerBlurClicked: section.enableBlur("layerBlur")
        onBackgroundBlurClicked: section.enableBlur("backgroundBlur")
        onOuterGlowClicked: section.addGlow(false)
        onInnerGlowClicked: section.addGlow(true)
        onGrainClicked: section.enableGrain()
    }

    function openShadowPickerAt(at, color, anchor, mx, my) {
        section.pickerShadowIndex = at;
        colorPicker.openFor(color, anchor, mx, my);
    }

    function openGlowPickerAt(at, color, anchor, mx, my) {
        section.pickerGlowIndex = at;
        glowPicker.openFor(color, anchor, mx, my);
    }

    // Picker entries stack: shadows/glows always append, singles
    // enable in place (background blur skips text: glyphs never sample
    // the backdrop, so the picker row disables up front for text).
    function setEffect(type, inner) {
        if (type === "shadow")
            section.addShadow(inner);
        else if (type === "glow")
            section.addGlow(inner);
        else if (type === "layerBlur" || type === "backgroundBlur")
            section.enableBlur(type);
        else if (type === "grain")
            section.enableGrain();
        else
            section.clearAllEffects();
    }

    function addShadow(inner) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var next = (leaves[i].shadows || []).slice();
            next.push(d.factory.defaultShadow(inner));
            leaves[i].shadows = next;
        }
        d.touch();
    }

    function addGlow(inner) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            var n = leaves[i];
            if (d.isEffectivelyLocked(n))
                continue;
            var next = (n.glows || []).slice();
            // Fresh map per leaf (never share one object across nodes).
            var entry = d.factory.defaultGlow(inner);
            next.push(entry);
            n.glows = next;
        }
        d.touch();
    }

    function enableBlur(role) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            // Background blur never lands on text (glyphs sample no
            // backdrop); layer blur stacks over glyphs like vectors.
            if (role === "backgroundBlur" && leaves[i].shapeType === "text")
                continue;
            var cur = leaves[i][role] ?? {};
            var defRadius = role === "backgroundBlur" ? 16 : 8;
            var defOpacity = role === "backgroundBlur" ? 0.7 : 1;
            leaves[i][role] = {
                enabled: true,
                radius: cur.radius !== undefined ? Math.max(0, Number(cur.radius) || 0) : defRadius,
                opacity: cur.opacity !== undefined ? Math.min(1, Math.max(0, Number(cur.opacity))) : defOpacity
            };
        }
        d.touch();
    }

    function enableGrain() {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var cur = leaves[i].grain ?? {};
            leaves[i].grain = {
                enabled: true,
                amount: cur.amount !== undefined ? Math.min(1, Math.max(0, Number(cur.amount))) : 0.5,
                size: cur.size !== undefined ? Math.min(10, Math.max(1, Number(cur.size) || 0)) : 2
            };
        }
        d.touch();
    }

    // Disables every branch and drops stacked entries.
    function clearAllEffects() {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            leaves[i].shadows = [];
            leaves[i].glows = [];
            // Whole-object reassigns (never in-place .enabled flips):
            // var maps notify only on assign, so mutations alone leave
            // the canvas stale until the tab rebuilds.
            if (leaves[i].layerBlur)
                leaves[i].layerBlur = Object.assign({}, leaves[i].layerBlur, {
                    enabled: false
                });
            if (leaves[i].backgroundBlur)
                leaves[i].backgroundBlur = Object.assign({}, leaves[i].backgroundBlur, {
                    enabled: false
                });
            if (leaves[i].grain)
                leaves[i].grain = Object.assign({}, leaves[i].grain, {
                    enabled: false
                });
        }
        d.touch();
    }

    function toggleShadowAt(at) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        var common = section.collectShadowAt(at);
        var nextOn = !(common.value.enabled !== false);
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var list = (leaves[i].shadows || []).slice();
            if (at >= list.length)
                continue;
            var entry = Object.assign({}, list[at]);
            entry.enabled = nextOn;
            list[at] = entry;
            leaves[i].shadows = list;
        }
        d.touch();
    }

    function toggleGlowAt(at) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        var common = section.collectGlowAt(at);
        var nextOn = !(common.value.enabled !== false);
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var list = (leaves[i].glows || []).slice();
            if (at >= list.length)
                continue;
            var entry = Object.assign({}, list[at]);
            entry.enabled = nextOn;
            list[at] = entry;
            leaves[i].glows = list;
        }
        d.touch();
    }

    function removeShadowAt(at) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var list = (leaves[i].shadows || []).slice();
            if (at >= list.length)
                continue;
            list.splice(at, 1);
            leaves[i].shadows = list;
        }
        d.touch();
    }

    function removeGlowAt(at) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var list = (leaves[i].glows || []).slice();
            if (at >= list.length)
                continue;
            list.splice(at, 1);
            leaves[i].glows = list;
        }
        d.touch();
    }

    function moveShadowAt(at, delta) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        var to = at + delta;
        if (to < 0)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var list = (leaves[i].shadows || []).slice();
            if (at >= list.length || to >= list.length)
                continue;
            var tmp = list[at];
            list[at] = list[to];
            list[to] = tmp;
            leaves[i].shadows = list;
        }
        d.touch();
    }

    function moveGlowAt(at, delta) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        var to = at + delta;
        if (to < 0)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var list = (leaves[i].glows || []).slice();
            if (at >= list.length || to >= list.length)
                continue;
            var tmp = list[at];
            list[at] = list[to];
            list[to] = tmp;
            leaves[i].glows = list;
        }
        d.touch();
    }

    function setShadowInnerAt(at, on) {
        section.patchShadowAt(at, "inner", on === true);
    }

    function setGlowInnerAt(at, on) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            var n = leaves[i];
            if (d.isEffectivelyLocked(n))
                continue;
            var list = (n.glows || []).slice();
            if (at >= list.length)
                continue;
            var entry = Object.assign({}, list[at]);
            entry.enabled = true;
            entry.inner = on === true;
            list[at] = entry;
            n.glows = list;
        }
        d.touch();
    }

    function patchShadowAt(at, role, value) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var list = (leaves[i].shadows || []).slice();
            if (at >= list.length)
                continue;
            var entry = Object.assign({}, list[at]);
            entry.enabled = true;
            entry[role] = role === "blur" || role === "spread" ? Math.max(0, Number(value) || 0) : value;
            list[at] = entry;
            leaves[i].shadows = list;
        }
        d.touch();
    }

    function patchGlowAt(at, role, value) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var j = 0; j < leaves.length; j++) {
            if (d.isEffectivelyLocked(leaves[j]))
                continue;
            var list = (leaves[j].glows || []).slice();
            if (at >= list.length)
                continue;
            var entry = Object.assign({}, list[at]);
            entry.enabled = true;
            entry[role] = role === "blur" || role === "spread" ? Math.max(0, Number(value) || 0) : value;
            list[at] = entry;
            leaves[j].glows = list;
        }
        d.touch();
    }

    function patchBlur(role, key, value) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var j = 0; j < leaves.length; j++) {
            if (d.isEffectivelyLocked(leaves[j]))
                continue;
            var cur = leaves[j][role] ?? {};
            var defRadius = role === "backgroundBlur" ? 16 : 8;
            var defOpacity = role === "backgroundBlur" ? 0.7 : 1;
            var next = {
                enabled: true,
                radius: cur.radius !== undefined ? Math.max(0, Number(cur.radius) || 0) : defRadius,
                opacity: cur.opacity !== undefined ? Math.min(1, Math.max(0, Number(cur.opacity))) : defOpacity
            };
            next[key] = key === "radius" ? Math.max(0, Number(value) || 0) : Math.min(1, Math.max(0, Number(value)));
            leaves[j][role] = next;
        }
        d.touch();
    }

    function removeBlur(role) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            if (leaves[i][role])
                leaves[i][role] = Object.assign({}, leaves[i][role], {
                    enabled: false
                });
        }
        d.touch();
    }

    function patchGrain(key, value) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var j = 0; j < leaves.length; j++) {
            if (d.isEffectivelyLocked(leaves[j]))
                continue;
            var cur = leaves[j].grain ?? {};
            var next = {
                enabled: true,
                amount: cur.amount !== undefined ? Math.min(1, Math.max(0, Number(cur.amount))) : 0.5,
                size: cur.size !== undefined ? Math.min(10, Math.max(1, Number(cur.size) || 0)) : 2
            };
            next[key] = key === "size" ? Math.min(10, Math.max(1, Number(value) || 0)) : Math.min(1, Math.max(0, Number(value)));
            leaves[j].grain = next;
        }
        d.touch();
    }

    function removeGrain() {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d._selectedLeaves();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            if (leaves[i].grain)
                leaves[i].grain = Object.assign({}, leaves[i].grain, {
                    enabled: false
                });
        }
        d.touch();
    }

    // Shadow color carries alpha (#aarrggbb) but HexField and the pad
    // speak opaque rgb: split/combine around them.
    function hexOf(c) {
        var t = String(c).toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (t.length === 8)
            return "#" + t.slice(2);
        return "#" + t;
    }

    function alphaOf(c) {
        var t = String(c).toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (t.length === 8)
            return Math.round(parseInt(t.slice(0, 2), 16) / 255 * 100);
        return 100;
    }

    function withAlpha(hex, pct) {
        var t = String(hex).toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (t.length === 3)
            t = t.charAt(0) + t.charAt(0) + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2);
        if (t.length === 8)
            t = t.slice(2);
        if (!/^[0-9a-f]{6}$/.test(t))
            t = "000000";
        var a = Math.round(Math.min(100, Math.max(0, Number(pct) || 0)) / 100 * 255);
        var h = a.toString(16);
        if (h.length === 1)
            h = "0" + h;
        if (a >= 255)
            return "#" + t;
        return "#" + h + t;
    }
}
