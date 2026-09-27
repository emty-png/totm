import QtQuick
import QtQuick.Layouts
import Totm

// Grow / Shrink clip options: the sized end of the gesture as a factor
// about the target center. Grow runs 0 <-> amount (default 1x),
// shrink runs amount <-> 1 (default 1.5x); times past the clip hold
// the end state, so grow-in lands on the chosen size. Commits flow
// through DocAnim (undoable); scrubs coalesce through doc transactions.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})

    spacing: 8

    Text {
        text: section.clip && section.clip.preset === "shrink" ? qsTr("Peak size") : qsTr("Grow size")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: "×"
        scrubStep: 0.05
        minimum: 0
        maximum: 100
        value: Number(section.opts.amount !== undefined ? section.opts.amount : (section.clip && section.clip.preset === "shrink" ? 1.5 : 1)) || 0
        onCommitted: v => section.setOption("amount", v)
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
