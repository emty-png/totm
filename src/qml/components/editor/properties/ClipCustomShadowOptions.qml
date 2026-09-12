import QtQuick
import QtQuick.Layouts
import Totm

// Custom Shadow editor: outer-shadow color, offsets, blur and spread
// from-to. Absolute values give exact control; the gallery seeds From
// from the live selection so new clips start jump-free.
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

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: String(section.opts.fromColor || "#80000000")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: section.hexOf(section.opts.fromColor)
            onCommitted: c => section.setOption("fromColor", section.withAlpha(c, section.opts.fromColor))
        }
    }

    RowLayout {
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "X"
            suffix: qsTr("px")
            minimum: -500
            maximum: 500
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
            minimum: -500
            maximum: 500
            value: Number(section.opts.fromY) || 0
            onCommitted: v => section.setOption("fromY", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Inner shadow")
            font.pixelSize: 12
            color: AppTheme.foreground
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: 11
            color: (section.opts.fromInner === true) ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: (section.opts.fromInner === true) ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: (section.opts.fromInner === true) ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: 8
                color: (section.opts.fromInner === true) ? AppTheme.background : AppTheme.muted
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("fromInner", !(section.opts.fromInner === true))
            }
        }
    }

    RowLayout {
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "B"
            suffix: qsTr("px")
            minimum: 0
            maximum: 100
            value: Number(section.opts.fromBlur) || 0
            onCommitted: v => section.setOption("fromBlur", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "S"
            suffix: qsTr("px")
            minimum: 0
            maximum: 50
            value: Number(section.opts.fromSpread) || 0
            onCommitted: v => section.setOption("fromSpread", v)
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

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: String(section.opts.toColor || "#80000000")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: section.hexOf(section.opts.toColor)
            onCommitted: c => section.setOption("toColor", section.withAlpha(c, section.opts.toColor))
        }
    }

    RowLayout {
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "X"
            suffix: qsTr("px")
            minimum: -500
            maximum: 500
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
            minimum: -500
            maximum: 500
            value: Number(section.opts.toY) || 0
            onCommitted: v => section.setOption("toY", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Inner shadow")
            font.pixelSize: 12
            color: AppTheme.foreground
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: 11
            color: (section.opts.toInner === true) ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: (section.opts.toInner === true) ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: (section.opts.toInner === true) ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: 8
                color: (section.opts.toInner === true) ? AppTheme.background : AppTheme.muted
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("toInner", !(section.opts.toInner === true))
            }
        }
    }

    RowLayout {
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "B"
            suffix: qsTr("px")
            minimum: 0
            maximum: 100
            value: Number(section.opts.toBlur) || 0
            onCommitted: v => section.setOption("toBlur", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "S"
            suffix: qsTr("px")
            minimum: 0
            maximum: 50
            value: Number(section.opts.toSpread) || 0
            onCommitted: v => section.setOption("toSpread", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    // Hex fields speak opaque rgb: split/combine alpha around them.
    function hexOf(c) {
        var t = String(c || "#80000000").toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (t.length === 8)
            return "#" + t.slice(2);
        return "#" + t;
    }

    function withAlpha(hex, keep) {
        var t = String(hex).toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (t.length === 3)
            t = t.charAt(0) + t.charAt(0) + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2);
        if (!/^[0-9a-f]{6}$/.test(t))
            t = "000000";
        var k = String(keep || "").toLowerCase();
        if (k.charAt(0) === "#")
            k = k.slice(1);
        if (k.length === 8)
            return "#" + k.slice(0, 2) + t;
        return "#" + t;
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
