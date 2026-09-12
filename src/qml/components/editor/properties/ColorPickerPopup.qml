import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Figma-style color picker: SV square + hue bar + hex row with live
// preview. Swatch-click opens via openFor(color, anchor, x, y); the hex
// field stays for typing. Drags stream committed() live between
// scrubStarted and scrubFinished so the caller coalesces one undo entry
// (same contract as NumberField scrub and EasingGraph handles).
// Opening and closing without touching anything commits nothing.
// Window-clamped: parented to the window overlay and placed from the
// click point (below when it fits, above otherwise), so the popup can
// never spill outside the window like a fixed offset would.
Popup {
    id: picker

    parent: Overlay.overlay

    property real hue: 0
    property real sat: 1
    property real val: 1
    property bool scrubbing: false
    // Gradient mode for fill/stroke gradients (Figma-style Solid |
    // Gradient tabs on top). Callers that support it pass allowGradient
    // and open via openForGradient; the working copy lives here so tab
    // switches never lose the draft.
    property bool allowGradient: false
    property string editMode: "solid"
    property var gradient: ({
            "angle": 90,
            "stops": [
                {
                    "color": "#000000",
                    "pos": 0
                },
                {
                    "color": "#ffffff",
                    "pos": 1
                }
            ]
        })

    readonly property color liveColor: Qt.hsva(picker.hue, picker.sat, picker.val, 1)

    signal committed(color newColor)
    signal gradientCommitted(var gradient)
    signal scrubStarted
    signal scrubFinished

    width: 248
    padding: 12
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 0.97
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: 100
            easing.type: Easing.InCubic
        }
    }

    background: Rectangle {
        radius: 10
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border
    }

    contentItem: Column {
        width: parent.width
        spacing: 8

        RowLayout {
            width: parent.width
            visible: picker.allowGradient
            spacing: 8

            SegmentedOption {
                label: qsTr("Solid")
                active: picker.editMode === "solid"
                onClicked: picker.editMode = "solid"
            }

            SegmentedOption {
                label: qsTr("Gradient")
                active: picker.editMode === "gradient"
                onClicked: picker.toGradient()
            }
        }

        ColorSVPad {
            visible: picker.editMode === "solid"
            width: parent.width
            height: 190
            hue: picker.hue
            sat: picker.sat
            val: picker.val
            pressPolicy: (s, v) => picker.applyPad(s, v, true)
            movePolicy: (s, v) => picker.applyPad(s, v, false)
            releasePolicy: () => picker.endDrag()
        }

        ColorHueSlider {
            visible: picker.editMode === "solid"
            width: parent.width
            hue: picker.hue
            pressPolicy: h => picker.applyHue(h, true)
            movePolicy: h => picker.applyHue(h, false)
            releasePolicy: () => picker.endDrag()
        }

        RowLayout {
            visible: picker.editMode === "solid"
            width: parent.width
            spacing: 8

            Text {
                Layout.preferredWidth: 28
                text: qsTr("Hex")
                font.pixelSize: 11
                color: AppTheme.muted
            }

            HexField {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                value: picker.toHex(picker.liveColor)
                onCommitted: c => picker.applyHex(c)
            }

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 28
                radius: 6
                color: picker.liveColor
                border.width: 1
                border.color: AppTheme.fieldBorder
            }
        }

        GradientEditor {
            id: gradEditor

            visible: picker.editMode === "gradient"
            width: parent.width
            gradient: picker.gradient
            onGradientCommitted: g => picker.applyGradient(g)
            onScrubStarted: picker.scrubStarted()
            onScrubFinished: picker.scrubFinished()
        }
    }

    // Press-outside mid-drag cancels the pad/slider gesture without a
    // release: settle the transaction here so history depth never leaks
    // (an unbalanced begin would swallow every later undo entry).
    onClosed: {
        if (picker.scrubbing)
            picker.endDrag();
        gradEditor.endDrag();
    }

    // Swatch entry: seed h/s/v from the variant. Greys carry no hue,
    // so they keep the current one instead of jumping the square red.
    function openFor(c, anchor, ax, ay) {
        picker.editMode = "solid";
        picker.seedFrom(c);
        picker.placeNear(anchor, ax, ay);
        picker.open();
    }

    // Gradient entry: works on a private copy so closing without touching
    // anything commits nothing, like the solid path.
    function openForGradient(g, anchor, ax, ay) {
        picker.editMode = "gradient";
        picker.gradient = picker.copyGradient(g);
        picker.placeNear(anchor, ax, ay);
        picker.open();
    }

    // Solid -> Gradient convert from the tab: first stop keeps the live
    // color, second contrasts against it. Gradient -> Solid just flips
    // the tab; the pad keeps its state and commits route as solid.
    function toGradient() {
        if (picker.editMode === "gradient")
            return;
        var live = picker.toHex(picker.liveColor);
        var other = picker.isDarkColor(live) ? "#ffffff" : "#000000";
        picker.gradient = {
            angle: 90,
            stops: [
                {
                    color: live,
                    pos: 0
                },
                {
                    color: other,
                    pos: 1
                }
            ]
        };
        picker.editMode = "gradient";
    }

    function isDarkColor(hex) {
        var t = String(hex).toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (t.length < 6)
            return true;
        var r = parseInt(t.slice(0, 2), 16), g = parseInt(t.slice(2, 4), 16), b = parseInt(t.slice(4, 6), 16);
        return (0.299 * r + 0.587 * g + 0.114 * b) < 128;
    }

    function copyGradient(g) {
        var d = g ?? {};
        var raw = d.stops;
        var out = [];
        if (raw && typeof raw.length === "number") {
            for (var i = 0; i < raw.length && out.length < 2; i++)
                out.push({
                    color: String((raw[i] || {}).color ?? "#000000"),
                    pos: out.length === 0 ? 0 : 1
                });
        }
        while (out.length < 2)
            out.push({
                color: out.length === 0 ? "#000000" : "#ffffff",
                pos: out.length === 0 ? 0 : 1
            });
        return {
            angle: Number(d.angle) || 0,
            stops: out
        };
    }

    function applyGradient(g) {
        picker.gradient = g;
        picker.gradientCommitted(g);
    }

    // Anchor-relative placement in overlay coords: below the click when
    // it fits, above otherwise, clamped on both axes with an 8px margin
    // so short windows and bottom rows never push it off-screen.
    function placeNear(anchor, ax, ay) {
        var ov = picker.parent;
        var w = picker.width;
        var h = picker.implicitHeight > 0 ? picker.implicitHeight : 272;
        if (!anchor || !ov) {
            picker.x = 8;
            picker.y = 8;
            return;
        }
        var p = anchor.mapToItem(ov, ax, ay);
        picker.x = Math.min(Math.max(8, Math.round(p.x - w / 2)), Math.max(8, ov.width - w - 8));
        var maxY = Math.max(8, ov.height - h - 8);
        var below = Math.round(p.y + 12);
        if (below + h <= ov.height - 8)
            picker.y = below;
        else
            picker.y = Math.max(8, Math.min(Math.round(p.y - 12 - h), maxY));
    }

    function toHex(c) {
        function ch(x) {
            var s = Math.round(x * 255).toString(16);
            return s.length === 1 ? "0" + s : s;
        }
        return "#" + ch(c.r) + ch(c.g) + ch(c.b);
    }

    // Manual #rrggbb parse (accepts rgb shorthand): incoming values may
    // be strings or colors depending on the caller, so nothing here may
    // assume QML color helpers. Returns [hue (-1 when grey), sat, val].
    function fromHex(s) {
        var t = String(s).toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (/^[0-9a-f]{3}$/.test(t))
            t = t.charAt(0) + t.charAt(0) + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2);
        if (!/^[0-9a-f]{6}$/.test(t))
            return [0, 0, 1];
        var r = parseInt(t.slice(0, 2), 16) / 255;
        var g = parseInt(t.slice(2, 4), 16) / 255;
        var b = parseInt(t.slice(4, 6), 16) / 255;
        var mx = Math.max(r, g, b);
        var mn = Math.min(r, g, b);
        var d = mx - mn;
        var h = -1;
        if (d !== 0) {
            if (mx === r)
                h = ((g - b) / d) % 6;
            else if (mx === g)
                h = (b - r) / d + 2;
            else
                h = (r - g) / d + 4;
            h /= 6;
            if (h < 0)
                h += 1;
        }
        return [h, mx === 0 ? 0 : d / mx, mx];
    }

    function seedFrom(c) {
        var hsv = picker.fromHex(c);
        if (hsv[0] >= 0)
            picker.hue = hsv[0];
        picker.sat = hsv[1];
        picker.val = hsv[2];
    }

    function beginDrag() {
        if (picker.scrubbing)
            return;
        picker.scrubbing = true;
        picker.scrubStarted();
    }

    function endDrag() {
        if (!picker.scrubbing)
            return;
        picker.scrubbing = false;
        picker.scrubFinished();
    }

    function applyPad(s, v, first) {
        if (first)
            picker.beginDrag();
        picker.sat = s;
        picker.val = v;
        picker.committed(picker.liveColor);
    }

    function applyHue(h, first) {
        if (first)
            picker.beginDrag();
        picker.hue = h;
        picker.committed(picker.liveColor);
    }

    // Typed hex is a discrete edit (one undo entry via the caller's
    // own checkpoint), never a scrub: no begin/end around it.
    function applyHex(c) {
        picker.seedFrom(c);
        picker.committed(picker.liveColor);
    }
}
