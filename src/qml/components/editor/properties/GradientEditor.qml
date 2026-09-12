import QtQuick
import QtQuick.Layouts
import Totm

// Gradient stop + angle editor for the color picker. Works on the picker's
// working copy: every gesture emits gradientCommitted with a whole new
// {angle, stops} map so the caller writes it back wholesale (same undo
// contract as solid drags). v1 is 2-stop linear only.
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

    // Stop selector: two solid swatches, active one outlined.
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: 2

            Rectangle {
                required property int index

                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                radius: 6
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

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: editor.stopIndex === 0 ? qsTr("Stop 1") : qsTr("Stop 2")
            font.pixelSize: 11
            color: AppTheme.muted
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

    function stops() {
        var s = editor.gradient ? editor.gradient.stops : null;
        if (s && typeof s.length === "number" && s.length >= 2)
            return s;
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

    function selectStop(i) {
        editor.stopIndex = i;
        editor.seedFrom(editor.stopColor(i));
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
        return {
            angle: Number(editor.gradient.angle) || 0,
            stops: [
                {
                    color: String(s[0].color),
                    pos: 0
                },
                {
                    color: String(s[1].color),
                    pos: 1
                }
            ]
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
        g.stops[editor.stopIndex].color = String(color);
        editor.gradientCommitted(g);
    }
}
