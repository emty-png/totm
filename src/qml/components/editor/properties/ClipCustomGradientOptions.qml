import QtQuick
import QtQuick.Layouts
import Totm

// Custom Gradient editor: fill- or stroke-gradient stop colors +
// angle from-to, plus entry opacity. Absolute values give exact
// control; the gallery seeds From from the live selection so new clips
// start jump-free. gradientKind picks the stack ("fill" default,
// "stroke" for the new stroke-gradient clip); both target entry 0.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId
    property string gradientKind: "fill"

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
            radius: AppTheme.radiusSmall
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
            radius: AppTheme.radiusSmall
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
            radius: AppTheme.radiusSmall
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
            radius: AppTheme.radiusSmall
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

    Text {
        text: qsTr("From opacity")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
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
        text: qsTr("To opacity")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
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
