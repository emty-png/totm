import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Totm

// Timeline: gutter (transport + labels) beside flickable tracks (ruler,
// lanes, playhead). Delegates stay modelData-pure with policies wired in
// onItemAdded; tracks input lives on a sibling overlay below at viewport
// geometry, so nothing collides with lanes, ruler or playhead.
Item {
    id: timeline

    required property var doc

    property real pxPerSec: 120
    readonly property real minZoom: 30
    readonly property real maxZoom: 600
    // Joint-drag state shared across lanes (selections span rows).
    property var jointOrig: ({})
    property real jointDx: 0
    property bool clipDragging: false
    property bool marqueeDragged: false
    readonly property real originX: 8
    readonly property real gutterWidth: 200
    // Headroom for the panel resize strip; divider and playhead bleed
    // through to the top edge.
    readonly property real topPad: 6
    readonly property real headerHeight: 44
    // Tracks start below the header hairline so rows sit beside labels.
    readonly property real tracksTop: timeline.topPad + timeline.headerHeight + 1
    readonly property real rulerHeight: 28
    readonly property real laneHeight: 30

    readonly property real playheadX: timeline.doc ? timeline.doc.anim.currentTime * timeline.pxPerSec : 0
    readonly property var lanes: timeline.computeLanes()
    readonly property var audioRows: timeline.computeAudioRows()
    readonly property real audioHeadHeight: 28
    // Audio chrome exists only once a clip does; the import button
    // floats over the ruler so adding the first clip is always at hand.
    readonly property bool hasAudio: timeline.audioRows.length > 0
    readonly property real audioTop: timeline.hasAudio ? timeline.audioHeadHeight : 0

    // Tracks input overlay below the content row: lane/diamond/ruler
    // presses land above; empty tracks and wheel fall through here.
    MouseArea {
        id: tracksMouse

        x: tracks.x
        y: tracks.y
        width: tracks.width
        height: tracks.height
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        onPressed: mouse => {
            // Grabbing tracks closes open field editors.
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
            // Empty-tracks click stops playback and clears selection.
            if (timeline.doc.anim.playing)
                timeline.doc.anim.pause();
            timeline.doc.clearClipSelection();
            timeline.doc.clearAudioSelection();
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

        Column {
            Layout.preferredWidth: timeline.gutterWidth
            Layout.fillHeight: true

            Item {
                width: parent.width
                height: timeline.topPad
            }

            TimelineTransport {
                width: parent.width
                height: timeline.headerHeight
                doc: timeline.doc
                headerHeight: timeline.headerHeight
            }

            // Lane labels ride with the tracks (transport stays put).
            Flickable {
                id: gutterScroll

                // Plain Column ignores Layout props, so size explicitly
                // (else the viewport is 0x0 and labels stay invisible).
                width: parent.width
                height: parent.height - timeline.topPad - timeline.headerHeight
                interactive: false
                clip: true
                contentWidth: timeline.gutterWidth
                contentHeight: timeline.lanes.length * timeline.laneHeight + timeline.audioTop + timeline.audioRows.length * timeline.laneHeight
                contentY: tracks.contentY

                Column {
                    width: timeline.gutterWidth

                    Repeater {
                        model: timeline.lanes

                        Item {
                            width: timeline.gutterWidth
                            height: timeline.laneHeight

                            RowLayout {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 12
                                    rightMargin: 8
                                }
                                spacing: 4

                                Text {
                                    Layout.maximumWidth: parent.width
                                    Layout.preferredWidth: Math.min(implicitWidth, parent.width)
                                    text: modelData.objectName
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    color: AppTheme.foreground
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.presetName
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    color: AppTheme.muted
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
                    }

                    // Audio header; import floats top-right over the ruler.
                    Item {
                        width: parent.width
                        height: timeline.audioHeadHeight
                        visible: timeline.hasAudio

                        Text {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                            }
                            text: qsTr("Audio")
                            font.pixelSize: 11
                            color: AppTheme.muted
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
                        model: timeline.audioRows

                        Item {
                            width: timeline.gutterWidth
                            height: timeline.laneHeight

                            AppIcon {
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 12
                                }
                                width: 14
                                height: 14
                                kind: "music"
                                iconColor: AppTheme.muted
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 32
                                    rightMargin: 8
                                }
                                text: qsTr("Sound %1").arg(modelData.clip.id)
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
            // Never interactive: it would claim press-drags and wheels
            // before the overlay sees them. Scrolling stays programmatic.
            interactive: false
            flickableDirection: Flickable.HorizontalAndVerticalFlick
            contentWidth: Math.max(tracks.width, timeline.tracksWidth())
            contentHeight: timeline.tracksTop + timeline.lanes.length * timeline.laneHeight + timeline.audioTop + timeline.audioRows.length * timeline.laneHeight

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

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: AppTheme.border
                }
                background: Item {
                    implicitWidth: 6
                }
            }

            // Ruler pinned to the viewport (lanes scroll under it), opaque
            // and above the lanes, covering the top pad.
            Item {
                z: 2
                y: tracks.contentY
                width: tracks.contentWidth
                height: timeline.topPad + timeline.headerHeight

                Rectangle {
                    anchors.fill: parent
                    color: AppTheme.background
                }

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

            // Lanes use explicit content geometry (anchors would pin them
            // to the viewport while the ruler scrolls away).
            Column {
                id: laneColumn

                x: 0
                y: timeline.tracksTop
                width: tracks.contentWidth
                height: timeline.lanes.length * timeline.laneHeight

                Repeater {
                    id: laneRows

                    model: timeline.lanes
                    onItemAdded: (index, item) => {
                        // Policies assigned where outer scope is visible.
                        item.diamondPolicy = (id, additive) => timeline.onDiamond(id, additive);
                        item.jointPolicy = (op, payload) => timeline.setJoint(op, payload);
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
                        jointOrig: timeline.jointOrig
                        jointDx: timeline.jointDx
                        jointActive: timeline.clipDragging
                        doc: timeline.doc
                    }
                }
            }

            // Audio header spacer pairing with the gutter header (content
            // geometry, so pans move the hairline with the ruler).
            Item {
                x: 0
                width: tracks.contentWidth
                y: timeline.tracksTop + timeline.lanes.length * timeline.laneHeight
                height: timeline.audioHeadHeight
                visible: timeline.hasAudio

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

            // Audio lanes pan with the ruler (never viewport-pinned).
            Column {
                id: audioColumn

                x: 0
                width: tracks.contentWidth
                y: timeline.tracksTop + timeline.lanes.length * timeline.laneHeight + timeline.audioTop
                height: timeline.audioRows.length * timeline.laneHeight

                Repeater {
                    id: audioRows

                    model: timeline.audioRows
                    onItemAdded: (index, item) => {
                        item.clipPolicy = (id, additive) => timeline.onAudioClip(id, additive);
                    }

                    TimelineAudioLane {
                        width: tracks.contentWidth
                        height: timeline.laneHeight
                        clip: modelData.clip
                        pxPerSec: timeline.pxPerSec
                        originX: timeline.originX
                        selected: modelData.selected
                        doc: timeline.doc
                    }
                }
            }

            // Playhead pinned to the viewport above the ruler: pill plus a
            // line through every lane.
            Item {
                z: 3
                x: timeline.originX + timeline.playheadX
                y: tracks.contentY
                width: 0
                height: tracks.height

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

            // Empty state, viewport-anchored below the ruler.
            Text {
                x: tracks.contentX + (tracks.width - width) / 2
                y: tracks.contentY + timeline.tracksTop + (tracks.height - timeline.tracksTop - height) / 2
                visible: timeline.lanes.length === 0 && timeline.audioRows.length === 0
                text: qsTr("Apply a preset or custom animation to begin...")
                font.pixelSize: 13
                color: AppTheme.muted
            }

            // Marquee rect in canvas selection language.
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

    // Add-sound button floating over the ruler (layout-independent box:
    // ToolbarButton only sizes itself for layouts).
    ToolbarButton {
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 8
            rightMargin: 12
        }
        width: 36
        height: 32
        iconKind: "music"
        onClicked: audioPicker.open()
    }

    // One lane per animated target in first-appearance order; reads rev
    // so renames, edits and selection refresh the rows.
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
            var n = d.findNode(Number(order[t]));
            var base = n && n.name ? n.name : qsTr("Clip");
            var sub = mine.length > 1 ? "· " + qsTr("%1 clips").arg(mine.length) : "· " + d.anim.presets.presetName(mine[0].preset);
            out.push({
                uid: order[t],
                name: base + " " + sub,
                objectName: base,
                presetName: sub,
                clips: mine,
                selected: sel
            });
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

    // Joint-drag publisher for the lanes (one transaction per formation).
    function setJoint(op, payload) {
        if (op === "begin") {
            timeline.jointOrig = payload || {};
        } else if (op === "move") {
            timeline.jointDx = Number(payload) || 0;
            timeline.clipDragging = true;
        } else if (op === "end") {
            timeline.jointOrig = {};
            timeline.jointDx = 0;
            timeline.clipDragging = false;
        }
    }

    function onAudioClip(id, additive) {
        var d = timeline.doc;
        if (!d)
            return;
        d.selectAudioClip(id, additive);
    }

    // Audio rows earliest-first; reads rev so edits rebuild.
    function computeAudioRows() {
        var d = timeline.doc;
        if (!d)
            return [];
        d.rev;
        var sel = d.audio.selectedAudioIds;
        var clips = d.audio.clips.slice().sort((a, b) => a.t0 - b.t0);
        var out = [];
        for (var i = 0; i < clips.length; i++) {
            out.push({
                clip: clips[i],
                selected: sel.indexOf(clips[i].id) >= 0
            });
        }
        return out;
    }

    // Marquee multi-pick: diamonds inside join, as does overlapped audio.
    // (Plain clicks are handled by the overlay.)
    function applyMarquee(area, additive) {
        var d = timeline.doc;
        if (!d)
            return;
        if (!additive) {
            d.clearClipSelection();
            d.clearAudioSelection();
        }
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
        var rows = timeline.audioRows;
        for (var m = 0; m < rows.length; m++) {
            var ay = timeline.tracksTop + lanes.length * timeline.laneHeight + timeline.audioTop + m * timeline.laneHeight + timeline.laneHeight / 2;
            if (ay < area.y || ay > area.y + area.height)
                continue;
            var clip = rows[m].clip;
            var x0 = timeline.originX + clip.t0 * timeline.pxPerSec;
            var x1 = timeline.originX + (clip.t0 + clip.duration) * timeline.pxPerSec;
            if (x0 <= area.x + area.width && x1 >= area.x)
                d.addAudioSelection(clip.id);
        }
    }

    function handleWheel(event) {
        // Overlay coords already are viewport coords.
        if (event.modifiers & Qt.ControlModifier) {
            timeline.zoomAt(event.x, event.angleDelta.y);
            event.accepted = true;
            return;
        }
        // Shift scrolls vertically, plain wheels pan horizontally
        // (Flickables stay non-interactive, so scrolling never steals
        // lane presses).
        if (event.modifiers & Qt.ShiftModifier) {
            var vy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y;
            if (vy !== 0)
                tracks.contentY = timeline.clampY(tracks.contentY - vy);
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
        timeline.zoomSet(next, viewX);
    }

    // Zoom keeping the time under viewX stable (viewport center default).
    function zoomSet(next, viewX) {
        var old = timeline.pxPerSec;
        next = Math.min(timeline.maxZoom, Math.max(timeline.minZoom, next));
        if (next === old)
            return;
        var vx = viewX === undefined ? tracks.width / 2 : viewX;
        var t = (tracks.contentX + vx - timeline.originX) / old;
        timeline.pxPerSec = next;
        tracks.contentX = timeline.clampX(t * next + timeline.originX - vx);
    }

    function zoomStep(dy) {
        timeline.zoomAt(tracks.width / 2, dy);
    }

    function zoomToFit() {
        var d = timeline.doc;
        var dur = d ? Math.max(0.5, d.anim.duration) : 4.0;
        timeline.pxPerSec = Math.min(timeline.maxZoom, Math.max(timeline.minZoom, (tracks.width - timeline.originX - 64) / dur));
        tracks.contentX = 0;
    }

    function clampX(x) {
        return Math.min(Math.max(0, timeline.tracksWidth() - tracks.width), Math.max(0, x));
    }

    function clampY(y) {
        return Math.min(Math.max(0, tracks.contentHeight - tracks.height), Math.max(0, y));
    }

    // Audio import: the probe reads duration first; only probed files
    // are copied in at the playhead (failures store nothing).
    FilePicker {
        id: audioPicker

        suffixes: ["mp3", "wav", "ogg", "flac"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.MusicLocation)
        onAccepted: timeline.probeAudio(selectedFile)
    }

    // Duration probe with no audio output. It keeps its file loaded:
    // clearing mid-demux tears down the pipeline under in-flight events,
    // so imports overwrite and failures just disarm.
    MediaPlayer {
        id: audioProbe

        property url probeSource
        property bool armed: false

        onDurationChanged: {
            if (audioProbe.armed && duration > 0)
                timeline.commitAudioProbe();
        }
        onErrorOccurred: {
            audioProbe.armed = false;
        }
    }

    Timer {
        id: probeTimeout

        interval: 5000
        onTriggered: audioProbe.armed = false
    }

    function probeAudio(file) {
        if (!timeline.doc)
            return;
        audioProbe.probeSource = file;
        audioProbe.armed = true;
        audioProbe.source = file;
        probeTimeout.restart();
    }

    function commitAudioProbe() {
        audioProbe.armed = false;
        probeTimeout.stop();
        var file = audioProbe.probeSource;
        var secs = audioProbe.duration / 1000;
        if (!timeline.doc || secs <= 0)
            return;
        var name = LibraryStore.importAudio(file);
        if (!name)
            return;
        timeline.doc.addAudioClip(name, timeline.doc.anim.currentTime, secs);
    }
}
