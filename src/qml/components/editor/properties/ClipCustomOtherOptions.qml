import QtQuick
import QtQuick.Layouts
import Totm

// Custom Other editors: Hide/Show (stepped bools), Resize (absolute box),
// Corner Radius and Stroke width (absolute px). Resize centers on each
// leaf's own center; corner writes all four when independent is on.
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
            radius: 11
            color: (section.opts.fromVisible !== false) ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: (section.opts.fromVisible !== false) ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: (section.opts.fromVisible !== false) ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: 8
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
            radius: 11
            color: (section.opts.toVisible === true) ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: (section.opts.toVisible === true) ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: (section.opts.toVisible === true) ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: 8
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
