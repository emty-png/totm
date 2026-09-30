import QtQuick
import QtQuick.Layouts
import Totm

// Typewriter clip options: reveal unit (letters/words/lines), speed,
// cursor and karaoke/sweep styling (stagger overlap, rise, highlight,
// moving band). Speed paces the clip: committing cps retimes the
// duration to cover the target text, so typing lands exactly at the
// tail. Lane stretches afterwards intentionally deviate (like slide
// distance), staying put until cps is touched again.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})

    spacing: 8

    Text {
        text: qsTr("Reveal")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        SegmentedOption {
            label: qsTr("Letters")
            active: section.opts.unit === "letters" || !section.opts.unit
            onClicked: section.setOption("unit", "letters")
        }

        SegmentedOption {
            label: qsTr("Words")
            active: section.opts.unit === "words"
            onClicked: section.setOption("unit", "words")
        }

        SegmentedOption {
            label: qsTr("Lines")
            active: section.opts.unit === "lines"
            onClicked: section.setOption("unit", "lines")
        }
    }

    Text {
        text: qsTr("Speed")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("cps")
        minimum: 1
        maximum: 120
        value: Number(section.opts.cps) > 0 ? Number(section.opts.cps) : 20
        onCommitted: v => section.setCps(v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Cursor")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: AppTheme.radiusLarge
            color: section.opts.cursor === true ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: section.opts.cursor === true ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: section.opts.cursor === true ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
                color: section.opts.cursor === true ? AppTheme.background : AppTheme.muted

                Behavior on x {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("cursor", !(section.opts.cursor === true))
            }
        }
    }

    Text {
        text: qsTr("Stagger")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: ""
        minimum: 0
        maximum: 1
        scrubStep: 0.05
        value: Number(section.opts.stagger) || 0
        onCommitted: v => section.setOption("stagger", Math.min(1, Math.max(0, Number(v) || 0)))
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("Rise")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("px")
        minimum: 0
        maximum: 100
        value: Number(section.opts.rise) || 0
        onCommitted: v => section.setOption("rise", Math.min(100, Math.max(0, Number(v) || 0)))
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Highlight")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: AppTheme.radiusLarge
            color: (section.opts.highlight || "") !== "" ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: (section.opts.highlight || "") !== "" ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: (section.opts.highlight || "") !== "" ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
                color: (section.opts.highlight || "") !== "" ? AppTheme.background : AppTheme.muted

                Behavior on x {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("highlight", (section.opts.highlight || "") !== "" ? "" : "#ffcc00")
            }
        }
    }

    HexField {
        Layout.fillWidth: true
        visible: (section.opts.highlight || "") !== ""
        value: String(section.opts.highlight || "#ffcc00")
        onCommitted: c => section.setOption("highlight", c)
    }

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Sweep band")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: AppTheme.radiusLarge
            color: section.opts.sweep === true ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: section.opts.sweep === true ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: section.opts.sweep === true ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
                color: section.opts.sweep === true ? AppTheme.background : AppTheme.muted

                Behavior on x {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("sweep", !(section.opts.sweep === true))
            }
        }
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: qsTr("Stagger/rise/highlight/sweep render per-unit karaoke; empty highlight disables recolor.")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    // Longest target text in chars (groups count their longest leaf).
    // Units still pace by chars, so words/lines share this duration.
    function textLen() {
        if (!section.doc || !section.clip)
            return 0;
        var node = section.doc.findNode(section.clip.targetUid);
        if (!node)
            return 0;
        var leaves = node.kind === "group" ? section.doc._leavesUnder(node) : [node];
        var best = 0;
        for (var i = 0; i < leaves.length; i++) {
            if (leaves[i].shapeType !== "text")
                continue;
            var len = String(leaves[i].textContent || "").length;
            if (len > best)
                best = len;
        }
        return best;
    }

    function setOption(role, value) {
        if (!section.doc)
            return;
        var patch = {};
        patch[role] = value;
        section.doc.setClipOptions(section.clipId, patch);
    }

    // cps lands as a second undo entry after the option (no combined
    // options+retime API exists); acceptable like timing edits nearby.
    function setCps(v) {
        section.setOption("cps", v);
        if (!section.doc || !section.clip)
            return;
        var len = section.textLen();
        if (len <= 0)
            return;
        var dur = Math.min(1800, Math.max(0.5, len / Math.max(1, v)));
        section.doc.retimeClip(section.clipId, section.clip.t0, dur);
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
