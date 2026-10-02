import QtQuick
import QtQuick.Layouts
import Totm

// Video time editor: footage from-to in footage seconds for video
// leaves (freeze = equal ends, reverse = From > To, ramp = easing).
// Keys hold {v} footage seconds for scrub/boomerang shapes; the
// sampler clamps to the probed length, so export never seeks past EOF.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})

    spacing: 8

    Text {
        text: qsTr("From (footage)")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("s")
        minimum: 0
        maximum: 3600
        scrubStep: 0.05
        value: Number(section.opts.from) || 0
        onCommitted: v => section.setOption("from", Math.max(0, Number(v) || 0))
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("To (footage)")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("s")
        minimum: 0
        maximum: 3600
        scrubStep: 0.05
        value: Number(section.opts.to) || 0
        onCommitted: v => section.setOption("to", Math.max(0, Number(v) || 0))
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        Layout.fillWidth: true
        text: qsTr("Equal ends freeze the frame. Easing shapes the ramp: Ease out decelerates into the end frame.")
        font.pixelSize: 11
        color: AppTheme.muted
        wrapMode: Text.WordWrap
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
