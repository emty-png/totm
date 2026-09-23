import QtQuick
import QtQuick.Layouts
import Totm

// Dash/gap pair editor shared by solid and gradient stroke clips.
// Width units with 0 as solid; the pair lerps continuously, so a
// solid<->dashed morph passes through dots.
ColumnLayout {
    id: dash

    required property var doc
    required property int clipId
    required property var opts

    spacing: 8
    Layout.fillWidth: true

    Text {
        text: qsTr("From dash / gap (width units, 0 = solid)")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "D"
            minimum: 0
            maximum: 100
            value: Number(dash.opts.fromDash) || 0
            onCommitted: v => dash.setOption("fromDash", v)
            onScrubStarted: dash.beginScrub()
            onScrubFinished: dash.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "G"
            minimum: 0
            maximum: 100
            value: Number(dash.opts.fromGap) || 0
            onCommitted: v => dash.setOption("fromGap", v)
            onScrubStarted: dash.beginScrub()
            onScrubFinished: dash.endScrub()
        }
    }

    Text {
        text: qsTr("To dash / gap (width units, 0 = solid)")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "D"
            minimum: 0
            maximum: 100
            value: Number(dash.opts.toDash) || 0
            onCommitted: v => dash.setOption("toDash", v)
            onScrubStarted: dash.beginScrub()
            onScrubFinished: dash.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "G"
            minimum: 0
            maximum: 100
            value: Number(dash.opts.toGap) || 0
            onCommitted: v => dash.setOption("toGap", v)
            onScrubStarted: dash.beginScrub()
            onScrubFinished: dash.endScrub()
        }
    }

    function setOption(role, value) {
        if (!dash.doc)
            return;
        var patch = {};
        patch[role] = value;
        dash.doc.setClipOptions(dash.clipId, patch);
    }

    function beginScrub() {
        if (dash.doc)
            dash.doc.beginTransaction();
    }

    function endScrub() {
        if (dash.doc)
            dash.doc.endTransaction();
    }
}
