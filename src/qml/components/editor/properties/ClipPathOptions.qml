import QtQuick
import QtQuick.Layouts
import Totm

// Motion-path clip options: follow-rotation and closed-loop toggles
// plus redraw (re-enters canvas draw mode with the current trajectory
// loaded). Points live in the clip as relative offsets from the path
// start (first point 0,0), sampled by arc length so drawing location
// never moves the shape's start.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    property var redrawPolicy: null

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})

    spacing: 8

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Follow rotation")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: 11
            color: section.opts.orient === true ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: section.opts.orient === true ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: section.opts.orient === true ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: 8
                color: section.opts.orient === true ? AppTheme.background : AppTheme.muted
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("orient", !(section.opts.orient === true))
            }
        }
    }

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Closed loop")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: 11
            color: section.opts.closed === true ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: section.opts.closed === true ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: section.opts.closed === true ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: 8
                color: section.opts.closed === true ? AppTheme.background : AppTheme.muted
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("closed", !(section.opts.closed === true))
            }
        }
    }

    // Edit action: enters canvas draw mode with the current trajectory
    // loaded for full point editing (move/bend/insert/remove); Enter
    // replaces it, Esc keeps it.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: 6
        color: redrawMouse.containsMouse || redrawMouse.pressed ? AppTheme.hover : AppTheme.surface
        border.width: 1
        border.color: AppTheme.fieldBorder

        Behavior on color {
            ColorAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 8

            AppIcon {
                anchors.verticalCenter: parent.verticalCenter
                kind: "pen"
                width: 14
                height: 14
                iconColor: AppTheme.foreground
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Edit path")
                font.pixelSize: 12
                color: AppTheme.foreground
            }
        }

        MouseArea {
            id: redrawMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (section.redrawPolicy)
                    section.redrawPolicy();
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
}
