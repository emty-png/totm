import QtQuick
import QtQuick.Layouts
import Totm

// Stroke position switch for one clip side. Position steps at the
// midpoint, so there is nothing to scrub, only a choice.
ColumnLayout {
    id: pos

    required property string label
    required property var position
    required property var doc
    required property int clipId
    required property string optionRole

    spacing: 8
    Layout.fillWidth: true

    Text {
        text: pos.label
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        SegmentedOption {
            label: qsTr("Center")
            active: (pos.position || "center") === "center"
            onClicked: pos.setOption(pos.optionRole, "center")
        }

        SegmentedOption {
            label: qsTr("Inside")
            active: pos.position === "inside"
            onClicked: pos.setOption(pos.optionRole, "inside")
        }

        SegmentedOption {
            label: qsTr("Outside")
            active: pos.position === "outside"
            onClicked: pos.setOption(pos.optionRole, "outside")
        }
    }

    function setOption(role, value) {
        if (!pos.doc)
            return;
        var patch = {};
        patch[role] = value;
        pos.doc.setClipOptions(pos.clipId, patch);
    }
}
