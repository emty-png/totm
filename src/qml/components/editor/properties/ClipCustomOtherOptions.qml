import QtQuick
import QtQuick.Layouts
import Totm

// Custom Other editors: Hide/Show (stepped bools), Flip axis (stepped
// mirror), Resize (absolute box), Corner Radius and Stroke width
// (absolute px). Stroke clips also carry entry opacity, dash pair and
// position: width/opacity/dash lerp, position steps at the midpoint.
// Resize centers on each leaf's own center; corner writes
// all four when independent is on. Stroke targets any stack entry.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property string preset: section.clip ? section.clip.preset : ""

    spacing: 8

    Text {
        visible: section.preset === "customHide"
        text: qsTr("From visible")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customHide"
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: (section.opts.fromVisible !== false) ? qsTr("Shown") : qsTr("Hidden")
            font.pixelSize: 12
            color: AppTheme.foreground
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: AppTheme.radiusLarge
            color: (section.opts.fromVisible !== false) ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: (section.opts.fromVisible !== false) ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: (section.opts.fromVisible !== false) ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
                color: (section.opts.fromVisible !== false) ? AppTheme.background : AppTheme.muted
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("fromVisible", !(section.opts.fromVisible !== false))
            }
        }
    }

    Text {
        visible: section.preset === "customHide"
        text: qsTr("To visible")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customHide"
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: (section.opts.toVisible === true) ? qsTr("Shown") : qsTr("Hidden")
            font.pixelSize: 12
            color: AppTheme.foreground
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: AppTheme.radiusLarge
            color: (section.opts.toVisible === true) ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: (section.opts.toVisible === true) ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: (section.opts.toVisible === true) ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
                color: (section.opts.toVisible === true) ? AppTheme.background : AppTheme.muted
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("toVisible", !(section.opts.toVisible === true))
            }
        }
    }

    Text {
        visible: section.preset === "customFlip"
        text: qsTr("Axis")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customFlip"
        spacing: 8

        SegmentedOption {
            label: qsTr("Horizontal")
            active: section.opts.axis !== "v"
            onClicked: section.setOption("axis", "h")
        }

        SegmentedOption {
            label: qsTr("Vertical")
            active: section.opts.axis === "v"
            onClicked: section.setOption("axis", "v")
        }
    }

    Text {
        visible: section.preset === "customResize"
        text: qsTr("From size")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customResize"
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "W"
            suffix: qsTr("px")
            minimum: 1
            maximum: 4000
            value: Number(section.opts.fromW) || 0
            onCommitted: v => section.setOption("fromW", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "H"
            suffix: qsTr("px")
            minimum: 1
            maximum: 4000
            value: Number(section.opts.fromH) || 0
            onCommitted: v => section.setOption("fromH", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    Text {
        visible: section.preset === "customResize"
        text: qsTr("To size")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customResize"
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "W"
            suffix: qsTr("px")
            minimum: 1
            maximum: 4000
            value: Number(section.opts.toW) || 0
            onCommitted: v => section.setOption("toW", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "H"
            suffix: qsTr("px")
            minimum: 1
            maximum: 4000
            value: Number(section.opts.toH) || 0
            onCommitted: v => section.setOption("toH", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    Text {
        visible: section.preset === "customCorner" || section.preset === "customStroke"
        text: qsTr("From")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    ClipEntryDropdown {
        visible: section.preset === "customStroke"
        doc: section.doc
        clip: section.clip
        clipId: section.clipId
        entryKind: "strokes"
    }

    NumberField {
        visible: section.preset === "customCorner" || section.preset === "customStroke"
        Layout.fillWidth: true
        suffix: qsTr("px")
        minimum: 0
        maximum: section.preset === "customCorner" ? 500 : 100
        value: Number(section.opts.from) || 0
        onCommitted: v => section.setOption("from", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        visible: section.preset === "customCorner" || section.preset === "customStroke"
        text: qsTr("To")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.preset === "customCorner" || section.preset === "customStroke"
        Layout.fillWidth: true
        suffix: qsTr("px")
        minimum: 0
        maximum: section.preset === "customCorner" ? 500 : 100
        value: Number(section.opts.to) || 0
        onCommitted: v => section.setOption("to", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    Text {
        visible: section.preset === "customStroke"
        text: qsTr("From opacity")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.preset === "customStroke"
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
        visible: section.preset === "customStroke"
        text: qsTr("To opacity")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    NumberField {
        visible: section.preset === "customStroke"
        Layout.fillWidth: true
        minimum: 0
        maximum: 1
        scrubStep: 0.05
        value: section.opts.toOpacity !== undefined ? Number(section.opts.toOpacity) : 1
        onCommitted: v => section.setOption("toOpacity", v)
        onScrubStarted: section.beginScrub()
        onScrubFinished: section.endScrub()
    }

    ClipDashPair {
        visible: section.preset === "customStroke"
        doc: section.doc
        clipId: section.clipId
        opts: section.opts
    }

    ClipPositionSwitch {
        visible: section.preset === "customStroke"
        label: qsTr("From position")
        position: section.opts.fromPosition
        doc: section.doc
        clipId: section.clipId
        optionRole: "fromPosition"
    }

    ClipPositionSwitch {
        visible: section.preset === "customStroke"
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

    function beginScrub() {
        if (section.doc)
            section.doc.beginTransaction();
    }

    function endScrub() {
        if (section.doc)
            section.doc.endTransaction();
    }
}
