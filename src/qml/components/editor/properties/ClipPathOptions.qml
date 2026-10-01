import QtQuick
import QtQuick.Layouts
import Totm

// Motion-path clip options: follow-rotation and closed-loop toggles
// plus redraw (re-enters canvas draw mode with the current trajectory
// loaded). Points live in the clip as relative offsets from the path
// start (first point 0,0), sampled by arc length so drawing location
// never moves the shape's start. Production controls (additive, old
// clips without them behave exactly as before): constant/eased speed,
// reverse, repeat/alternate traversals, orient offset/flip, and the
// follow point (which point of the shape rides the path).
ColumnLayout {
    id: section

    required property var doc
    required property int clipId

    property var redrawPolicy: null

    readonly property var clip: section.doc ? section.doc.animClip(section.clipId) : null
    readonly property var opts: section.clip ? section.clip.options || {} : ({})
    readonly property var pts: section.opts.pts || []
    readonly property bool orientOn: section.opts.orient === true
    readonly property string speed: section.opts.speed === "constant" ? "constant" : "eased"
    // Path-local traversal repeat (times/alternate), unrelated to the
    // removed clip loop modes: the clip still plays once and holds.
    readonly property string repeatMode: section.opts.repeatMode === "times" ? "times" : section.opts.repeatMode === "alternate" ? "alternate" : "once"
    readonly property string follow: section.followName(section.opts.follow)

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
            radius: AppTheme.radiusLarge
            color: section.orientOn ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: section.orientOn ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: section.orientOn ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
                color: section.orientOn ? AppTheme.background : AppTheme.muted
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("orient", !section.orientOn)
            }
        }
    }

    RowLayout {
        visible: section.orientOn
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Angle offset")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        NumberField {
            Layout.preferredWidth: 110
            suffix: "°"
            minimum: -180
            maximum: 180
            value: Number(section.opts.orientOffset) || 0
            onCommitted: v => section.setOption("orientOffset", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    RowLayout {
        visible: section.orientOn
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Flip 180°")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: AppTheme.radiusLarge
            color: section.opts.orientFlip === true ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: section.opts.orientFlip === true ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: section.opts.orientFlip === true ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
                color: section.opts.orientFlip === true ? AppTheme.background : AppTheme.muted
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("orientFlip", !(section.opts.orientFlip === true))
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
            radius: AppTheme.radiusLarge
            color: section.opts.closed === true ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: section.opts.closed === true ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: section.opts.closed === true ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
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

    Text {
        text: qsTr("Speed along path")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        SegmentedOption {
            label: qsTr("Eased")
            active: section.speed === "eased"
            onClicked: section.setOption("speed", "eased")
        }

        SegmentedOption {
            label: qsTr("Constant")
            active: section.speed === "constant"
            onClicked: section.setOption("speed", "constant")
        }
    }

    RowLayout {
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Reverse")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 22
            radius: AppTheme.radiusLarge
            color: section.opts.reverse === true ? AppTheme.foreground : AppTheme.surface
            border.width: 1
            border.color: section.opts.reverse === true ? AppTheme.foreground : AppTheme.fieldBorder

            Rectangle {
                x: section.opts.reverse === true ? parent.width - width - 3 : 3
                y: 3
                width: 16
                height: 16
                radius: AppTheme.radiusMedium
                color: section.opts.reverse === true ? AppTheme.background : AppTheme.muted
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.setOption("reverse", !(section.opts.reverse === true))
            }
        }
    }

    Text {
        text: qsTr("Repeat")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    RowLayout {
        spacing: 8

        SegmentedOption {
            label: qsTr("Once")
            active: section.repeatMode === "once"
            onClicked: section.setRepeat("once", 1)
        }

        SegmentedOption {
            label: qsTr("Repeat")
            active: section.repeatMode === "times"
            onClicked: section.setRepeat("times", Math.max(2, Math.round(Number(section.opts.repeatCount) || 2)))
        }

        SegmentedOption {
            label: qsTr("Alternate")
            active: section.repeatMode === "alternate"
            onClicked: section.setRepeat("alternate", Math.max(2, Math.round(Number(section.opts.repeatCount) || 2)))
        }
    }

    RowLayout {
        visible: section.repeatMode !== "once"
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Times")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        NumberField {
            Layout.preferredWidth: 110
            suffix: "×"
            minimum: 2
            maximum: 8
            value: Math.min(8, Math.max(2, Math.round(Number(section.opts.repeatCount) || 2)))
            onCommitted: v => section.setOption("repeatCount", Math.min(8, Math.max(2, Math.round(v))))
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    Text {
        text: qsTr("Follow point")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    GridLayout {
        columns: 3
        rowSpacing: 8
        columnSpacing: 8

        SegmentedOption {
            label: qsTr("TL")
            active: section.follow === "topLeft"
            onClicked: section.setOption("follow", "topLeft")
        }

        SegmentedOption {
            label: qsTr("Top")
            active: section.follow === "top"
            onClicked: section.setOption("follow", "top")
        }

        SegmentedOption {
            label: qsTr("TR")
            active: section.follow === "topRight"
            onClicked: section.setOption("follow", "topRight")
        }

        SegmentedOption {
            label: qsTr("Left")
            active: section.follow === "left"
            onClicked: section.setOption("follow", "left")
        }

        SegmentedOption {
            label: qsTr("Center")
            active: section.follow === "center"
            onClicked: section.setOption("follow", "center")
        }

        SegmentedOption {
            label: qsTr("Right")
            active: section.follow === "right"
            onClicked: section.setOption("follow", "right")
        }

        SegmentedOption {
            label: qsTr("BL")
            active: section.follow === "bottomLeft"
            onClicked: section.setOption("follow", "bottomLeft")
        }

        SegmentedOption {
            label: qsTr("Bottom")
            active: section.follow === "bottom"
            onClicked: section.setOption("follow", "bottom")
        }

        SegmentedOption {
            label: qsTr("BR")
            active: section.follow === "bottomRight"
            onClicked: section.setOption("follow", "bottomRight")
        }
    }

    RowLayout {
        spacing: 8

        SegmentedOption {
            label: qsTr("Custom pivot")
            active: section.follow === "custom"
            onClicked: section.setOption("follow", "custom")
        }
    }

    RowLayout {
        visible: section.follow === "custom"
        spacing: 8

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "X"
            suffix: qsTr("px")
            minimum: -4000
            maximum: 4000
            value: Number(section.opts.followX) || 0
            onCommitted: v => section.setOption("followX", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }

        NumberField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            prefix: "Y"
            suffix: qsTr("px")
            minimum: -4000
            maximum: 4000
            value: Number(section.opts.followY) || 0
            onCommitted: v => section.setOption("followY", v)
            onScrubStarted: section.beginScrub()
            onScrubFinished: section.endScrub()
        }
    }

    RowLayout {
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: AppTheme.radiusSmall
            color: simplifyMouse.containsMouse || simplifyMouse.pressed ? AppTheme.hover : AppTheme.surface
            border.width: 1
            border.color: AppTheme.fieldBorder
            opacity: section.pts.length >= 3 ? 1 : 0.4

            Text {
                anchors.centerIn: parent
                text: qsTr("Simplify")
                font.pixelSize: 12
                color: AppTheme.foreground
            }

            MouseArea {
                id: simplifyMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.simplifyPath()
            }
        }
    }

    // Edit action: enters canvas draw mode with the current trajectory
    // loaded for full point editing (move/bend/insert/remove); Enter
    // replaces it, Esc keeps it.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: AppTheme.radiusSmall
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

    function followName(v) {
        var ok = ["topLeft", "top", "topRight", "right", "bottomRight", "bottom", "bottomLeft", "left", "center", "custom"];
        return ok.indexOf(v) >= 0 ? v : "topLeft";
    }

    function setRepeat(mode, count) {
        if (!section.doc)
            return;
        section.doc.setClipOptions(section.clipId, {
            repeatMode: mode,
            repeatCount: mode === "once" ? 1 : Math.min(8, Math.max(2, Math.round(count)))
        });
    }

    function simplifyPath() {
        if (!section.doc || section.pts.length < 3)
            return;
        var kept = section.rdpSimplify(section.pts, 1.5);
        // Closed loops need 3+ points; 2-point closed is a degenerate
        // forth-back line, so keep the original instead.
        var minKept = section.opts.closed === true ? 3 : 2;
        if (kept.length >= minKept && kept.length < section.pts.length)
            section.doc.setClipOptions(section.clipId, {
                pts: kept
            });
    }

    // Ramer-Douglas-Peucker on anchors only; handles ride along with
    // their anchor so curves keep their shape. Anchor-only distance can
    // still distort strong curves; eps stays small (1.5px) and closed
    // loops keep 3+ points. Endpoints never drop.
    function rdpSimplify(list, eps) {
        if (list.length <= 2)
            return list.slice();
        var keep = [];
        for (var i = 0; i < list.length; i++)
            keep.push(false);
        keep[0] = true;
        keep[list.length - 1] = true;
        section.rdpWalk(list, 0, list.length - 1, eps, keep);
        var out = [];
        for (var j = 0; j < list.length; j++) {
            if (keep[j])
                out.push(list[j]);
        }
        return out;
    }

    function rdpWalk(list, a, b, eps, keep) {
        if (b <= a + 1)
            return;
        var ax = Number(list[a].x) || 0, ay = Number(list[a].y) || 0;
        var bx = Number(list[b].x) || 0, by = Number(list[b].y) || 0;
        var dx = bx - ax, dy = by - ay;
        var denom = Math.hypot(dx, dy);
        var best = -1, bestD = 0;
        for (var i = a + 1; i < b; i++) {
            var px = (Number(list[i].x) || 0) - ax, py = (Number(list[i].y) || 0) - ay;
            var d = denom < 1e-9 ? Math.hypot(px, py) : Math.abs(px * dy - py * dx) / denom;
            if (d > bestD) {
                bestD = d;
                best = i;
            }
        }
        if (best >= 0 && bestD > eps) {
            keep[best] = true;
            section.rdpWalk(list, a, best, eps, keep);
            section.rdpWalk(list, best, b, eps, keep);
        }
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
