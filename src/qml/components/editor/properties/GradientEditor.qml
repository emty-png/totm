import QtQuick
import QtQuick.Layouts
import Totm

// Gradient stop + angle editor for the color picker. Works on the picker's
// working copy: every gesture emits gradientCommitted with a whole new
// {angle, stops} map so the caller writes it back wholesale (same undo
// contract as solid drags). N-stop linear (2..8 stops, sorted by pos).
ColumnLayout {
    id: editor

    required property var gradient

    signal gradientCommitted(var gradient)
    signal scrubStarted
    signal scrubFinished

    property int stopIndex: 0
    property real hue: 0
    property real sat: 1
    property real val: 1
    property bool scrubbing: false

    spacing: 8

    // Stop selector: N swatches + add/remove, active one outlined.
    // Flow wraps to a second row past ~6 stops so the popup never
    // overflows its 248px width.
    Flow {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: editor.stops().length

            Rectangle {
                required property int index

                width: 28
                height: 28
                radius: AppTheme.radiusSmall
                color: editor.stopColor(index)
                border.width: 1
                border.color: editor.stopIndex === index ? AppTheme.foreground : AppTheme.fieldBorder

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.selectStop(parent.index)
                }
            }
        }

        PanelIconButton {
            iconKind: "plus"
            filled: false
            iconSize: 14
            enabled: editor.stops().length < 8
            onClicked: editor.addStop()
        }

        PanelIconButton {
            iconKind: "close"
            filled: false
            iconSize: 12
            enabled: editor.stops().length > 2
            onClicked: editor.removeStop()
        }
    }

    ColorSVPad {
        Layout.fillWidth: true
        Layout.preferredHeight: 150
        hue: editor.hue
        sat: editor.sat
        val: editor.val
        pressPolicy: (s, v) => editor.applyPad(s, v, true)
        movePolicy: (s, v) => editor.applyPad(s, v, false)
        releasePolicy: () => editor.endDrag()
    }

    ColorHueSlider {
        Layout.fillWidth: true
        hue: editor.hue
        pressPolicy: h => editor.applyHue(h, true)
        movePolicy: h => editor.applyHue(h, false)
        releasePolicy: () => editor.endDrag()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        HexField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            value: editor.stopColor(editor.stopIndex)
            onCommitted: c => editor.applyHex(c)
        }

        NumberField {
            Layout.preferredWidth: 72
            suffix: qsTr("%")
            minimum: 0
            maximum: 100
            scrubStep: 1
            value: Math.round(Number(editor.stopPos(editor.stopIndex)) * 100)
            onCommitted: v => editor.applyPos(v / 100)
            onScrubStarted: editor.scrubStarted()
            onScrubFinished: editor.scrubFinished()
        }

        NumberField {
            Layout.preferredWidth: 84
            prefix: qsTr("A")
            suffix: qsTr("°")
            minimum: 0
            maximum: 360
            scrubStep: 1
            value: Number(editor.gradient.angle) || 0
            onCommitted: v => editor.applyAngle(v)
            onScrubStarted: editor.scrubStarted()
            onScrubFinished: editor.scrubFinished()
        }
    }

    Component.onCompleted: editor.selectStop(0)

    onGradientChanged: {
        var n = editor.stops().length;
        if (editor.stopIndex >= n)
            editor.stopIndex = Math.max(0, n - 1);
        editor.seedFrom(editor.stopColor(editor.stopIndex));
    }

    function stops() {
        var s = editor.gradient ? editor.gradient.stops : null;
        if (s && typeof s.length === "number" && s.length >= 2 && s.length <= 8)
            return s;
        if (s && typeof s.length === "number" && s.length > 8) {
            // Defensive: model should never exceed 8 (factory resamples),
            // but resample by sorted index so coverage survives.
            var copy = Array.prototype.slice.call(s, 0, s.length);
            copy.sort(function (a, b) {
                return Number(a.pos) - Number(b.pos);
            });
            var sampled = [];
            for (var k = 0; k < 8; k++)
                sampled.push(copy[Math.round(k * (copy.length - 1) / 7)]);
            return sampled;
        }
        return [
            {
                color: "#000000",
                pos: 0
            },
            {
                color: "#ffffff",
                pos: 1
            }
        ];
    }

    function stopColor(i) {
        var s = editor.stops();
        var c = i < s.length ? s[i].color : "#000000";
        return String(c);
    }

    function stopPos(i) {
        var s = editor.stops();
        if (i >= s.length)
            return i === 0 ? 0 : 1;
        var p = Number(s[i].pos);
        return isNaN(p) ? (s.length <= 1 ? i : i / (s.length - 1)) : Math.min(1, Math.max(0, p));
    }

    function selectStop(i) {
        var n = editor.stops().length;
        editor.stopIndex = Math.min(Math.max(0, i), Math.max(0, n - 1));
        editor.seedFrom(editor.stopColor(editor.stopIndex));
    }

    function seedFrom(c) {
        var hsv = editor.fromHex(c);
        if (hsv[0] >= 0)
            editor.hue = hsv[0];
        editor.sat = hsv[1];
        editor.val = hsv[2];
    }

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

    function toHex(c) {
        function ch(x) {
            var s = Math.round(x * 255).toString(16);
            return s.length === 1 ? "0" + s : s;
        }
        return "#" + ch(c.r) + ch(c.g) + ch(c.b);
    }

    function currentGradient() {
        var s = editor.stops();
        var out = [];
        for (var i = 0; i < s.length; i++) {
            var p = Number(s[i].pos);
            out.push({
                color: String(s[i].color),
                pos: isNaN(p) ? (s.length <= 1 ? i : i / (s.length - 1)) : Math.min(1, Math.max(0, p))
            });
        }
        return {
            angle: Number(editor.gradient.angle) || 0,
            stops: out
        };
    }

    function sortedGradient(stops, angle) {
        var out = stops.slice();
        out.sort(function (a, b) {
            return a.pos - b.pos;
        });
        return {
            angle: angle,
            stops: out
        };
    }

    function beginDrag() {
        if (editor.scrubbing)
            return;
        editor.scrubbing = true;
        editor.scrubStarted();
    }

    function endDrag() {
        if (!editor.scrubbing)
            return;
        editor.scrubbing = false;
        editor.scrubFinished();
    }

    function applyPad(s, v, first) {
        if (first)
            editor.beginDrag();
        editor.sat = s;
        editor.val = v;
        editor.commitStop(editor.toHex(Qt.hsva(editor.hue, s, v, 1)));
    }

    function applyHue(h, first) {
        if (first)
            editor.beginDrag();
        editor.hue = h;
        editor.commitStop(editor.toHex(Qt.hsva(h, editor.sat, editor.val, 1)));
    }

    function applyHex(c) {
        editor.seedFrom(c);
        editor.commitStop(String(c));
    }

    function applyAngle(v) {
        var g = editor.currentGradient();
        g.angle = Math.min(360, Math.max(0, Number(v) || 0));
        editor.gradientCommitted(g);
    }

    function commitStop(color) {
        var g = editor.currentGradient();
        var idx = Math.min(editor.stopIndex, g.stops.length - 1);
        g.stops[idx].color = String(color);
        g.stops.sort(function (a, b) {
            return a.pos - b.pos;
        });
        editor.gradientCommitted(g);
    }

    function applyPos(p) {
        var g = editor.currentGradient();
        var idx = Math.min(editor.stopIndex, g.stops.length - 1);
        var moved = g.stops[idx];
        var np = Math.min(1, Math.max(0, Number(p) || 0));
        moved.pos = np;
        var sorted = editor.sortedGradient(g.stops, g.angle);
        // Follow the moved stop by identity so duplicates sharing a
        // position select the right swatch.
        var at = sorted.stops.indexOf(moved);
        if (at < 0) {
            at = idx;
            for (var i = 0; i < sorted.stops.length; i++) {
                if (Math.abs(sorted.stops[i].pos - np) < 0.0005) {
                    at = i;
                    break;
                }
            }
        }
        editor.stopIndex = at;
        editor.gradientCommitted(sorted);
    }

    function addStop() {
        var g = editor.currentGradient();
        if (g.stops.length >= 8)
            return;
        var idx = Math.min(editor.stopIndex, g.stops.length - 1);
        var cur = g.stops[idx];
        var pos;
        if (idx >= g.stops.length - 1 && g.stops.length >= 2) {
            // At the end: midpoint with predecessor so the new stop stays
            // inside 0..1 instead of duplicating the edge.
            var prev = g.stops[g.stops.length - 2];
            var pp = Number(prev.pos), cp = Number(cur.pos);
            if (isNaN(pp))
                pp = cp;
            if (isNaN(cp))
                cp = pp;
            if (Math.abs(pp - cp) < 0.0005) {
                // Duplicated end: step inward to stay visible.
                pos = cp >= 1 ? cp - 0.1 : (cp <= 0 ? cp + 0.1 : Math.min(1, cp + 0.1));
            } else {
                pos = (pp + cp) / 2;
            }
        } else {
            var next = g.stops[Math.min(idx + 1, g.stops.length - 1)];
            pos = (Number(cur.pos) + Number(next.pos)) / 2;
            if (Math.abs(Number(cur.pos) - Number(next.pos)) < 0.0005) {
                // Duplicated pair: step outward to stay visible.
                pos = Number(cur.pos) >= 1 ? Number(cur.pos) - 0.1 : Math.min(1, Number(cur.pos) + 0.1);
            }
        }
        if (pos === undefined || isNaN(pos))
            pos = Math.min(1, Math.max(0, Number(cur.pos) + 0.1));
        pos = Math.min(1, Math.max(0, pos));
        // Avoid an invisible same-pos duplicate when copying the same
        // color: nudge inside 0..1 so the new swatch is visible (exact
        // duplicates remain possible by scrubbing % for hard edges).
        var dup = false;
        for (var d = 0; d < g.stops.length; d++) {
            if (Math.abs(Number(g.stops[d].pos) - pos) < 0.0005) {
                dup = true;
                break;
            }
        }
        if (dup) {
            var up = Math.min(1, pos + 0.1);
            var upDup = false;
            for (var u = 0; u < g.stops.length; u++) {
                if (Math.abs(Number(g.stops[u].pos) - up) < 0.0005) {
                    upDup = true;
                    break;
                }
            }
            if (!upDup)
                pos = up;
            else {
                var dn = Math.max(0, pos - 0.1);
                var dnDup = false;
                for (var v = 0; v < g.stops.length; v++) {
                    if (Math.abs(Number(g.stops[v].pos) - dn) < 0.0005) {
                        dnDup = true;
                        break;
                    }
                }
                if (!dnDup)
                    pos = dn;
            }
        }
        var newStop = {
            color: String(cur.color),
            pos: pos
        };
        g.stops.push(newStop);
        var sorted = editor.sortedGradient(g.stops, g.angle);
        // Select the new stop by identity so duplicates never steal it.
        var at = sorted.stops.indexOf(newStop);
        if (at < 0) {
            at = sorted.stops.length - 1;
            for (var i = 0; i < sorted.stops.length; i++) {
                if (Math.abs(sorted.stops[i].pos - pos) < 0.0005) {
                    at = i;
                    break;
                }
            }
        }
        editor.stopIndex = at;
        editor.seedFrom(String(cur.color));
        editor.gradientCommitted(sorted);
    }

    function removeStop() {
        var g = editor.currentGradient();
        if (g.stops.length <= 2)
            return;
        var idx = Math.min(editor.stopIndex, g.stops.length - 1);
        g.stops.splice(idx, 1);
        g.stops.sort(function (a, b) {
            return a.pos - b.pos;
        });
        editor.stopIndex = Math.min(idx, g.stops.length - 1);
        var nextColor = g.stops.length > 0 ? String(g.stops[editor.stopIndex].color) : "#000000";
        editor.seedFrom(nextColor);
        editor.gradientCommitted({
            angle: g.angle,
            stops: g.stops
        });
    }
}
