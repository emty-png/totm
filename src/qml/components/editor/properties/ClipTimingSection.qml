import QtQuick
import QtQuick.Layouts
import Totm

// Clip timing: duration plus the easing row that opens the graph editor
// through graphPolicy. Commits flow through DocAnim (undoable); scrubs
// coalesce through doc transactions.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    property var graphPolicy: null

    // clipRev keeps this live through lane drags: nudgeClip mutates
    // plain clip objects in place (no touch, no array rebuild, so lane
    // delegates survive), which plain-field bindings would never see.
    readonly property var clip: {
        if (!section.doc)
            return null;
        section.doc.anim.clipRev;
        return section.doc.animClip(section.clipId);
    }

    spacing: 8

    Text {
        text: qsTr("Duration")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        suffix: qsTr("s")
        scrubStep: 0.1
        minimum: 0.1
        maximum: 60
        value: section.clip ? section.clip.duration : 0.8
        onCommitted: v => section.retime(v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("Easing")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        radius: 6
        color: easingMouse.containsMouse || easingMouse.pressed ? AppTheme.hover : AppTheme.surface
        border.width: 1
        border.color: AppTheme.fieldBorder

        Text {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 8
                rightMargin: 8
            }
            text: section.easingName()
            font.pixelSize: 12
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        MouseArea {
            id: easingMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (section.graphPolicy)
                    section.graphPolicy();
            }
        }
    }

    function easingName() {
        if (!section.clip || !section.doc)
            return "";
        return section.doc.anim.presets.easingName(section.clip.easing.id);
    }

    function retime(v) {
        if (section.doc && section.clip)
            section.doc.retimeClip(section.clipId, section.clip.t0, v);
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
