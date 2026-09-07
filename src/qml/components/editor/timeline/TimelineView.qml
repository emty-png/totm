import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Timeline: left sidebar (transport plus one label per animated top)
// beside a horizontally flickable tracks area (ruler, lanes, red
// playhead overlay). Hairlines divide the header and every lane on both
// sides so rows read across the divider. Delegates stay pure modelData
// with policies wired in onItemAdded, like LayersView.
// Tracks input lives on a sibling overlay below the content row (never
// inside the Flickable): same geometry as the viewport, zero collision
// with lanes, ruler or playhead, deterministic coordinates.
Item {
    id: timeline

    required property var doc

    // Zoomable pixels-per-second (ctrl+wheel around the cursor).
    property real pxPerSec: 120
    readonly property real minZoom: 30
    readonly property real maxZoom: 600
    property bool marqueeDragged: false
    readonly property real originX: 8
    readonly property real gutterWidth: 200
    // Transparent headroom for the panel's resize strip. Interactive
    // content starts below it; the divider and playhead bleed through
    // to the top edge.
    readonly property real topPad: 6
    readonly property real headerHeight: 44
    // Tracks start below the header hairline so lane rows sit exactly
    // beside their gutter labels.
    readonly property real tracksTop: timeline.topPad + timeline.headerHeight + 1
    readonly property real rulerHeight: 28
    readonly property real laneHeight: 30

    readonly property real playheadX: timeline.doc ? timeline.doc.anim.currentTime * timeline.pxPerSec : 0
    readonly property var lanes: timeline.computeLanes()

    // Tracks input overlay, below the content row: lane, diamond and
    // ruler presses land above; empty tracks and wheel fall through here.
    MouseArea {
        id: tracksMouse

        x: tracks.x
        y: tracks.y
        width: tracks.width
        height: tracks.height
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        onPressed: mouse => {
            // Grabbing empty tracks finishes any open field editor.
            timeline.forceActiveFocus();
            timeline.marqueeDragged = false;
            marquee.pressAt(mouse.x + tracks.contentX, mouse.y + tracks.contentY);
        }
        onPositionChanged: mouse => {
            if (pressed)
                marquee.moveTo(mouse.x + tracks.contentX, mouse.y + tracks.contentY);
        }
        onReleased: mouse => marquee.release(!!(mouse.modifiers & Qt.ShiftModifier))
        onClicked: {
            if (timeline.marqueeDragged || !timeline.doc)
                return;
            // Clicking empty tracks stops playback like the ruler and
            // clears the clip selection. Diamond clicks keep playing.
            if (timeline.doc.anim.playing)
                timeline.doc.anim.pause();
            timeline.doc.clearClipSelection();
        }
        onWheel: wheel => timeline.handleWheel(wheel)
    }

    DragSelection {
        id: marquee

        onStarted: timeline.marqueeDragged = true
        onFinished: (area, additive) => timeline.applyMarquee(area, additive)
    }

    RowLayout {
        id: contentRow

        anchors.fill: parent
        spacing: 0

        // Sidebar: transport block plus lane labels, hairlined per row.
        Column {
            Layout.preferredWidth: timeline.gutterWidth
            Layout.fillHeight: true

            Item {
                width: parent.width
                height: timeline.topPad
            }

            Item {
                width: parent.width
                height: timeline.headerHeight

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 12
                    }
                    spacing: 8

                    ToolbarButton {
                        Layout.alignment: Qt.AlignVCenter
                        iconKind: timeline.doc && timeline.doc.anim.playing ? "pause" : "play"
                        onClicked: {
                            if (!timeline.doc)
                                return;
                            if (timeline.doc.anim.playing)
                                timeline.doc.anim.pause();
                            else
                                timeline.doc.anim.play();
                        }
                    }

                    ToolbarButton {
                        Layout.alignment: Qt.AlignVCenter
                        iconKind: "stop"
                        onClicked: {
                            if (timeline.doc)
                                timeline.doc.anim.stop();
                        }
                    }

                    NumberField {
                        Layout.preferredWidth: 76
                        Layout.alignment: Qt.AlignVCenter
                        suffix: "s"
                        scrubStep: 0.1
                        minimum: 0.5
                        maximum: 60
                        value: timeline.doc ? timeline.doc.anim.duration : 4.0
                        onCommitted: v => {
                            if (timeline.doc)
                                timeline.doc.setAnimDuration(v);
                        }
                        onScrubStarted: {
                            if (timeline.doc)
                                timeline.doc.beginTransaction();
                        }
                        onScrubFinished: {
                            if (timeline.doc)
                                timeline.doc.endTransaction();
                        }
                    }
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: 1
                    color: AppTheme.border
                }
            }

            Repeater {
                model: timeline.lanes

                Item {
                    width: timeline.gutterWidth
                    height: timeline.laneHeight

                    Text {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 12
                            rightMargin: 8
                        }
                        text: modelData.name
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        color: AppTheme.foreground
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: 1
                        color: AppTheme.border
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: AppTheme.border
        }

        Flickable {
            id: tracks

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            contentWidth: Math.max(tracks.width, timeline.tracksWidth())
            contentHeight: timeline.tracksTop + timeline.lanes.length * timeline.laneHeight

            ScrollBar.horizontal: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitHeight: 6
                    radius: 3
                    color: AppTheme.border
                }
                background: Item {
                    implicitHeight: 6
                }
            }

            // Ruler block: ruler bottom-aligned with the sidebar transport,
            // sharing its hairline.
            Item {
                y: timeline.topPad
                width: tracks.contentWidth
                height: timeline.headerHeight

                TimelineRuler {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: timeline.rulerHeight
                    doc: timeline.doc
                    pxPerSec: timeline.pxPerSec
                    originX: timeline.originX
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: 1
                    color: AppTheme.border
                }
            }

            // Lanes.
            Column {
                id: laneColumn

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: timeline.tracksTop
                }
                height: timeline.lanes.length * timeline.laneHeight

                Repeater {
                    id: laneRows

                    model: timeline.lanes
                    onItemAdded: (index, item) => {
                        // Click-select policy for lane delegates
                        // (delegate-safe: assigned here where outer scope
                        // is visible, like LayersView).
                        item.diamondPolicy = (id, additive) => timeline.onDiamond(id, additive);
                    }

                    TimelineLane {
                        width: tracks.contentWidth
                        height: timeline.laneHeight
                        laneUid: modelData.uid
                        laneName: modelData.name
                        clips: modelData.clips
                        pxPerSec: timeline.pxPerSec
                        originX: timeline.originX
                        selectedIds: modelData.selected
                        doc: timeline.doc
                    }
                }
            }

            // Playhead overlay: pill readout on the ruler plus a line down
            // through every lane. Covers the viewport, not just the content,
            // so the line always reaches the panel bottom.
            Item {
                x: timeline.originX + timeline.playheadX
                width: 0
                height: Math.max(tracks.contentHeight, tracks.height)

                Rectangle {
                    x: -1
                    y: 0
                    width: 2
                    height: parent.height
                    color: AppTheme.snapGuide
                }

                Rectangle {
                    x: -23
                    y: 21
                    width: 46
                    height: 18
                    radius: 9
                    color: AppTheme.snapGuide

                    Text {
                        anchors.centerIn: parent
                        text: timeline.doc ? timeline.doc.anim.currentTime.toFixed(2) : "0.00"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: "#ffffff"
                    }
                }
            }

            // Empty state: no clips yet. Anchored to the viewport below the
            // ruler, not the content, so it stays put while scrolled.
            Text {
                x: tracks.contentX + (tracks.width - width) / 2
                y: timeline.tracksTop + (tracks.height - timeline.tracksTop - height) / 2
                visible: timeline.lanes.length === 0
                text: qsTr("Apply a preset from the gallery to begin...")
                font.pixelSize: 13
                color: AppTheme.muted
            }

            // Marquee rect, canvas selection language.
            Rectangle {
                visible: marquee.selecting
                x: marquee.selection.x
                y: marquee.selection.y
                width: marquee.selection.width
                height: marquee.selection.height
                color: "#140d99ff"
                border.width: 1
                border.color: "#0d99ff"
            }
        }
    } // contentRow

    // One row per clip (not per shape): stacked animations on one
    // target read as separate lanes, grouped by target in
    // first-appearance order, earliest first. Reads rev, clips and clip
    // selection so renames, edits and selection all refresh the rows;
    // delegates bind modelData only.
    function computeLanes() {
        var d = timeline.doc;
        if (!d)
            return [];
        d.rev;
        var clips = d.anim.clips;
        var sel = d.anim.selectedClipIds;
        var byTarget = {};
        var order = [];
        for (var i = 0; i < clips.length; i++) {
            var u = clips[i].targetUid;
            if (!byTarget[u]) {
                byTarget[u] = [];
                order.push(u);
            }
            byTarget[u].push(clips[i]);
        }
        var out = [];
        for (var t = 0; t < order.length; t++) {
            var mine = byTarget[order[t]].slice().sort((a, b) => a.t0 - b.t0);
            var n = d.findNode(order[t]);
            var base = n ? n.name : qsTr("Clip");
            for (var j = 0; j < mine.length; j++) {
                out.push({
                    uid: order[t],
                    name: base + " · " + d.anim.presets.presetName(mine[j].preset),
                    clips: [mine[j]],
                    selected: sel
                });
            }
        }
        return out;
    }

    function tracksWidth() {
        var d = timeline.doc;
        var dur = d ? Math.max(0.5, d.anim.duration) : 4.0;
        return timeline.originX + dur * timeline.pxPerSec + 120;
    }

    function onDiamond(id, additive) {
        var d = timeline.doc;
        if (!d)
            return;
        if (additive && d.anim.isClipSelected(id))
            d.anim.deselectClip(id);
        else
            d.selectClip(id, additive);
    }

    // Marquee select: any clip with a diamond inside the rect joins.
    // Click (no drag) is handled by the overlay; this only multi-picks.
    function applyMarquee(area, additive) {
        var d = timeline.doc;
        if (!d)
            return;
        if (!additive)
            d.clearClipSelection();
        var lanes = timeline.lanes;
        for (var i = 0; i < lanes.length; i++) {
            var cy = timeline.tracksTop + i * timeline.laneHeight + timeline.laneHeight / 2;
            if (cy + 6 < area.y || cy - 6 > area.y + area.height)
                continue;
            var clips = lanes[i].clips;
            for (var j = 0; j < clips.length; j++) {
                var ends = [clips[j].t0, clips[j].t0 + clips[j].duration];
                for (var k = 0; k < ends.length; k++) {
                    var dx = timeline.originX + ends[k] * timeline.pxPerSec;
                    if (dx + 6 >= area.x && dx - 6 <= area.x + area.width) {
                        d.selectClip(clips[j].id, true);
                        break;
                    }
                }
            }
        }
    }

    function handleWheel(event) {
        // Overlay coordinates already are viewport coordinates.
        if (event.modifiers & Qt.ControlModifier) {
            timeline.zoomAt(event.x, event.angleDelta.y);
            event.accepted = true;
            return;
        }
        var dx = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x / 2;
        var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
        if (dx !== 0 || dy !== 0) {
            tracks.contentX = timeline.clampX(tracks.contentX - dx - dy);
            event.accepted = true;
        }
    }

    // Zoom around a viewport x, keeping the time under it stable.
    function zoomAt(viewX, deltaY) {
        var old = timeline.pxPerSec;
        var next = Math.min(timeline.maxZoom, Math.max(timeline.minZoom, old * Math.pow(1.2, deltaY / 120)));
        if (next === old)
            return;
        var t = (tracks.contentX + viewX - timeline.originX) / old;
        timeline.pxPerSec = next;
        tracks.contentX = timeline.clampX(t * next + timeline.originX - viewX);
    }

    function clampX(x) {
        return Math.min(Math.max(0, timeline.tracksWidth() - tracks.width), Math.max(0, x));
    }
}
