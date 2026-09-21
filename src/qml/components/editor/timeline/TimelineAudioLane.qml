import QtQuick
import Totm

// One audio lane row: a tape-style span bar (not animation diamonds:
// audio has no keyframes, both ends move the whole clip and it never
// stretches) with slim end-cap grips marking the grabbable ends.
// Selection stays the universal red wash + rim. Clicks select, Delete
// removes. Empty lane space falls through to the view marquee below.
// The bar carries a zoom-adaptive waveform (filled mini-bars over the
// clip file window, silent when undecodable) so beats stay visible.
// Drag state lives here while the bar stays model-bound: the doc clip
// updates silently in place (no rebuild) and release touches once for
// a single undo entry, like TimelineLane.
// Plain props with defaults (never required): Repeater delegates
// evaluate required bindings before the model context attaches, which
// breaks modelData reads. All drag paths null-guard.
Item {
    id: lane

    property var clip: null
    property real pxPerSec: 120
    property real originX: 0
    property bool selected: false

    // Plain (never required): this lane is a Repeater delegate, and
    // required bindings evaluate before the model context attaches,
    // which breaks the modelData reads below. All drag paths null-guard.
    property var doc: null

    property var clipPolicy: null

    // Active drag: press-time snapshot plus applied time. Visuals follow
    // dragT0 (not the model, which carries no mid-drag notifications).
    property bool dragging: false
    property int dragId: -1
    property real dragT0: 0
    property real snapT0: 0
    property real pressLx: 0

    // Zoom-adaptive waveform over the clip file window
    // [offset, offset + duration]: buckets follow the bar pixel width
    // (~2px per bar) so zooming re-slices instead of stretching. Empty
    // (no ffmpeg, undecodable, missing blob) keeps the plain bar below.
    // Move drags only shift t0, so peaks never recompute mid-drag.
    readonly property int waveBuckets: Math.min(512, Math.max(1, Math.floor(lane.barW() / 2)))
    readonly property var wavePeaks: lane.clip ? LibraryStore.audioPeaks(lane.clip.source || "", lane.waveBuckets, Number(lane.clip.offset) || 0, Math.max(0.05, Number(lane.clip.duration) || 0)) : []

    implicitHeight: 30

    // Bottom hairline pairing with the gutter label's own line so the
    // row reads across the divider.
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: AppTheme.border
    }

    function barX() {
        var t = lane.dragging ? lane.dragT0 : (lane.clip ? lane.clip.t0 : 0);
        return lane.originX + t * lane.pxPerSec;
    }

    function barW() {
        var d = lane.clip ? lane.clip.duration : 0;
        return Math.max(14, d * lane.pxPerSec);
    }

    // Tape bar for the clip: squared ends and grip caps instead of
    // keyframe diamonds, so audio never reads as animatable. The wave
    // spans edge to edge between the caps. Dragging the bar moves the
    // whole clip; end overflow is fine (use sites intersect with the
    // composition end). (Empty lane space falls through to the view
    // marquee below.)
    Rectangle {
        x: lane.barX()
        y: (parent.height - 18) / 2
        width: lane.barW()
        height: 18
        radius: 4
        color: lane.selected ? AppTheme.snapGuide : AppTheme.hover
        opacity: lane.selected ? 0.3 : 1
        border.width: 1
        border.color: lane.selected ? AppTheme.snapGuide : AppTheme.fieldBorder

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        MouseArea {
            id: barMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: lane.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            preventStealing: true
            onPressed: mouse => lane.dragPress(lane.clip ? lane.clip.id : -1, lane.mapFromItem(barMouse, mouse.x, mouse.y).x)
            onPositionChanged: mouse => lane.dragMove(lane.mapFromItem(barMouse, mouse.x, mouse.y).x)
            onReleased: lane.dragRelease()
            onClicked: mouse => {
                if (lane.clipPolicy && lane.clip)
                    lane.clipPolicy(lane.clip.id, !!(mouse.modifiers & (Qt.ControlModifier | Qt.MetaModifier)));
            }
        }

        // End-cap grips: visual drag affordance (input rides the bar
        // area above). Hidden on nub bars where caps would collide.
        Rectangle {
            x: 4
            y: (parent.height - height) / 2
            width: 3
            height: parent.height - 8
            radius: 1.5
            visible: lane.barW() > 30
            color: lane.selected ? AppTheme.background : AppTheme.muted
            opacity: lane.selected ? 0.9 : 0.6
        }

        Rectangle {
            x: parent.width - 7
            y: (parent.height - height) / 2
            width: 3
            height: parent.height - 8
            radius: 1.5
            visible: lane.barW() > 30
            color: lane.selected ? AppTheme.background : AppTheme.muted
            opacity: lane.selected ? 0.9 : 0.6
        }

        // Filled mini-bars over the clip window, running between the
        // caps; silence still draws a 1px flatline so presence reads
        // apart from undecodable.
        Canvas {
            id: waves

            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            visible: lane.wavePeaks.length > 0 && lane.barW() > 34
            property var peaks: lane.wavePeaks
            onPeaksChanged: waves.requestPaint()
            onWidthChanged: waves.requestPaint()
            onHeightChanged: waves.requestPaint()
            onAvailableChanged: {
                if (waves.available)
                    waves.requestPaint();
            }

            onPaint: {
                var ctx = waves.getContext("2d");
                // clearRect, not reset(): Qt's 2d context never
                // implemented reset(), so it throws and aborts the
                // paint leaving only the bare bar behind.
                ctx.globalAlpha = 1;
                ctx.clearRect(0, 0, waves.width, waves.height);
                var p = waves.peaks;
                if (!p || p.length === 0 || waves.width <= 0 || waves.height <= 0)
                    return;
                var n = p.length;
                var bw = waves.width / n;
                var muted = lane.clip && lane.clip.muted === true;
                ctx.fillStyle = String(lane.selected ? AppTheme.background : AppTheme.foreground);
                ctx.globalAlpha = muted ? 0.3 : (lane.selected ? 0.95 : 0.85);
                for (var i = 0; i < n; i++) {
                    var v = Math.min(1, Math.max(0, Number(p[i]) || 0));
                    // Display gamma: raw RMS sits low in the strip, so
                    // lift it (beats stay distinct, quiet lifts legible).
                    // Backend magnitudes stay honest 0..1 energy.
                    var g = Math.pow(v, 0.5);
                    var h = Math.max(1, Math.min(waves.height, g * waves.height));
                    var w = Math.max(1, bw - 0.5);
                    ctx.fillRect(i * bw, (waves.height - h) / 2, w, h);
                }
                ctx.globalAlpha = 1;
            }
        }
    }

    function findClip() {
        if (!lane.doc || !lane.clip)
            return null;
        return lane.doc.audioClip(lane.clip.id);
    }

    // Snap to zero, the playhead and every audio sibling end in the
    // document within 6px, plus animation ends so music lines up with
    // motion like everything else does.
    function snapTime(t) {
        var threshold = 6 / lane.pxPerSec;
        var best = t, bestDist = threshold;
        var consider = v => {
            var dist = Math.abs(t - v);
            if (dist < bestDist) {
                bestDist = dist;
                best = v;
            }
        };
        consider(0);
        if (!lane.doc)
            return Math.round(best * 100) / 100;
        consider(lane.doc.anim.currentTime);
        var auds = lane.doc.audio.clips;
        for (var i = 0; i < auds.length; i++) {
            if (auds[i].id === lane.dragId)
                continue;
            consider(auds[i].t0);
            consider(auds[i].t0 + auds[i].duration);
        }
        var anims = lane.doc.anim.clips;
        for (var j = 0; j < anims.length; j++) {
            consider(anims[j].t0);
            consider(anims[j].t0 + anims[j].duration);
        }
        return Math.round(best * 100) / 100;
    }

    function dragPress(clipId, lx) {
        var c = lane.findClip();
        if (!c || !lane.doc || c.id !== clipId)
            return;
        // Passive: selecting must not disturb playback.
        lane.doc.beginPassiveTransaction();
        lane.dragId = clipId;
        lane.snapT0 = c.t0;
        lane.dragT0 = c.t0;
        lane.pressLx = lx;
        lane.dragging = false;
    }

    function dragMove(lx) {
        if (lane.dragId < 0 || !lane.doc)
            return;
        if (!lane.dragging && Math.abs(lx - lane.pressLx) < 4)
            return;
        lane.dragging = true;
        var dx = (lx - lane.pressLx) / lane.pxPerSec;
        lane.dragT0 = Math.max(0, lane.snapTime(lane.snapT0 + dx));
        lane.doc.nudgeAudioClip(lane.dragId, lane.dragT0);
    }

    function dragRelease() {
        var d = lane.doc;
        var id = lane.dragId;
        var moved = lane.dragging;
        var t0 = lane.dragT0;
        lane.dragging = false;
        lane.dragId = -1;
        if (!d)
            return;
        if (moved) {
            // Value already sits final via nudges: one touch stages the
            // single undo entry that end() commits.
            d.nudgeAudioClip(id, t0);
            d.touch();
        }
        d.endTransaction();
    }
}
