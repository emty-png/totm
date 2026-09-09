import QtQuick
import QtQuick.Layouts
import Totm

// Slide / Move & Scale clip options: direction, distance, start scale
// (movescale) and the built-in fade switch (slide). Commits flow through
// DocAnim (undoable); scrubs coalesce through doc transactions.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property bool isMoveScale: !!section.clip && section.clip.preset === "movescale"

    spacing: 8

    Text {
        text: qsTr("Direction")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
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
        text: qsTr("Distance")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("px")
        minimum: 0
        maximum: 2000
        value: section.opts.distance || 0
        onCommitted: v => section.setOption("distance", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        visible: section.isMoveScale
        text: qsTr("Scale")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.isMoveScale
        Layout.fillWidth: true
        suffix: "%"
        minimum: 0
        maximum: 150
        value: section.opts.scale || 0
        onCommitted: v => section.setOption("scale", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    RowLayout {
        visible: !section.isMoveScale
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Fade")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: 11
            color: section.opts.fade !== false ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: section.opts.fade !== false ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: section.opts.fade !== false ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: 8
                color: section.opts.fade !== false ? AppTheme.background : AppTheme.muted

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
                onClicked: section.setOption("fade", !(section.opts.fade !== false))
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
