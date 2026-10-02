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
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignVCenter
            radius: AppTheme.radiusSmall
            color: "#1a1a1a"
            border.width: 1
            border.color: AppTheme.fieldBorder
            clip: true

            AppIcon {
                anchors.centerIn: parent
                kind: "play"
                iconColor: AppTheme.muted
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: section.snapshot.commonOf("videoSource").mixed ? qsTr("Mixed") : (section.currentSource() === "" ? qsTr("Missing video") : section.currentSource())
                font.pixelSize: 11
                color: section.hasFile() ? AppTheme.muted : AppTheme.closeHover
                elide: Text.ElideMiddle
            }

            Text {
                Layout.fillWidth: true
                visible: !section.hasFile()
                text: qsTr("File moved? Replace to relink. Export paints a dark tile until then.")
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
                    label: qsTr("Detach audio")
                    visible: section.hasSound
                    enabled: section.hasFile()
                    onClicked: section.detachAudio()
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

    FilePicker {
        id: replacePicker
        suffixes: ["mp4", "webm", "mov", "m4v", "mkv"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.MoviesLocation)
        onAccepted: {
            var path = LibraryStore.normalizeVideoPath(selectedFile);
            if (!path)
                return;
            // Same single-probe rule as placement: unprobed files still
            // relink (unknown duration, no loop math) instead of failing.
            var pr = LibraryStore.videoProbe(path);
            // One undo entry for the whole relink (source + length).
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
