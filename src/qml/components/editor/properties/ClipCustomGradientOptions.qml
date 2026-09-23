import QtQuick
import QtQuick.Layouts
import Totm

// Custom Gradient editor: fill- or stroke-gradient stop colors +
// angle from-to, plus entry opacity. Absolute values give exact
// control; the gallery seeds From from the live selection so new clips
// start jump-free. gradientKind picks the stack ("fill" default,
// "stroke" for the new stroke-gradient clip); both target entry 0.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId
    property string gradientKind: "fill"

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property var entryDefaults: DocCustomDefaults {}
    readonly property string entryKind: section.gradientKind === "stroke" ? "strokes" : "fills"
    readonly property var targetTop: {
        if (section.doc)
            section.doc.rev;
        if (!section.doc || !section.clip)
            return null;
        var n = section.doc.findNode(section.clip.targetUid);
        if (!n)
            return null;
        if (n.kind === "shape")
            return n;
        var leaves = section.doc._leavesUnder(n);
        return leaves.length > 0 ? leaves[0] : null;
    }

    spacing: 8

    Text {
        text: section.gradientKind === "stroke" ? qsTr("Stroke entry") : qsTr("Fill entry")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    PanelDropdown {
        Layout.fillWidth: true
        options: section.entryOptions()
        currentId: String(section.entryIndex())
        onPicked: id => section.retargetEntry(Number(id))
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

    function entryIndex() {
        var raw = section.gradientKind === "stroke" ? section.opts.strokeIndex : section.opts.fillIndex;
        if (raw === undefined)
            return 0;
        var n = Math.round(Number(raw));
        if (isNaN(n))
            return 0;
        return Math.min(32, Math.max(0, n));
    }

    function entryOptions() {
        var out = [];
        var list = (section.targetTop && section.targetTop[section.entryKind]) || [];
        var base = section.gradientKind === "stroke" ? qsTr("Stroke ") : qsTr("Fill ");
        for (var i = 0; i < list.length; i++) {
            var e = list[i] || {};
            out.push({
                id: String(i),
                name: base + (i + 1) + (e.enabled === false ? qsTr(" (off)") : "")
            });
        }
        if (out.length === 0)
            out.push({
                id: "0",
                name: base + "1"
            });
        return out;
    }

    // Retarget onto another entry: From reseeds from the live entry
    // (no jump at clip start), To stays user-edited, one undo entry.
    function retargetEntry(i) {
        if (!section.doc || !section.clip || i === section.entryIndex())
            return;
        var node = section.doc.findNode(section.clip.targetUid);
        var tops = node ? [node] : [];
        var patch = section.entryDefaults.fromPatchForEntry(section.doc.anim.presets, section.doc, tops, section.clip.preset, i);
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
