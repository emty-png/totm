import QtQuick
import QtQuick.Layouts
import Totm

// Custom Gradient editor: fill- or stroke-gradient stop colors +
// angle from-to, plus entry opacity. Stroke gradients also carry width,
// dash pair and position like the solid Stroke clip: width/dash lerp,
// position steps at the midpoint. Absolute values give exact control;
// the gallery seeds From from the live selection so new clips start
// jump-free. gradientKind picks the stack ("fill" default, "stroke" for
// the stroke-gradient clip); both target any entry with a dropdown.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId
    property string gradientKind: "fill"

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property string entryKind: section.gradientKind === "stroke" ? "strokes" : "fills"

    spacing: 8

    ClipEntryDropdown {
        doc: section.doc
        clip: section.clip
        clipId: section.clipId
        entryKind: section.entryKind
    }

    Text {
        text: qsTr("From stops")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        Rectangle {
            id: fromStop1

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: String(section.opts.fromC1 || "#000000")
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => section.openStopPicker("fromC1", String(section.opts.fromC1 || "#000000"), fromStop1, mouse.x, mouse.y)
            }
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.fromC1 || "#000000")
            onCommitted: c => section.setOption("fromC1", c)
        }

        Rectangle {
            id: fromStop2

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: String(section.opts.fromC2 || "#ffffff")
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => section.openStopPicker("fromC2", String(section.opts.fromC2 || "#ffffff"), fromStop2, mouse.x, mouse.y)
            }
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.fromC2 || "#ffffff")
            onCommitted: c => section.setOption("fromC2", c)
        }
    }

    NumberField {
        Layout.fillWidth: true
        prefix: qsTr("A")
        suffix: qsTr("°")
        minimum: 0
        maximum: 360
        scrubStep: 1
        value: Number(section.opts.fromAngle) || 0
        onCommitted: v => section.setOption("fromAngle", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("To stops")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        Rectangle {
            id: toStop1

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: String(section.opts.toC1 || "#000000")
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => section.openStopPicker("toC1", String(section.opts.toC1 || "#000000"), toStop1, mouse.x, mouse.y)
            }
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.toC1 || "#000000")
            onCommitted: c => section.setOption("toC1", c)
        }

        Rectangle {
            id: toStop2

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: String(section.opts.toC2 || "#ff0000")
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => section.openStopPicker("toC2", String(section.opts.toC2 || "#ff0000"), toStop2, mouse.x, mouse.y)
            }
        }

        HexField {
            Layout.fillWidth: true
            value: String(section.opts.toC2 || "#ff0000")
            onCommitted: c => section.setOption("toC2", c)
        }
    }

    NumberField {
        Layout.fillWidth: true
        prefix: qsTr("A")
        suffix: qsTr("°")
        minimum: 0
        maximum: 360
        scrubStep: 1
        value: Number(section.opts.toAngle) || 0
        onCommitted: v => section.setOption("toAngle", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("From opacity")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        minimum: 0
        maximum: 1
        scrubStep: 0.05
        value: section.opts.fromOpacity !== undefined ? Number(section.opts.fromOpacity) : 1
        onCommitted: v => section.setOption("fromOpacity", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("To opacity")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        Layout.fillWidth: true
        minimum: 0
        maximum: 1
        scrubStep: 0.05
        value: section.opts.toOpacity !== undefined ? Number(section.opts.toOpacity) : 1
        onCommitted: v => section.setOption("toOpacity", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        visible: section.gradientKind === "stroke"
        text: qsTr("From width")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.gradientKind === "stroke"
        Layout.fillWidth: true
        suffix: qsTr("px")
        minimum: 0
        maximum: 100
        value: Number(section.opts.from) || 0
        onCommitted: v => section.setOption("from", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        visible: section.gradientKind === "stroke"
        text: qsTr("To width")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.gradientKind === "stroke"
        Layout.fillWidth: true
        suffix: qsTr("px")
        minimum: 0
        maximum: 100
        value: Number(section.opts.to) || 0
        onCommitted: v => section.setOption("to", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    ClipDashPair {
        visible: section.gradientKind === "stroke"
        doc: section.doc
        clipId: section.clipId
        opts: section.opts
    }

    ClipPositionSwitch {
        visible: section.gradientKind === "stroke"
        label: qsTr("From position")
        position: section.opts.fromPosition
        doc: section.doc
        clipId: section.clipId
        optionRole: "fromPosition"
    }

    ClipPositionSwitch {
        visible: section.gradientKind === "stroke"
        label: qsTr("To position")
        position: section.opts.toPosition
        doc: section.doc
        clipId: section.clipId
        optionRole: "toPosition"
    }

    function setOption(role, value) {
        if (!section.doc)
            return;
        var patch = {};
        patch[role] = value;
        section.doc.setClipOptions(section.clipId, patch);
    }

    // Solid picker for the stop wells (stops are solid colors): the
    // well seeds the popup, drags stream through one scrub
    // transaction, typed hex commits discretely on its own.
    function openStopPicker(role, color, anchor, ax, ay) {
        section.pickerRole = role;
        stopPicker.openFor(color, anchor, ax, ay);
    }

    function beginScrub() {
        if (section.doc)
            section.doc.beginTransaction();
    }

    function endScrub() {
        if (section.doc)
            section.doc.endTransaction();
    }

    // Option key the picker popup is editing
    // ("fromC1"/"fromC2"/"toC1"/"toC2").
    property string pickerRole: ""

    ColorPickerPopup {
        id: stopPicker

        onScrubStarted: section.beginScrub()
        onCommitted: c => {
            if (section.pickerRole !== "")
                section.setOption(section.pickerRole, String(c));
        }
        onScrubFinished: section.endScrub()
    }
}
