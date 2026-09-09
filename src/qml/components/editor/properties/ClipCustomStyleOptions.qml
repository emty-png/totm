import QtQuick
import QtQuick.Layouts
import Totm

// Custom Style editors: Opacity (absolute 0-1) and Color (fill hex
// from-to). Absolute values give exact control; the gallery seeds From
// from the live selection so new clips start jump-free.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property string preset: section.clip ? section.clip.preset : ""

    spacing: 8

    Text {
        visible: section.preset === "customOpacity" || section.preset === "customColor"
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
            radius: 6
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
        visible: section.preset === "customOpacity" || section.preset === "customColor"
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
            radius: 6
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
