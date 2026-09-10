import QtQuick
import QtMultimedia
import Totm

// Timeline audio preview: a growth-only pool of players conducted by a
// 100ms poll of the transport clock. Starts, stops and scrub
// repositions all derive from anim.currentTime, so preview follows
// seeks and trim cuts without chasing per-frame ticks. A few ms of
// start drift between overlapping players is accepted in v1 (music
// beds, not samples).
// Backend lifecycle rule (learned from a segfault): media pipelines
// are assigned and reassigned, never torn down mid-session. Players
// are created once, parked by pausing, and keep their last source, so
// no demux teardown races with in-flight backend events. An
// Instantiator/Repeater must not own players: rows rebuilds would
// destroy streaming pipelines.
Item {
    id: preview

    required property var doc

    visible: false

    // Rebuilt on structural doc changes only (rev never moves on ticks,
    // so reconciliation never interrupts playback by itself).
    readonly property var rows: preview.computeRows()

    // Player pool (growth-only) plus parallel clip assignment. Plain
    // arrays mutated in place: nothing binds them, only functions read.
    property var pool: []
    property var assign: []

    Component {
        id: playerFactory

        MediaPlayer {
            audioOutput: AudioOutput {}
        }
    }

    function computeRows() {
        var d = preview.doc;
        if (!d)
            return [];
        d.rev;
        var out = [];
        var clips = d.audio ? d.audio.clips : [];
        for (var i = 0; i < clips.length; i++) {
            if (LibraryStore.hasAudio(clips[i].source))
                out.push(clips[i]);
        }
        return out;
    }

    // Grow the pool to the rows and assign clips to players. Reassigned
    // players pause first; retired ones park with their source intact
    // (clearing it would tear down a live pipeline).
    function reconcile() {
        var rows = preview.rows;
        while (preview.pool.length < rows.length) {
            var made = playerFactory.createObject(preview);
            preview.pool.push(made);
            preview.assign.push(-1);
        }
        for (var i = 0; i < preview.pool.length; i++) {
            var p = preview.pool[i];
            if (!p)
                continue;
            if (i < rows.length) {
                if (preview.assign[i] !== rows[i].id) {
                    if (p.playbackState === MediaPlayer.PlayingState)
                        p.pause();
                    preview.assign[i] = rows[i].id;
                    p.source = LibraryStore.audioUrl(rows[i].source);
                }
            } else if (p.playbackState === MediaPlayer.PlayingState) {
                p.pause();
            }
        }
    }

    onRowsChanged: preview.reconcile()

    // Audible window of one clip in composition time, or null when the
    // trim rule leaves nothing (mirrors the exporter intersection).
    function audible(clip, dur) {
        var s = Math.max(clip.t0, 0);
        var e = Math.min(clip.t0 + clip.duration, dur);
        if (e - s <= 0.02)
            return null;
        return {
            start: s,
            len: e - s
        };
    }

    function findClip(id) {
        var d = preview.doc;
        if (!d)
            return null;
        return d.audioClip(id);
    }

    function ready(p) {
        return p && p.mediaStatus >= MediaPlayer.LoadedMedia && p.mediaStatus !== MediaPlayer.EndOfMedia && p.mediaStatus !== MediaPlayer.InvalidMedia;
    }

    // Audible gain for one clip at a poll instant: mute cuts, volume
    // scales, fades ramp over the audible window (mirrors the exporter
    // envelope so preview matches the render).
    function gainAt(c, win, now) {
        if (!c || c.muted === true)
            return 0;
        var v = c.volume === undefined ? 1 : Math.min(1, Math.max(0, Number(c.volume) || 0));
        var pos = now - win.start;
        if (c.fadeIn > 0 && pos < c.fadeIn)
            v *= Math.max(0, pos / c.fadeIn);
        if (c.fadeOut > 0 && pos > win.len - c.fadeOut)
            v *= Math.max(0, (win.len - pos) / c.fadeOut);
        return Math.min(1, Math.max(0, v));
    }

    // One poll pass: start what is due, park what is past, repair what
    // drifted (scrubs land here as large jumps, ticks never reach it).
    function sync() {
        var d = preview.doc;
        if (!d || !d.anim.playing)
            return;
        var now = d.anim.currentTime;
        var dur = d.anim.duration;
        for (var i = 0; i < preview.pool.length; i++) {
            var p = preview.pool[i];
            if (!p)
                continue;
            var c = preview.findClip(preview.assign[i]);
            var win = c ? preview.audible(c, dur) : null;
            if (!win || now < win.start || now >= win.start + win.len) {
                if (p.playbackState === MediaPlayer.PlayingState)
                    p.pause();
                continue;
            }
            if (p.audioOutput)
                p.audioOutput.volume = preview.gainAt(c, win, now);
            var wantMs = (c.offset + (now - c.t0)) * 1000;
            if (p.playbackState !== MediaPlayer.PlayingState)
                p.play();
            if (preview.ready(p) && Math.abs(p.position - wantMs) > 350)
                p.setPosition(Math.max(0, wantMs));
        }
    }

    function parkAll() {
        for (var i = 0; i < preview.pool.length; i++) {
            var p = preview.pool[i];
            if (p && p.playbackState === MediaPlayer.PlayingState)
                p.pause();
        }
    }

    Timer {
        id: poller

        interval: 100
        repeat: true
        running: !!preview.doc && preview.doc.anim.playing
        onTriggered: preview.sync()
    }

    onDocChanged: preview.parkAll()

    Connections {
        target: preview.doc ? preview.doc.anim : null
        function onPlayingChanged() {
            if (!preview.doc)
                return;
            if (preview.doc.anim.playing)
                preview.sync();
            else
                preview.parkAll();
        }
    }
}
