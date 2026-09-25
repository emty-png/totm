import QtQuick
import QtQuick.Layouts
import Totm

// Mask wipe / iris clip options: reveal direction (wipe), soft edge,
// invert. Commits flow through DocAnim (undoable). Keyframes live in
// the sibling Keyframes section below.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property bool isWipe: !!section.clip && section.clip.preset === "maskWipe"

    spacing: 8

    Text {
        visible: section.isWipe
        text: qsTr("Reveal from")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.isWipe
        spacing: 8

        SegmentedOption {
            label: qsTr("Left")
            active: section.opts.direction === "left" || !section.opts.direction
            onClicked: section.setOption("direction", "left")
        }

        SegmentedOption {
            label: qsTr("Right")
            active: section.opts.direction === "right"
            onClicked: section.setOption("direction", "right")
        }

        SegmentedOption {
            label: qsTr("Up")
            active: section.opts.direction === "up"
            onClicked: section.setOption("direction", "up")
        }

        SegmentedOption {
            label: qsTr("Down")
            active: section.opts.direction === "down"
            onClicked: section.setOption("direction", "down")
        }
    }

    Text {
        text: qsTr("Feather")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("px")
        minimum: 0
        maximum: 100
        value: section.opts.feather || 0
        onCommitted: v => section.setOption("feather", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Invert")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: AppTheme.radiusLarge
            color: section.opts.invert === true ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: section.opts.invert === true ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: section.opts.invert === true ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
                color: section.opts.invert === true ? AppTheme.background : AppTheme.muted

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
                onClicked: section.setOption("invert", !(section.opts.invert === true))
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
