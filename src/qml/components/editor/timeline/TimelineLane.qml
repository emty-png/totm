import QtQuick
import Totm

// One timeline lane: span bars per clip plus draggable diamond keyframes
// at each clip end. Start diamonds and bars move the whole clip, end
// diamonds stretch its duration (6px snap to playhead, zero and sibling
// ends); clicks still select, Delete still removes. Empty lane space
// falls through to the view marquee below for multi-select. Drag state lives here while delegates stay
// model-bound: the doc clips update silently in place (no rebuild, live
// canvas preview) and release touches once for a single undo entry.
// Plain props with defaults (never required): Repeater delegates
// evaluate required bindings before the model context attaches, which
// breaks modelData reads.
Item {
    id: lane

    property int laneUid: -1
    property string laneName: ""
    property var clips: []
    property real pxPerSec: 120
    property real originX: 0
    property var selectedIds: []

    // Plain (never required): this lane is a Repeater delegate, and
    // required bindings evaluate before the model context attaches,
    // which breaks the modelData reads below. All drag paths null-guard.
    property var doc: null

    property var diamondPolicy: null

    // Active drag: press-time snapshot plus applied times. Visuals follow
    // these (not the model, which carries no mid-drag notifications).
    property bool dragging: false
    property int dragClipId: -1
    property string dragMode: "move"
    property real dragT0: 0
    property real dragDur: 0
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

    function isSelected(id) {
        return lane.selectedIds.indexOf(id) >= 0;
    }

    function laneX(t) {
        return lane.originX + t * lane.pxPerSec;
    }

    // Span bar per clip, full end-to-end under the diamonds so each
    // clip reads as one connected unit. Dragging the bar moves the clip.
    // (Empty lane space falls through to the view marquee below.)
    Repeater {
        model: lane.clips

        Rectangle {
            x: lane.barX(modelData)
            y: (parent.height - 10) / 2
            width: Math.max(14, lane.barW(modelData))
            height: 10
            radius: 5
            // Selected clips wash red (calm in both themes) instead of a
            // solid bar; resting clips stay in theme neutrals.
            color: lane.isSelected(modelData.id) ? AppTheme.snapGuide : AppTheme.hover
            opacity: lane.isSelected(modelData.id) ? 0.3 : 1
            border.width: 1
            border.color: lane.isSelected(modelData.id) ? AppTheme.snapGuide : AppTheme.fieldBorder

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
                onPressed: mouse => lane.dragPress(modelData.id, "move", lane.mapFromItem(barMouse, mouse.x, mouse.y).x)
                onPositionChanged: mouse => lane.dragMove(lane.mapFromItem(barMouse, mouse.x, mouse.y).x)
                onReleased: lane.dragRelease()
                onClicked: mouse => {
                    if (lane.diamondPolicy)
                        lane.diamondPolicy(modelData.id, !!(mouse.modifiers & (Qt.ControlModifier | Qt.MetaModifier)));
                }
            }
        }
    }

    // Diamond keyframes at both clip ends: start moves, end stretches.
    Repeater {
        model: lane.keyEnds()

        Rectangle {
            x: lane.endX(modelData) - width / 2
            y: (parent.height - height) / 2
            width: 12
            height: 12
            rotation: 45
            radius: 2.5
            scale: lane.isSelected(modelData.clipId) ? 1.18 : 1
            // Diamonds stay white in every theme (theme-proof ends);
            // selected ones go red with a white rim to match the wash.
            color: lane.isSelected(modelData.clipId) ? AppTheme.snapGuide : "#ffffff"
            border.width: 1.25
            border.color: lane.isSelected(modelData.clipId) ? "#ffffff" : AppTheme.fieldBorder

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
                cursorShape: lane.dragging ? Qt.ClosedHandCursor : modelData.end === "end" ? Qt.SizeHorCursor : Qt.PointingHandCursor
                preventStealing: true
                onPressed: mouse => lane.dragPress(modelData.clipId, modelData.end === "end" ? "stretch" : "move", lane.mapFromItem(endMouse, mouse.x, mouse.y).x)
                onPositionChanged: mouse => lane.dragMove(lane.mapFromItem(endMouse, mouse.x, mouse.y).x)
                onReleased: lane.dragRelease()
                onClicked: mouse => {
                    if (lane.diamondPolicy)
                        lane.diamondPolicy(modelData.clipId, !!(mouse.modifiers & (Qt.ControlModifier | Qt.MetaModifier)));
                }
            }
        }
    }

    // Bar geometry, following the drag while one is active on its clip.
    function barX(snap) {
        if (lane.dragging && snap.id === lane.dragClipId)
            return lane.laneX(lane.dragT0);
        return lane.laneX(snap.t0);
    }

    function barW(snap) {
        if (lane.dragging && snap.id === lane.dragClipId)
            return lane.dragDur * lane.pxPerSec;
        return snap.duration * lane.pxPerSec;
    }

    function endX(end) {
        if (lane.dragging && end.clipId === lane.dragClipId)
            return lane.laneX(end.end === "end" ? lane.dragT0 + lane.dragDur : lane.dragT0);
        return lane.laneX(end.x);
    }

    // Both ends of every clip as {clipId, x seconds, end}.
    function keyEnds() {
        var out = [];
        var list = lane.clips || [];
        for (var i = 0; i < list.length; i++) {
            out.push({
                clipId: list[i].id,
                x: list[i].t0,
                end: "start"
            });
            out.push({
                clipId: list[i].id,
                x: list[i].t0 + list[i].duration,
                end: "end"
            });
        }
        return out;
    }

    function findClip(id) {
        var list = lane.clips || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id)
                return list[i];
        }
        return null;
    }

    // Snap to zero, the playhead and every other clip end in the
    // document within 6px (lanes hold one clip each now, so siblings
    // live across rows).
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
        var list = lane.doc.anim.clips;
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === lane.dragClipId)
                continue;
            consider(list[i].t0);
            consider(list[i].t0 + list[i].duration);
        }
        return Math.round(best * 100) / 100;
    }

    function dragPress(clipId, mode, lx) {
        var c = lane.findClip(clipId);
        if (!c || !lane.doc)
            return;
        // Passive: selecting must not disturb playback; the first real
        // move below settles explicitly before mutating.
        lane.doc.beginPassiveTransaction();
        lane.dragClipId = clipId;
        lane.dragMode = mode;
        lane.storeOrig(c);
        lane.pressLx = lx;
        lane.dragging = false;
    }

    // Press-time snapshot kept as plain props (the model object mutates
    // silently underneath, so only scalars are stable).
    property real snapT0: 0
    property real snapDur: 0

    function storeOrig(c) {
        lane.snapT0 = c.t0;
        lane.snapDur = c.duration;
        lane.dragT0 = c.t0;
        lane.dragDur = c.duration;
    }

    function dragMove(lx) {
        if (lane.dragClipId < 0 || !lane.doc)
            return;
        if (!lane.dragging && Math.abs(lx - lane.pressLx) < 4)
            return;
        if (!lane.dragging)
            lane.doc.anim.settlePreview();
        lane.dragging = true;
        var dx = (lx - lane.pressLx) / lane.pxPerSec;
        // Both ends stay inside the composition: move keeps the whole
        // clip in range, stretch pins its end to the duration.
        var comp = Math.max(0.5, lane.doc.anim.duration);
        if (lane.dragMode === "stretch") {
            var end = Math.min(comp, lane.snapTime(lane.snapT0 + lane.snapDur + dx));
            lane.dragT0 = lane.snapT0;
            lane.dragDur = Math.min(60, Math.max(0.1, end - lane.snapT0));
        } else {
            var cap = Math.max(0, comp - lane.snapDur);
            lane.dragT0 = Math.min(cap, Math.max(0, lane.snapTime(lane.snapT0 + dx)));
            lane.dragDur = lane.snapDur;
        }
        lane.doc.nudgeClip(lane.dragClipId, lane.dragT0, lane.dragDur);
        if (!lane.doc.anim.playing)
            lane.doc.seekPlayhead(lane.doc.anim.currentTime);
    }

    function dragRelease() {
        var d = lane.doc;
        var id = lane.dragClipId;
        var moved = lane.dragging;
        var t0 = lane.dragT0, dur = lane.dragDur;
        lane.dragging = false;
        lane.dragClipId = -1;
        if (!d)
            return;
        if (moved) {
            // Values already sit final via nudges: one touch stages the
            // single undo entry that end() commits.
            d.nudgeClip(id, t0, dur);
            d.touch();
        }
        d.endTransaction();
    }
}
