import QtQuick
import Totm

// One audio lane row: a span bar with diamond keyframes at both ends,
// all in the animation-lane language. Diamonds rest ghost-filled
// (surface) instead of solid white so music reads apart from regular
// keyframes; selection stays the universal red wash + rim. Both ends
// move the whole clip (no stretch in v1). Clicks select, Delete
// removes. Empty lane space falls through to the view marquee below.
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

    // Both ends of the clip for the diamonds. Duration never stretches,
    // so the end rides the start while dragging.
    function keyEnds() {
        if (!lane.clip)
            return [];
        return [
            {
                end: "start"
            },
            {
                end: "end"
            }
        ];
    }

    function endX(end) {
        var base = lane.dragging ? lane.dragT0 : (lane.clip ? lane.clip.t0 : 0);
        var d = lane.clip ? lane.clip.duration : 0;
        return lane.originX + (base + (end.end === "end" ? d : 0)) * lane.pxPerSec;
    }

    // Span bar for the clip, full end-to-end under the diamonds so it
    // reads as one connected unit like animation lanes. Dragging the
    // bar moves the whole clip; end overflow is fine (use sites
    // intersect with the composition end). (Empty lane space falls
    // through to the view marquee below.)
    Rectangle {
        x: lane.barX()
        y: (parent.height - 10) / 2
        width: lane.barW()
        height: 10
        radius: 5
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
    }

    // Diamond keyframes at both clip ends, same geometry as animation
    // diamonds. Both move (audio never stretches); the ghost fill sets
    // them apart from regular keyframes.
    Repeater {
        model: lane.keyEnds()

        Rectangle {
            x: lane.endX(modelData) - width / 2
            y: (parent.height - height) / 2
            width: 12
            height: 12
            rotation: 45
            radius: 2.5
            scale: lane.selected ? 1.18 : 1
            color: lane.selected ? AppTheme.snapGuide : AppTheme.surface
            border.width: 1.25
            border.color: lane.selected ? "#ffffff" : AppTheme.fieldBorder

            Behavior on scale {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                id: endMouse

                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: lane.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                preventStealing: true
                onPressed: mouse => lane.dragPress(lane.clip ? lane.clip.id : -1, lane.mapFromItem(endMouse, mouse.x, mouse.y).x)
                onPositionChanged: mouse => lane.dragMove(lane.mapFromItem(endMouse, mouse.x, mouse.y).x)
                onReleased: lane.dragRelease()
                onClicked: mouse => {
                    if (lane.clipPolicy && lane.clip)
                        lane.clipPolicy(lane.clip.id, !!(mouse.modifiers & (Qt.ControlModifier | Qt.MetaModifier)));
                }
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
