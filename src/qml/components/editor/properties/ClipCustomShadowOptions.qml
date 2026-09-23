import QtQuick
import QtQuick.Layouts
import Totm

// Custom Shadow editor: outer/inner-shadow color, offsets, blur and
// spread from-to. Absolute values give exact control; the gallery seeds
// From from the live selection so new clips start jump-free. Targets any
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
        entryKind: "shadows"
    }

    ColorPickerPopup {
        id: colorPicker

        onScrubStarted: section.beginScrub()
        onCommitted: c => {
            if (section.pickerRole === "")
                return;
            var cur = section.pickerRole === "fromColor" ? section.opts.fromColor : section.opts.toColor;
            section.setOption(section.pickerRole, fromWell.withAlpha(String(c), cur));
        }
        onScrubFinished: section.endScrub()
    }

    Text {
        text: qsTr("From")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    ClipAlphaWell {
        id: fromWell

        colorValue: section.opts.fromColor
        defaultColor: "#80000000"
        doc: section.doc
        clipId: section.clipId
        optionRole: "fromColor"
        onSwatchClicked: (role, rgb, anchor, ax, ay) => section.openPicker(role, rgb, anchor, ax, ay)
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

    ClipAlphaWell {
        colorValue: section.opts.toColor
        defaultColor: "#80000000"
        doc: section.doc
        clipId: section.clipId
        optionRole: "toColor"
        onSwatchClicked: (role, rgb, anchor, ax, ay) => section.openPicker(role, rgb, anchor, ax, ay)
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

    function setOption(role, value) {
        if (!section.doc)
            return;
        var patch = {};
        patch[role] = value;
        section.doc.setClipOptions(section.clipId, patch);
    }

    // Solid picker for the color wells: the well seeds the popup
    // (opaque rgb; the stored alpha rides through withAlpha like the
    // hex path), drags stream through one scrub transaction, typed
    // hex commits discretely on its own.
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
