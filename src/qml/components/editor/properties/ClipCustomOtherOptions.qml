import QtQuick
import QtQuick.Layouts
import Totm

// Custom Other editors: Hide/Show (stepped bools), Flip axis (stepped
// mirror), Resize (absolute box), Corner Radius and Stroke width
// (absolute px). Stroke clips also carry entry opacity, dash pair and
// position: width/opacity/dash lerp, position steps at the midpoint.
// Resize centers on each leaf's own center; corner writes
// all four when independent is on. All style targets are entry 0.
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property string preset: section.clip ? section.clip.preset : ""
    readonly property var entryDefaults: DocCustomDefaults {}
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

    Text {
        visible: section.preset === "customStroke"
        text: qsTr("Stroke entry")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    PanelDropdown {
        visible: section.preset === "customStroke"
        Layout.fillWidth: true
        options: section.entryOptions()
        currentId: String(section.entryIndex())
        onPicked: id => section.retargetEntry(Number(id))
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

    Text {
        visible: section.preset === "customStroke"
        text: qsTr("From dash / gap (width units, 0 = solid)")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customStroke"
        spacing: 8
        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "D"
            minimum: 0
            maximum: 100
            value: Number(section.opts.fromDash) || 0
            onCommitted: v => section.setOption("fromDash", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "G"
            minimum: 0
            maximum: 100
            value: Number(section.opts.fromGap) || 0
            onCommitted: v => section.setOption("fromGap", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    Text {
        visible: section.preset === "customStroke"
        text: qsTr("To dash / gap (width units, 0 = solid)")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customStroke"
        spacing: 8
        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "D"
            minimum: 0
            maximum: 100
            value: Number(section.opts.toDash) || 0
            onCommitted: v => section.setOption("toDash", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "G"
            minimum: 0
            maximum: 100
            value: Number(section.opts.toGap) || 0
            onCommitted: v => section.setOption("toGap", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    Text {
        visible: section.preset === "customStroke"
        text: qsTr("From position")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customStroke"
        spacing: 8
        SegmentedOption {
            label: qsTr("Center")
            active: (section.opts.fromPosition || "center") === "center"
            onClicked: section.setOption("fromPosition", "center")
        }
        SegmentedOption {
            label: qsTr("Inside")
            active: section.opts.fromPosition === "inside"
            onClicked: section.setOption("fromPosition", "inside")
        }
        SegmentedOption {
            label: qsTr("Outside")
            active: section.opts.fromPosition === "outside"
            onClicked: section.setOption("fromPosition", "outside")
        }
    }

    Text {
        visible: section.preset === "customStroke"
        text: qsTr("To position")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        visible: section.preset === "customStroke"
        spacing: 8
        SegmentedOption {
            label: qsTr("Center")
            active: (section.opts.toPosition || "center") === "center"
            onClicked: section.setOption("toPosition", "center")
        }
        SegmentedOption {
            label: qsTr("Inside")
            active: section.opts.toPosition === "inside"
            onClicked: section.setOption("toPosition", "inside")
        }
        SegmentedOption {
            label: qsTr("Outside")
            active: section.opts.toPosition === "outside"
            onClicked: section.setOption("toPosition", "outside")
        }
    }

    function setOption(role, value) {
        if (!section.doc)
            return;
        var patch = {};
        patch[role] = value;
        section.doc.setClipOptions(section.clipId, patch);
    }

    function entryIndex() {
        if (section.opts.strokeIndex === undefined)
            return 0;
        var n = Math.round(Number(section.opts.strokeIndex));
        if (isNaN(n))
            return 0;
        return Math.min(32, Math.max(0, n));
    }

    function entryOptions() {
        var out = [];
        var list = (section.targetTop && section.targetTop.strokes) || [];
        for (var i = 0; i < list.length; i++) {
            var e = list[i] || {};
            out.push({
                id: String(i),
                name: qsTr("Stroke ") + (i + 1) + (e.enabled === false ? qsTr(" (off)") : "")
            });
        }
        if (out.length === 0)
            out.push({
                id: "0",
                name: qsTr("Stroke 1")
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
        var patch = section.entryDefaults.fromPatchForEntry(section.doc.anim.presets, section.doc, tops, "customStroke", i);
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
