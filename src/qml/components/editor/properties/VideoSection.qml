import QtCore
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Totm

// Video source section: linked file plus playback controls. Visible
// only when every selected leaf is a video; link-by-path keeps .totm
// small, missing files show a placeholder on canvas and a dark tile
// in export. Detach copies the file's sound onto an audio lane.
PanelSection {
    id: section

    required property var snapshot
    property var doc: section.snapshot ? section.snapshot.doc : null

    title: qsTr("Video")
    visible: section.snapshot.sel.length > 0 && section.snapshot.allOfType("video")
    enabled: !section.snapshot.allLocked

    function currentSource() {
        if (section.snapshot.sel.length === 0)
            return "";
        return section.snapshot.sel[0].videoSource ?? "";
    }

    function baseName(path) {
        if (!path)
            return "";
        var p = String(path).replace(/\\/g, "/");
        var i = p.lastIndexOf("/");
        return i >= 0 ? p.slice(i + 1) : p;
    }

    function hasFile() {
        return section.currentSource() !== "" && LibraryStore.hasVideo(section.currentSource());
    }

    // Container probe, cached per source: one fast ffmpeg -i parse feeds
    // the decode states below. Refresh is imperative (timer + visibility
    // + replace) and bindings read plain props only — writing cache
    // state from inside a visible: binding trips QML's loop detector
    // and re-spawns the probe per pass.
    property bool fileProbed: false
    property bool fileOk: false
    property string probedFor: ""
    // Sound presence across the selection, cached per path: sound
    // controls hide only when every probed file positively lacks a
    // track. Unknown/unprobed counts as sounding (fail-open), so
    // nothing flickers or over-hides mid-probe.
    property bool hasSound: true
    property var audioMap: ({})
    property string probedLeaves: ""
    property bool previewFailed: false
    // Probed length for the current source (Fit-comp needs it even
    // with no meta line displayed).
    property real probedDur: 0

    onVisibleChanged: {
        if (visible)
            section.refreshProbe();
    }

    function refreshProbe() {
        var leaves = section.snapshot ? section.snapshot.selLeaves : [];
        var keys = [];
        for (var i = 0; i < leaves.length; i++)
            keys.push(String(leaves[i].videoSource ?? ""));
        keys.sort();
        var leafKey = keys.join("\n");
        var src = section.currentSource();
        if (src === section.probedFor && leafKey === section.probedLeaves)
            return;
        section.probedFor = src;
        section.probedLeaves = leafKey;
        section.previewFailed = false;
        if (!src) {
            section.fileProbed = true;
            section.fileOk = false;
            section.hasSound = true;
            return;
        }
        var pr = LibraryStore.videoProbe(src);
        section.fileOk = pr && pr.ok === true;
        section.fileProbed = true;
        section.probedDur = section.fileOk ? Math.max(0, Number(pr.duration) || 0) : 0;
        var am = section.audioMap;
        var sound = false;
        for (var j = 0; j < keys.length; j++) {
            var k = keys[j];
            if (k === "")
                continue;
            if (am[k] === undefined) {
                var lp = k === src ? pr : LibraryStore.videoProbe(k);
                am[k] = lp && lp.ok === true ? (lp.hasAudio === true) : -1;
            }
            if (am[k] !== false)
                sound = true;
        }
        section.audioMap = am;
        section.hasSound = sound;
    }

    Timer {
        interval: 500
        repeat: true
        running: section.visible
        onTriggered: section.refreshProbe()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            id: thumb

            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: "#1a1a1a"
            border.width: 1
            border.color: thumbDrop.containsDrag ? AppTheme.foreground : AppTheme.fieldBorder
            clip: true

            Behavior on border.color {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }

            AppIcon {
                anchors.centerIn: parent
                kind: "film"
                iconColor: AppTheme.muted
            }

            Text {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: 2
                }
                visible: thumbDrop.containsDrag
                text: qsTr("Drop")
                font.pixelSize: 9
                color: AppTheme.foreground
            }

            DropArea {
                id: thumbDrop
                anchors.fill: parent
                onDropped: drop => section.relinkDropped(drop)
            }

            SequentialAnimation {
                id: shake
                NumberAnimation {
                    target: thumb
                    property: "x"
                    to: -4
                    duration: 45
                }
                NumberAnimation {
                    target: thumb
                    property: "x"
                    to: 4
                    duration: 60
                }
                NumberAnimation {
                    target: thumb
                    property: "x"
                    to: -2
                    duration: 60
                }
                NumberAnimation {
                    target: thumb
                    property: "x"
                    to: 0
                    duration: 60
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: section.snapshot.commonOf("videoSource").mixed ? qsTr("Mixed") : (section.currentSource() === "" ? qsTr("Missing video") : section.baseName(section.currentSource()))
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: section.hasFile() ? AppTheme.foreground : AppTheme.closeHover
                elide: Text.ElideMiddle
            }

            Text {
                Layout.fillWidth: true
                visible: !section.snapshot.commonOf("videoSource").mixed && section.currentSource() !== ""
                text: section.currentSource()
                font.pixelSize: 10
                color: AppTheme.muted
                elide: Text.ElideMiddle
            }

            Text {
                Layout.fillWidth: true
                visible: section.hasFile() && !section.fileProbed
                text: qsTr("Probing…")
                font.pixelSize: 11
                color: AppTheme.muted

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: section.hasFile() && !section.fileProbed
                    onRunningChanged: {
                        if (!running)
                            opacity = 1;
                    }
                    NumberAnimation {
                        to: 0.35
                        duration: 500
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        to: 1
                        duration: 500
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !section.hasFile()
                text: qsTr("File moved? Replace or drop a video onto the thumbnail to relink. Export paints a dark tile until then.")
                font.pixelSize: 11
                color: AppTheme.muted
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: section.hasFile() && section.fileProbed && !section.fileOk
                text: qsTr("Couldn't decode this file — canvas and export show a dark tile.")
                font.pixelSize: 11
                color: AppTheme.closeHover
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: section.hasFile() && section.fileOk && section.previewFailed
                text: qsTr("This file won't preview on this OS — export still works.")
                font.pixelSize: 11
                color: AppTheme.muted
                wrapMode: Text.WordWrap
            }

            RowLayout {
                spacing: 8
                SegmentedOption {
                    label: qsTr("Replace")
                    onClicked: replacePicker.open()
                }
                SegmentedOption {
                    label: qsTr("Reveal")
                    enabled: section.currentSource() !== ""
                    onClicked: LibraryStore.revealVideo(section.currentSource())
                }
                SegmentedOption {
                    label: qsTr("Detach audio")
                    visible: section.hasSound
                    enabled: section.hasFile()
                    onClicked: section.detachAudio()
                }
            }

            RowLayout {
                spacing: 8
                visible: section.hasFile() && section.fileOk
                SegmentedOption {
                    label: qsTr("Fit comp to video")
                    onClicked: section.fitCompToVideo()
                }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 8
        rowSpacing: 8

        Text {
            visible: section.hasSound
            text: qsTr("Volume")
            font.pixelSize: 12
            color: AppTheme.foreground
        }
        NumberField {
            visible: section.hasSound
            Layout.fillWidth: true
            value: Math.round((section.snapshot.commonOf("videoVolume").mixed ? 1 : Number(section.snapshot.commonOf("videoVolume").value ?? 1)) * 100)
            mixed: section.snapshot.commonOf("videoVolume").mixed
            minimum: 0
            maximum: 100
            suffix: "%"
            onCommitted: v => section.snapshot.setAll("videoVolume", Math.min(1, Math.max(0, Number(v) / 100)))
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }

        Text {
            text: qsTr("Speed")
            font.pixelSize: 12
            color: AppTheme.foreground
        }
        NumberField {
            Layout.fillWidth: true
            value: section.snapshot.commonOf("playbackRate").mixed ? 1 : Number(section.snapshot.commonOf("playbackRate").value ?? 1)
            mixed: section.snapshot.commonOf("playbackRate").mixed
            minimum: 0.25
            maximum: 4
            scrubStep: 0.05
            suffix: "x"
            onCommitted: v => section.snapshot.setAll("playbackRate", Math.min(4, Math.max(0.25, Number(v) || 1)))
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }

        Text {
            text: qsTr("Offset")
            font.pixelSize: 12
            color: AppTheme.foreground
        }
        NumberField {
            Layout.fillWidth: true
            value: section.snapshot.commonOf("videoOffset").mixed ? 0 : Number(section.snapshot.commonOf("videoOffset").value ?? 0)
            mixed: section.snapshot.commonOf("videoOffset").mixed
            minimum: 0
            maximum: 3600
            scrubStep: 0.05
            suffix: "s"
            onCommitted: v => section.snapshot.setAll("videoOffset", Math.max(0, Number(v) || 0))
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }

        Text {
            text: qsTr("Start")
            font.pixelSize: 12
            color: AppTheme.foreground
        }
        NumberField {
            Layout.fillWidth: true
            value: section.snapshot.commonOf("videoStart").mixed ? 0 : Number(section.snapshot.commonOf("videoStart").value ?? 0)
            mixed: section.snapshot.commonOf("videoStart").mixed
            minimum: 0
            maximum: 3600
            scrubStep: 0.05
            suffix: "s"
            onCommitted: v => section.snapshot.setAll("videoStart", Math.max(0, Number(v) || 0))
            onScrubStarted: section.snapshot.beginScrub()
            onScrubFinished: section.snapshot.endScrub()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: section.hasFile() && section.fileOk

        SegmentedOption {
            label: qsTr("Move to playhead")
            onClicked: section.moveToPlayhead()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        SegmentedOption {
            label: qsTr("Fit")
            active: !section.snapshot.commonOf("videoFit").mixed && (section.snapshot.commonOf("videoFit").value ?? "fit") === "fit"
            onClicked: section.snapshot.setAll("videoFit", "fit")
        }
        SegmentedOption {
            label: qsTr("Cover")
            active: !section.snapshot.commonOf("videoFit").mixed && section.snapshot.commonOf("videoFit").value === "cover"
            onClicked: section.snapshot.setAll("videoFit", "cover")
        }
        SegmentedOption {
            label: qsTr("Stretch")
            active: !section.snapshot.commonOf("videoFit").mixed && section.snapshot.commonOf("videoFit").value === "fill"
            onClicked: section.snapshot.setAll("videoFit", "fill")
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        SegmentedOption {
            visible: section.hasSound
            label: section.snapshot.commonOf("videoMuted").mixed ? qsTr("Muted?") : (section.snapshot.commonOf("videoMuted").value === true ? qsTr("Muted") : qsTr("Mute"))
            active: !section.snapshot.commonOf("videoMuted").mixed && section.snapshot.commonOf("videoMuted").value === true
            onClicked: section.toggleMuted()
        }
        SegmentedOption {
            label: section.snapshot.commonOf("videoLoop").mixed ? qsTr("Loop?") : (section.snapshot.commonOf("videoLoop").value !== false ? qsTr("Looping") : qsTr("Loop"))
            active: section.snapshot.commonOf("videoLoop").mixed ? false : (section.snapshot.commonOf("videoLoop").value !== false)
            onClicked: section.toggleLoop()
        }
    }

    function toggleMuted() {
        var cur = section.snapshot.commonOf("videoMuted");
        var next = cur.mixed ? true : !(cur.value === true);
        section.snapshot.setAll("videoMuted", next);
    }

    function toggleLoop() {
        var cur = section.snapshot.commonOf("videoLoop");
        var next = cur.mixed ? false : !(cur.value !== false);
        section.snapshot.setAll("videoLoop", next);
    }

    // Jump the selection's timeline start to the playhead (one undo
    // entry): the precise counterpart to dragging the timeline bar.
    function moveToPlayhead() {
        if (!section.doc || !section.doc.anim)
            return;
        var t = Math.max(0, Number(section.doc.anim.currentTime) || 0);
        section.snapshot.setAll("videoStart", t);
    }

    function fitCompToVideo() {
        if (!section.doc || !section.doc.anim)
            return;
        var off = section.snapshot.sel.length > 0 ? Number(section.snapshot.sel[0].videoOffset || 0) : 0;
        var rate = section.snapshot.sel.length > 0 ? Number(section.snapshot.sel[0].playbackRate || 1) : 1;
        if (!(rate > 0))
            rate = 1;
        var dur = section.probedDur > 0 ? section.probedDur : (section.snapshot.sel.length > 0 ? Number(section.snapshot.sel[0].videoDuration || 0) : 0);
        if (!(dur > 0))
            return;
        var loop = section.snapshot.sel.length > 0 ? (section.snapshot.sel[0].videoLoop !== false) : true;
        var visible = loop ? dur : Math.max(0.5, (dur - off) / rate);
        visible = Math.min(60, Math.max(0.5, visible));
        // The span starts at the timeline start, so the comp must cover
        // both (start 0 keeps the legacy exact length).
        var start = section.snapshot.sel.length > 0 ? Math.max(0, Number(section.snapshot.sel[0].videoStart || 0)) : 0;
        visible = Math.min(60, Math.max(0.5, start + visible));
        section.doc.beginTransaction();
        section.doc.anim.setDuration(visible);
        section.doc.endTransaction();
    }

    // Detach: one audio clip per selected video, starting at the
    // playhead, trimmed to the composition end. The clip points at the
    // same linked file so ffmpeg extracts its track; volume/mute copy
    // over for continuity. Video stays visual-only otherwise.
    function detachAudio() {
        if (!section.doc || !section.doc.anim)
            return;
        var t0 = Number(section.doc.anim.currentTime) || 0;
        // One undo entry for clip + carried volume/mute.
        section.doc.beginTransaction();
        for (var i = 0; i < section.snapshot.selLeaves.length; i++) {
            var s = section.snapshot.selLeaves[i];
            var src = String(s.videoSource ?? "");
            if (src === "" || !LibraryStore.hasVideo(src))
                continue;
            var dur = Math.max(0, Number(s.videoDuration) || 0);
            if (!(dur > 0))
                dur = Math.max(0.5, Number(section.doc.anim.duration) - t0);
            var id = section.doc.addAudioClip(src, t0, dur);
            if (id >= 0) {
                section.doc.selectAudioClip(id, false);
                section.doc.setAudioProp("volume", Math.min(1, Math.max(0, Number(s.videoVolume) ?? 1)));
                if (s.videoMuted === true)
                    section.doc.setAudioProp("muted", true);
            }
        }
        section.doc.endTransaction();
    }

    // Shake the thumbnail when a probe completes undecodable: a
    // motion cue that the dark tile is not just loading slowly.
    onFileOkChanged: {
        if (section.visible && section.fileProbed && !section.fileOk && section.hasFile())
            shake.restart();
    }

    // Shared relink: probe once, then one undo entry for source +
    // length + offset reset. Unprobed files still relink (unknown
    // duration, no loop math) instead of failing the gesture.
    function relinkToPath(path) {
        if (!path)
            return;
        var pr = LibraryStore.videoProbe(path);
        if (section.doc)
            section.doc.beginTransaction();
        section.snapshot.setAll("videoSource", path);
        section.snapshot.setAll("videoDuration", pr && pr.ok === true ? Math.max(0, Number(pr.duration) || 0) : 0);
        section.snapshot.setAll("videoOffset", 0);
        if (section.doc)
            section.doc.endTransaction();
        // Clear the caches so the timer re-probes this file once
        // (one extra spawn on an explicit user action, then cached).
        section.probedFor = "";
        section.probedLeaves = "";
        section.refreshProbe();
    }

    // Thumbnail drop-to-relink: video files only, first URL wins.
    function relinkDropped(drop) {
        var urls = (drop && drop.urls) || [];
        if (urls.length === 0)
            return;
        var flat = String(urls[0]).split("?")[0];
        if (!/\.(mp4|webm|mov|m4v|mkv)$/i.test(flat))
            return;
        var path = LibraryStore.normalizeVideoPath(urls[0]);
        if (!path)
            return;
        section.relinkToPath(path);
    }

    FilePicker {
        id: replacePicker
        suffixes: ["mp4", "webm", "mov", "m4v", "mkv"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.MoviesLocation)
        onAccepted: {
            var path = LibraryStore.normalizeVideoPath(selectedFile);
            section.relinkToPath(path);
        }
    }

    // OS-backend playability probe: no outputs, never audible. Flags
    // files the local Qt Multimedia backend can't demux (e.g. WebM on
    // OS players) so the panel says so while ffmpeg export proceeds.
    MediaPlayer {
        id: previewProbe
        source: section.hasFile() ? LibraryStore.videoUrl(section.currentSource()) : ""
        autoPlay: false
        onSourceChanged: section.previewFailed = false
        onErrorOccurred: section.previewFailed = true
        onHasVideoChanged: {
            if (hasVideo)
                section.previewFailed = false;
        }
    }
}
