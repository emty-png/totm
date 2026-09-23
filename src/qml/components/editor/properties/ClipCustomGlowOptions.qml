import QtQuick
import QtQuick.Layouts
import Totm

// Custom Glow editor: color, blur and spread from-to plus the inner
// toggle. Absolute values give exact control; the gallery seeds From
// from the live selection so new clips start jump-free. Targets any
// stack entry (index 0 = top) with a dropdown that reseeds From only.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    // Option key the picker popup is editing ("fromColor"/"toColor").
    property string pickerRole: ""

    spacing: 8

    ClipEntryDropdown {
        doc: section.doc
        clip: section.clip
        clipId: section.clipId
        entryKind: "glows"
    }

    ColorPickerPopup {
        id: colorPicker

        onScrubStarted: section.beginScrub()
        onCommitted: c => {
            if (section.pickerRole === "")
                return;
            var cur = section.pickerRole === "fromColor" ? section.opts.fromColor : section.opts.toColor;
            section.setOption(section.pickerRole, section.withAlpha(String(c), cur));
        }
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("From")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        Rectangle {
            id: fromSwatch

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: String(section.opts.fromColor || "#cc00ffff")
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => section.openPicker("fromColor", section.hexOf(section.opts.fromColor), fromSwatch, mouse.x, mouse.y)
            }
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
            radius: AppTheme.radiusLarge
            color: (section.opts.fromInner === true) ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: (section.opts.fromInner === true) ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: (section.opts.fromInner === true) ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
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
            id: toSwatch

            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: String(section.opts.toColor || "#cc00ffff")
            border.width: 1
            border.color: AppTheme.border

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => section.openPicker("toColor", section.hexOf(section.opts.toColor), toSwatch, mouse.x, mouse.y)
            }
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
            radius: AppTheme.radiusLarge
            color: (section.opts.toInner === true) ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: (section.opts.toInner === true) ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: (section.opts.toInner === true) ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
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

    // Hex fields speak opaque rgb: split/combine alpha around them.
    function hexOf(c) {
        var t = String(c || "#cc00ffff").toLowerCase();
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

    // Solid picker for the color wells: the well seeds the popup
    // (opaque rgb; the stored alpha rides through withAlpha like the
    // shadow editor), drags stream through one scrub transaction.
    function openPicker(role, color, anchor, ax, ay) {
        section.pickerRole = role;
        colorPicker.openFor(color, anchor, ax, ay);
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
