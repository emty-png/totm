import QtQuick
import QtQuick.Layouts
import Totm

// Custom Style editors: Opacity (absolute 0-1), Color (fill hex
// from-to + entry opacity), Stroke color (stroke hex from-to + entry
// opacity). Wells open the shared solid picker; hex stays for typing.
// Absolute values give exact control; the gallery seeds From from the
// live selection so new clips start jump-free. A solid clip opened on
// a linear top entry auto-swaps to its gradient sibling (seeded, one
// undo entry) instead of animating an invisible color. Color clips
// target the top stack entry (index 0); whole-stack animation is out
// of scope for v1.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property string preset: section.clip ? section.clip.preset : ""
    // Top entry of the clip target (reactive to doc edits): a solid
    // color clip on a linear top entry animates an unused color field,
    // so the section auto-swaps to the gradient sibling on open.
    readonly property var targetTop: {
        if (section.doc)
            section.doc.rev;
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
    readonly property bool targetTopIsLinear: {
        var t = section.targetTop;
        if (!t)
            return false;
        var stack = section.preset === "customStrokeColor" ? (t.strokes || []) : (t.fills || []);
        return stack.length > 0 && stack[0] && stack[0].type === "linear";
    }
    readonly property bool showGradientHint: (section.preset === "customColor" || section.preset === "customStrokeColor") && section.targetTopIsLinear
    // Set when the automatic swap to the gradient sibling fails (the
    // target is gone): the note below is a fallback, never a button.
    property bool swapFailed: false

    spacing: 8

    Text {
        visible: section.showGradientHint && section.swapFailed
        Layout.fillWidth: true
        text: section.preset === "customStrokeColor" ? qsTr("Top stroke is a gradient — reopen this clip to animate its stops.") : qsTr("Top fill is a gradient — reopen this clip to animate its stops.")
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        color: AppTheme.muted
    }

    Component.onCompleted: {
        // Solid color clips on a linear top entry animate an unused
        // color field (invisible): swap to the gradient sibling at
        // open time, seeded from the live entry, instead of asking.
        if (section.showGradientHint) {
            var gradPreset = section.preset === "customStrokeColor" ? "customStrokeGradient" : "customGradient";
            if (!section.doc.convertClipPreset(section.clipId, gradPreset))
                section.swapFailed = true;
        }
    }

    Text {
        visible: section.preset === "customOpacity" || section.preset === "customColor" || section.preset === "customStrokeColor"
        text: qsTr("From")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.preset === "customOpacity"
        Layout.fillWidth: true
        minimum: 0
        maximum: 1
        scrubStep: 0.05
        value: Number(section.opts.from) || 0
        onCommitted: v => section.setOption("from", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    RowLayout {
        visible: section.preset === "customColor"
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: String(section.opts.from || "#000000")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.from || "#000000")
            onCommitted: c => section.setOption("from", c)
        }
    }

    RowLayout {
        visible: section.preset === "customStrokeColor"
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: String(section.opts.from || "#000000")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.from || "#000000")
            onCommitted: c => section.setOption("from", c)
        }
    }

    Text {
        visible: section.preset === "customOpacity" || section.preset === "customColor" || section.preset === "customStrokeColor"
        text: qsTr("To")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.preset === "customOpacity"
        Layout.fillWidth: true
        minimum: 0
        maximum: 1
        scrubStep: 0.05
        value: Number(section.opts.to) || 0
        onCommitted: v => section.setOption("to", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    RowLayout {
        visible: section.preset === "customColor"
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: String(section.opts.to || "#ff0000")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.to || "#ff0000")
            onCommitted: c => section.setOption("to", c)
        }
    }

    RowLayout {
        visible: section.preset === "customStrokeColor"
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: String(section.opts.to || "#ff0000")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.to || "#ff0000")
            onCommitted: c => section.setOption("to", c)
        }
    }

    Text {
        visible: section.preset === "customColor" || section.preset === "customStrokeColor"
        text: qsTr("From opacity")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.preset === "customColor" || section.preset === "customStrokeColor"
        Layout.fillWidth: true
        minimum: 0
        maximum: 1
        scrubStep: 0.05
        value: section.opts.fromOpacity !== undefined ? Number(section.opts.fromOpacity) : 1
        onCommitted: v => section.setOption("fromOpacity", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        visible: section.preset === "customColor" || section.preset === "customStrokeColor"
        text: qsTr("To opacity")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.preset === "customColor" || section.preset === "customStrokeColor"
        Layout.fillWidth: true
        minimum: 0
        maximum: 1
        scrubStep: 0.05
        value: section.opts.toOpacity !== undefined ? Number(section.opts.toOpacity) : 1
        onCommitted: v => section.setOption("toOpacity", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    function setOption(role, value) {
        if (!section.doc)
            return;
        var patch = {};
        patch[role] = value;
        section.doc.setClipOptions(section.clipId, patch);
    }

    function beginScrub() {
        if (section.doc)
            section.doc.beginTransaction();
    }

    function endScrub() {
        if (section.doc)
            section.doc.endTransaction();
    }
}
