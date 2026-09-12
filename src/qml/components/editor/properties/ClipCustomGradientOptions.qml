import QtQuick
import QtQuick.Layouts
import Totm

// Custom Gradient editor: fill-gradient stop colors + angle from-to.
// Absolute values give exact control; the gallery seeds From from the
// live selection so new clips start jump-free.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})

    spacing: 8

    Text {
        text: qsTr("From stops")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: String(section.opts.fromC1 || "#000000")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.fromC1 || "#000000")
            onCommitted: c => section.setOption("fromC1", c)
        }

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: String(section.opts.fromC2 || "#ffffff")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.fromC2 || "#ffffff")
            onCommitted: c => section.setOption("fromC2", c)
        }
    }

    NumberField {
        Layout.fillWidth: true
        prefix: qsTr("A")
        suffix: qsTr("°")
        minimum: 0
        maximum: 360
        scrubStep: 1
        value: Number(section.opts.fromAngle) || 0
        onCommitted: v => section.setOption("fromAngle", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("To stops")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: String(section.opts.toC1 || "#000000")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.toC1 || "#000000")
            onCommitted: c => section.setOption("toC1", c)
        }

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: String(section.opts.toC2 || "#ff0000")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.toC2 || "#ff0000")
            onCommitted: c => section.setOption("toC2", c)
        }
    }

    NumberField {
        Layout.fillWidth: true
        prefix: qsTr("A")
        suffix: qsTr("°")
        minimum: 0
        maximum: 360
        scrubStep: 1
        value: Number(section.opts.toAngle) || 0
        onCommitted: v => section.setOption("toAngle", v)
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
