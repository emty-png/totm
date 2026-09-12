import QtQuick
import QtQuick.Layouts
import Totm

// Custom Blur editors: Layer Blur and Background Blur share radius
// (px) plus opacity (strength) from-to. Absolute values give exact
// control; the gallery seeds From from the live selection.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId
    required property string blurKind

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property bool isBackground: section.blurKind === "backgroundBlur"

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
            prefix: "R"
            suffix: qsTr("px")
            minimum: 0
            maximum: 100
            value: Number(section.opts.fromRadius) || 0
            onCommitted: v => section.setOption("fromRadius", v)
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
            value: Math.round(Number(section.opts.fromOpacity ?? (section.isBackground ? 0.7 : 1)) * 100)
            onCommitted: v => section.setOption("fromOpacity", v / 100)
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
            prefix: "R"
            suffix: qsTr("px")
            minimum: 0
            maximum: 100
            value: Number(section.opts.toRadius) || 0
            onCommitted: v => section.setOption("toRadius", v)
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
            value: Math.round(Number(section.opts.toOpacity ?? (section.isBackground ? 0.7 : 1)) * 100)
            onCommitted: v => section.setOption("toOpacity", v / 100)
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
