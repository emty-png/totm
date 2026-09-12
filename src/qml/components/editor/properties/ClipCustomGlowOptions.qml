import QtQuick
import QtQuick.Layouts
import Totm

// Custom Glow editor: color, blur and spread from-to plus the inner
// toggle. Absolute values give exact control; the gallery seeds From
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
            color: String(section.opts.fromColor || "#cc00ffff")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.fromColor || "#cc00ffff")
            onCommitted: c => section.setOption("fromColor", c)
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

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Inner glow")
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
            color: String(section.opts.toColor || "#cc00ffff")
            border.width: 1
            border.color: AppTheme.border
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.toColor || "#cc00ffff")
            onCommitted: c => section.setOption("toColor", c)
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

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Inner glow")
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
