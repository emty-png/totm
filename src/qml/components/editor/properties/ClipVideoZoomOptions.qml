import QtQuick
import QtQuick.Layouts
import Totm

// Video zoom editor: content punch-in/out inside the box (box and
// strokes stay put). From/To are zoom factors (1 = native frame),
// focal rides 0..1 of the frame. Keys hold {s} absolute zoom.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})

    spacing: 8

    Text {
        text: qsTr("From (zoom)")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("x")
        minimum: 1
        maximum: 8
        scrubStep: 0.05
        value: Number(section.opts.from !== undefined ? section.opts.from : 1) || 0
        onCommitted: v => section.setOption("from", Math.min(8, Math.max(1, Number(v) || 1)))
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("To (zoom)")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("x")
        minimum: 1
        maximum: 8
        scrubStep: 0.05
        value: Number(section.opts.to !== undefined ? section.opts.to : 1) || 0
        onCommitted: v => section.setOption("to", Math.min(8, Math.max(1, Number(v) || 1)))
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("Focal X")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("%")
        minimum: 0
        maximum: 100
        scrubStep: 1
        value: Math.round(Number(section.opts.focusX !== undefined ? section.opts.focusX : 0.5) * 100)
        onCommitted: v => section.setOption("focusX", Math.min(1, Math.max(0, Number(v) / 100)))
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("Focal Y")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("%")
        minimum: 0
        maximum: 100
        scrubStep: 1
        value: Math.round(Number(section.opts.focusY !== undefined ? section.opts.focusY : 0.5) * 100)
        onCommitted: v => section.setOption("focusY", Math.min(1, Math.max(0, Number(v) / 100)))
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
