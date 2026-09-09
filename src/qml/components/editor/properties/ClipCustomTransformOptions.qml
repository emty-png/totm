import QtQuick
import QtQuick.Layouts
import Totm

// Custom Transform editors: Scale (uniform factor), Rotate (offset deg),
// Move (relative offset px). From-to values lerp with easing; scale and
// move derive from base so clips stay valid when nodes move after apply.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property string preset: section.clip ? section.clip.preset : ""

    spacing: 8

    Text {
        visible: section.preset === "customScale" || section.preset === "customRotate"
        text: qsTr("From")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.preset === "customScale"
        Layout.fillWidth: true
        suffix: "×"
        minimum: 0
        maximum: 10
        scrubStep: 0.05
        value: Number(section.opts.from) || 0
        onCommitted: v => section.setOption("from", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    NumberField {
        visible: section.preset === "customRotate"
        Layout.fillWidth: true
        suffix: "°"
        minimum: -1440
        maximum: 1440
        value: Number(section.opts.from) || 0
        onCommitted: v => section.setOption("from", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        visible: section.preset === "customScale" || section.preset === "customRotate"
        text: qsTr("To")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.preset === "customScale"
        Layout.fillWidth: true
        suffix: "×"
        minimum: 0
        maximum: 10
        scrubStep: 0.05
        value: Number(section.opts.to) || 0
        onCommitted: v => section.setOption("to", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    NumberField {
        visible: section.preset === "customRotate"
        Layout.fillWidth: true
        suffix: "°"
        minimum: -1440
        maximum: 1440
        value: Number(section.opts.to) || 0
        onCommitted: v => section.setOption("to", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        visible: section.preset === "customMove"
        text: qsTr("From offset")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customMove"
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "X"
            suffix: qsTr("px")
            minimum: -2000
            maximum: 2000
            value: Number(section.opts.fromX) || 0
            onCommitted: v => section.setOption("fromX", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "Y"
            suffix: qsTr("px")
            minimum: -2000
            maximum: 2000
            value: Number(section.opts.fromY) || 0
            onCommitted: v => section.setOption("fromY", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    Text {
        visible: section.preset === "customMove"
        text: qsTr("To offset")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customMove"
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "X"
            suffix: qsTr("px")
            minimum: -2000
            maximum: 2000
            value: Number(section.opts.toX) || 0
            onCommitted: v => section.setOption("toX", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "Y"
            suffix: qsTr("px")
            minimum: -2000
            maximum: 2000
            value: Number(section.opts.toY) || 0
            onCommitted: v => section.setOption("toY", v)
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
