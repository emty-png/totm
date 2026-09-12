import QtQuick
import QtQuick.Layouts
import Totm

// Custom Grain editor: amount and size from-to. Absolute values give
// exact control; the gallery seeds From from the live selection so new
// clips start jump-free. The noise seed follows the transport clock on
// both sides, so it is never stored in the clip.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})

    spacing: 8

    Text {
        text: qsTr("From")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "S"
            suffix: qsTr("px")
            minimum: 1
            maximum: 10
            value: Number(section.opts.fromSize) || 0
            onCommitted: v => section.setOption("fromSize", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            suffix: "%"
            minimum: 0
            maximum: 100
            value: Math.round(Number(section.opts.fromAmount || 0) * 100)
            onCommitted: v => section.setOption("fromAmount", v / 100)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    Text {
        text: qsTr("To")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "S"
            suffix: qsTr("px")
            minimum: 1
            maximum: 10
            value: Number(section.opts.toSize) || 0
            onCommitted: v => section.setOption("toSize", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            suffix: "%"
            minimum: 0
            maximum: 100
            value: Math.round(Number(section.opts.toAmount || 0) * 100)
            onCommitted: v => section.setOption("toAmount", v / 100)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
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
