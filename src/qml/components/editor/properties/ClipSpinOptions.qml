import QtQuick
import QtQuick.Layouts
import Totm

// Spin / Twist clip options: direction plus turn count (spin).
// Commits flow through DocAnim (undoable); scrubs coalesce through
// doc transactions.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property bool isSpin: !!section.clip && section.clip.preset === "spin"

    spacing: 8

    Text {
        text: qsTr("Direction")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        SegOption {
            label: qsTr("CW")
            active: section.opts.direction !== "ccw"
            onClicked: section.setOption("direction", "cw")
        }

        SegOption {
            label: qsTr("CCW")
            active: section.opts.direction === "ccw"
            onClicked: section.setOption("direction", "ccw")
        }
    }

    Text {
        visible: section.isSpin
        text: qsTr("Turns")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.isSpin
        Layout.fillWidth: true
        suffix: "×"
        minimum: 0.25
        maximum: 10
        scrubStep: 0.25
        value: section.opts.turns || 1
        onCommitted: v => section.setOption("turns", v)
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
