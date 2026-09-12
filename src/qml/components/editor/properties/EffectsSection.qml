import QtQuick
import QtQuick.Layouts
import Totm

// Outer shadow effect (single per shape in v1). Vector shapes only:
// text glyphs and images keep native rendering and never see this
// section. + opens the effect picker; the rows edit color, offsets,
// blur and spread live with scrub-coalesced undo.
PanelSection {
    id: section

    required property var snapshot

    title: qsTr("Effects")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup && section.vectorOnly()
    enabled: !section.snapshot.allLocked
    compact: !section.shadowOn()
    showAdd: !section.shadowOn()
    showRemove: section.shadowOn()
    onAddClicked: picker.openAt(section)
    onRemoveClicked: section.setEnabled(false)

    property var shadowCommon: section.collectShadow()
    // Outer shadow and glow share the painter; inner flips the flag.
    // Mixed inner/outer reads as outer until unified.
    property bool shadowInner: section.shadowCommon.value.inner === true

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        SegmentedOption {
            label: qsTr("Outer")
            active: !section.shadowInner
            onClicked: section.setInner(false)
        }

        SegmentedOption {
            label: qsTr("Inner")
            active: section.shadowInner
            onClicked: section.setInner(true)
        }
    }

    function vectorOnly() {
        var leaves = section.snapshot.selLeaves;
        if (leaves.length === 0)
            return false;
        for (var i = 0; i < leaves.length; i++) {
            var t = leaves[i].type;
            if (t !== "rectangle" && t !== "ellipse" && t !== "triangle" && t !== "star" && t !== "pen")
                return false;
        }
        return true;
    }

    function shadowOn() {
        var leaves = section.snapshot.selLeaves;
        if (leaves.length === 0)
            return false;
        for (var i = 0; i < leaves.length; i++) {
            if (!leaves[i].shadow || leaves[i].shadow.enabled !== true)
                return false;
        }
        return true;
    }

    // Common shadow with per-key mixed flags (maps never === by ref).
    function collectShadow() {
        var leaves = section.snapshot.selLeaves;
        var base = {
            enabled: false,
            inner: false,
            color: "#80000000",
            x: 0,
            y: 4,
            blur: 8,
            spread: 0
        };
        if (leaves.length === 0)
            return {
                value: base,
                mixedColor: true,
                mixedX: true,
                mixedY: true,
                mixedBlur: true,
                mixedSpread: true,
                mixedInner: true
            };
        var first = leaves[0].shadow ?? base;
        var mc = false, mx = false, my = false, mb = false, ms = false, mi = false;
        for (var i = 1; i < leaves.length; i++) {
            var s = leaves[i].shadow ?? base;
            if (String(s.color) !== String(first.color))
                mc = true;
            if (Number(s.x) !== Number(first.x))
                mx = true;
            if (Number(s.y) !== Number(first.y))
                my = true;
            if (Number(s.blur) !== Number(first.blur))
                mb = true;
            if (Number(s.spread) !== Number(first.spread))
                ms = true;
            if ((s.inner === true) !== (first.inner === true))
                mi = true;
        }
        return {
            value: {
                enabled: first.enabled === true,
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
            mixedInner: mi
        };
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            id: swatch

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: section.shadowCommon.value.color
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => colorPicker.openFor(String(section.shadowCommon.value.color), swatch, mouse.x, mouse.y)
            }
        }

        HexField {
            Layout.fillWidth: true
            value: section.hexOf(section.shadowCommon.value.color)
            mixed: section.shadowCommon.mixedColor
            onCommitted: c => section.patchShadow("color", section.withAlpha(c, section.alphaOf(section.shadowCommon.value.color)))
        }

        NumberField {
            Layout.preferredWidth: 76
            suffix: "%"
            minimum: 0
            maximum: 100
            value: section.alphaOf(section.shadowCommon.value.color)
            mixed: section.shadowCommon.mixedColor
            onCommitted: v => section.patchShadow("color", section.withAlpha(section.hexOf(section.shadowCommon.value.color), v))
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "X"
            suffix: qsTr("px")
            minimum: -500
            maximum: 500
            value: section.shadowCommon.value.x
            mixed: section.shadowCommon.mixedX
            onCommitted: v => section.patchShadow("x", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "Y"
            suffix: qsTr("px")
            minimum: -500
            maximum: 500
            value: section.shadowCommon.value.y
            mixed: section.shadowCommon.mixedY
            onCommitted: v => section.patchShadow("y", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "B"
            suffix: qsTr("px")
            minimum: 0
            maximum: 100
            value: section.shadowCommon.value.blur
            mixed: section.shadowCommon.mixedBlur
            onCommitted: v => section.patchShadow("blur", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "S"
            suffix: qsTr("px")
            minimum: 0
            maximum: 50
            value: section.shadowCommon.value.spread
            mixed: section.shadowCommon.mixedSpread
            onCommitted: v => section.patchShadow("spread", v)
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    // Shadow color picker: solid only. The pad edits opaque rgb; the
    // row's opacity field owns alpha, so picks keep current alpha.
    ColorPickerPopup {
        id: colorPicker

        onScrubStarted: section.snapshot.beginScrub()
        onCommitted: c => section.patchShadow("color", section.withAlpha(String(c), section.alphaOf(section.shadowCommon.value.color)))
        onScrubFinished: section.snapshot.endScrub()
    }

    EffectsPopup {
        id: picker

        onOuterShadowClicked: section.enableAs(false)
        onInnerShadowClicked: section.enableAs(true)
    }

    function baseShadow() {
        var v = section.shadowCommon.value;
        return {
            enabled: v.enabled,
            inner: v.inner === true,
            color: String(v.color),
            x: Number(v.x) || 0,
            y: Number(v.y) || 0,
            blur: Math.max(0, Number(v.blur) || 0),
            spread: Math.max(0, Number(v.spread) || 0)
        };
    }

    function setEnabled(on) {
        var next = section.baseShadow();
        next.enabled = on === true;
        section.snapshot.setAll("shadow", next);
    }

    // Popup entries enable with their own shape: outer keeps current
    // params, inner flips the flag.
    function enableAs(inner) {
        var next = section.baseShadow();
        next.enabled = true;
        next.inner = inner === true;
        section.snapshot.setAll("shadow", next);
    }

    function setInner(on) {
        var next = section.baseShadow();
        next.enabled = true;
        next.inner = on === true;
        section.snapshot.setAll("shadow", next);
    }

    function patchShadow(role, value) {
        var next = section.baseShadow();
        next.enabled = true;
        next[role] = value;
        section.snapshot.setAll("shadow", next);
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
