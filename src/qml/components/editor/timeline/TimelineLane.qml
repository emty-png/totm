import QtQuick
import Totm

// One timeline lane: span bars per clip plus draggable diamond keyframes
// at each clip end. Start diamonds and bars move the whole clip, end
// diamonds stretch its duration (6px snap to playhead, zero and sibling
// ends); clicks still select, Delete still removes. Stored animation
// keys show as small ticks on their bar: click selects and seeks,
// drag retimes between neighbors. Stepped clips
// (hide/show, appear, flip) are instants: one diamond at t0, no bar,
// nothing to stretch. Empty lane space falls through to the view marquee
// below for multi-select. Drag state lives here while delegates stay
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
    // Joint-move state, owned by the view and shared across lanes
    // (selections span rows): press-time t0/dur per selected id, the
    // live delta in seconds, and whether a joint drag is showing.
    property var jointPolicy: null
    property var jointOrig: ({})
    property real jointDx: 0
    property bool jointActive: false

    // Active drag: press-time snapshot plus applied times. Visuals follow
    // these (not the model, which carries no mid-drag notifications).
    property bool dragging: false
    property int dragClipId: -1
    property string dragMode: "move"
    property real dragT0: 0
    property real dragDur: 0
    property real pressLx: 0
    // Key-drag state (dragMode "key"): press-time clip-local t plus
    // the live absolute time the tick follows.
    property int dragKeyIndex: -1
    property real snapKeyT: 0
    property real snapKeyAbs: 0
    property real dragKeyAbs: 0

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

    // Stepped clips (hide/show, appear, flip) are instants, not spans:
    // one diamond at t0, no bar, no stretch handle.
    function isStepped(preset) {
        if (!lane.doc)
            return false;
        return lane.doc.anim.presets.isStepped(preset);
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
            visible: !lane.isStepped(modelData.preset)
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

            // Loop badge: one glyph so short clips still read as looped.
            Text {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    rightMargin: 3
                }
                visible: modelData.loop === "loop" || modelData.loop === "pingpong"
                text: modelData.loop === "pingpong" ? "⇄" : "⟳"
                font.pixelSize: 9
                color: AppTheme.foreground
                opacity: 0.9
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

    // Keyframe ticks, one small diamond per stored key at its
    // absolute time. Click selects the clip and seeks; drag retimes
    // the key between its neighbors (single undo entry, snapped).
    Repeater {
        model: lane.keyTicks()

        Rectangle {
            x: lane.tickX(modelData) - width / 2
            y: (parent.height - height) / 2
            width: 8
            height: 8
            rotation: 45
            radius: 2
            color: AppTheme.foreground
            border.width: 1
            border.color: AppTheme.fieldBorder

            MouseArea {
                id: keyMouse

                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                onPressed: mouse => lane.keyPress(modelData.clipId, modelData.keyIndex, lane.mapFromItem(keyMouse, mouse.x, mouse.y).x)
                onPositionChanged: mouse => lane.keyMove(lane.mapFromItem(keyMouse, mouse.x, mouse.y).x)
                onReleased: lane.keyRelease()
                onClicked: mouse => lane.keyClick(modelData.clipId, modelData.keyIndex, !!(mouse.modifiers & (Qt.ControlModifier | Qt.MetaModifier)))
            }
        }
    }

    // Bar geometry, following the drag while one is active on its clip.
    // Joint clips ride the shared delta off their press-time snapshot
    // (the model mutates silently, so only these scalars stay stable).
    function barX(snap) {
        if (lane.dragging && snap.id === lane.dragClipId)
            return lane.laneX(lane.dragT0);
        if (lane.jointActive && lane.jointOrig[snap.id] !== undefined)
            return lane.laneX(lane.jointOrig[snap.id].t0 + lane.jointDx);
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
        var o = lane.jointActive ? lane.jointOrig[end.clipId] : undefined;
        if (o !== undefined)
            return lane.laneX(o.t0 + lane.jointDx + (end.end === "end" ? o.dur : 0));
        return lane.laneX(end.x);
    }

    // Both ends of every clip as {clipId, x seconds, end}. Stepped
    // clips expose only their start: one keyframe, nothing to stretch.

    function keyEnds() {
        var out = [];
        var list = lane.clips || [];
        for (var i = 0; i < list.length; i++) {
            out.push({
                clipId: list[i].id,
                x: list[i].t0,
                end: "start"
            });
            if (lane.isStepped(list[i].preset))
                continue;
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

    // Stored keys as {clipId, keyIndex, x seconds}. Stepped clips
    // carry no keys; single stored keys show too (they mark time
    // even before driving interpolation).
    function keyTicks() {
        var out = [];
        var list = lane.clips || [];
        for (var i = 0; i < list.length; i++) {
            if (lane.isStepped(list[i].preset))
                continue;
            var keys = list[i].options ? list[i].options.keys : null;
            if (!keys || typeof keys.length !== "number")
                continue;
            for (var k = 0; k < keys.length; k++) {
                out.push({
                    clipId: list[i].id,
                    keyIndex: k,
                    x: list[i].t0 + Number(keys[k].t) * list[i].duration
                });
            }
        }
        return out;
    }

    // Tick geometry, following clip drags (move/stretch/joint) plus
    // the active key drag's own live time.
    function tickX(tick) {
        if (lane.dragging && tick.clipId === lane.dragClipId) {
            if (lane.dragMode === "key" && tick.keyIndex === lane.dragKeyIndex)
                return lane.laneX(lane.dragKeyAbs);
            if (lane.dragMode === "move")
                return lane.laneX(tick.x + lane.dragT0 - lane.snapT0);
            if (lane.dragMode === "stretch") {
                var c = lane.findClip(tick.clipId);
                var kt = (c && c.options && c.options.keys && c.options.keys[tick.keyIndex]) ? Number(c.options.keys[tick.keyIndex].t) : 0;
                return lane.laneX(lane.dragT0 + kt * lane.dragDur);
            }
        }
        if (lane.jointActive && lane.jointOrig[tick.clipId] !== undefined)
            return lane.laneX(tick.x + lane.jointDx);
        return lane.laneX(tick.x);
    }

    function keyClipAt(clipId, keyIndex) {
        var c = lane.findClip(clipId);
        if (!c || !c.options || !c.options.keys || keyIndex < 0 || keyIndex >= c.options.keys.length)
            return null;
        return c;
    }

    function keyPress(clipId, keyIndex, lx) {
        var c = lane.keyClipAt(clipId, keyIndex);
        if (!c || !lane.doc)
            return;
        lane.doc.beginPassiveTransaction();
        lane.dragClipId = clipId;
        lane.dragMode = "key";
        lane.dragKeyIndex = keyIndex;
        lane.snapKeyT = Number(c.options.keys[keyIndex].t);
        lane.snapKeyAbs = c.t0 + lane.snapKeyT * c.duration;
        lane.dragKeyAbs = lane.snapKeyAbs;
        lane.pressLx = lx;
        lane.dragging = false;
    }

    function keyMove(lx) {
        if (lane.dragClipId < 0 || lane.dragKeyIndex < 0 || !lane.doc)
            return;
        if (!lane.dragging && Math.abs(lx - lane.pressLx) < 4)
            return;
        if (!lane.dragging)
            lane.doc.anim.settlePreview();
        lane.dragging = true;
        var c = lane.keyClipAt(lane.dragClipId, lane.dragKeyIndex);
        if (!c)
            return;
        var raw = lane.snapKeyAbs + (lx - lane.pressLx) / lane.pxPerSec;
        var local = (lane.snapTime(raw) - c.t0) / Math.max(0.001, c.duration);
        if (lane.doc.nudgeKey(lane.dragClipId, lane.dragKeyIndex, local))
            lane.dragKeyAbs = c.t0 + Number(c.options.keys[lane.dragKeyIndex].t) * c.duration;
        if (!lane.doc.anim.playing)
            lane.doc.seekPlayhead(lane.doc.anim.currentTime);
    }

    function keyRelease() {
        var d = lane.doc;
        var id = lane.dragClipId, idx = lane.dragKeyIndex;
        if (id < 0)
            return;
        var moved = lane.dragging;
        var abs = lane.dragKeyAbs;
        lane.dragging = false;
        lane.dragClipId = -1;
        lane.dragMode = "move";
        lane.dragKeyIndex = -1;
        if (!d)
            return;
        if (moved) {
            var c = lane.keyClipAt(id, idx);
            if (c)
                d.nudgeKey(id, idx, (abs - c.t0) / Math.max(0.001, c.duration));
            d.touch();
        }
        d.endTransaction();
    }

    function keyClick(clipId, keyIndex, additive) {
        var c = lane.keyClipAt(clipId, keyIndex);
        if (!c || !lane.doc)
            return;
        if (lane.diamondPolicy)
            lane.diamondPolicy(clipId, additive);
        lane.doc.seekPlayhead(c.t0 + Number(c.options.keys[keyIndex].t) * c.duration);
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
        var auds = lane.doc.audio.clips;
        for (var j = 0; j < auds.length; j++) {
            consider(auds[j].t0);
            consider(auds[j].t0 + auds[j].duration);
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
        // Joint-move press snapshot: every selected clip anywhere in the
        // document rides the same delta when this drag moves. Published
        // to the view (shared across lanes); visuals stay still until
        // the first move flips jointActive on.
        var orig = {};
        var ids = [];
        if (mode === "move" && lane.doc.anim.isClipSelected(clipId)) {
            var sel = lane.doc.anim.selectedClipIds;
            var all = lane.doc.anim.clips;
            for (var i = 0; i < all.length; i++) {
                if (sel.indexOf(all[i].id) >= 0) {
                    orig[all[i].id] = {
                        t0: all[i].t0,
                        dur: all[i].duration
                    };
                    ids.push(all[i].id);
                }
            }
        }
        lane.jointIds = ids;
        lane.jointSnap = orig;
        if (lane.jointPolicy)
            lane.jointPolicy("begin", orig);
    }

    // Ids riding the active joint drag (press-time snapshot above).
    property var jointIds: []
    // Local press-time snapshot (bindings to the view copy exist for
    // the other lanes' visuals; the drag itself reads this).
    property var jointSnap: ({})

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
        var comp = Math.max(0.5, lane.doc.anim.duration);
        if (lane.dragMode === "stretch") {
            var end = Math.min(comp, lane.snapTime(lane.snapT0 + lane.snapDur + (lx - lane.pressLx) / lane.pxPerSec));
            lane.dragT0 = lane.snapT0;
            lane.dragDur = Math.min(60, Math.max(0.1, end - lane.snapT0));
            lane.doc.nudgeClip(lane.dragClipId, lane.dragT0, lane.dragDur);
        } else if (lane.jointIds.length > 1) {
            // Joint move: the dragged clip snaps, everyone rides the
            // same delta, clamped so the whole formation stays inside
            // the composition. Silent nudges + one touch on release =
            // a single undo entry for the formation.
            var want = lane.snapTime(lane.snapT0 + (lx - lane.pressLx) / lane.pxPerSec);
            var dx = lane.clampJointDx(lane.jointIds, want - lane.snapT0, comp);
            for (var i = 0; i < lane.jointIds.length; i++) {
                var o = lane.jointSnap[lane.jointIds[i]];
                lane.doc.nudgeClip(lane.jointIds[i], o.t0 + dx, o.dur);
            }
            lane.dragT0 = lane.snapT0 + dx;
            lane.dragDur = lane.snapDur;
            if (lane.jointPolicy)
                lane.jointPolicy("move", dx);
        } else {
            // Both ends stay inside the composition: move keeps the whole
            // clip in range, stretch pins its end to the duration.
            var cap = Math.max(0, comp - lane.snapDur);
            lane.dragT0 = Math.min(cap, Math.max(0, lane.snapTime(lane.snapT0 + (lx - lane.pressLx) / lane.pxPerSec)));
            lane.dragDur = lane.snapDur;
            lane.doc.nudgeClip(lane.dragClipId, lane.dragT0, lane.dragDur);
        }
        if (!lane.doc.anim.playing)
            lane.doc.seekPlayhead(lane.doc.anim.currentTime);
    }

    // Widest delta keeping every joint clip inside [0, comp].
    function clampJointDx(ids, dx, comp) {
        var lo = -Infinity, hi = Infinity;
        for (var i = 0; i < ids.length; i++) {
            var o = lane.jointSnap[ids[i]];
            lo = Math.max(lo, 0 - o.t0);
            hi = Math.min(hi, comp - o.dur - o.t0);
        }
        return Math.min(hi, Math.max(lo, dx));
    }

    function dragRelease() {
        var d = lane.doc;
        var id = lane.dragClipId;
        var moved = lane.dragging;
        var t0 = lane.dragT0, dur = lane.dragDur;
        var joint = lane.jointIds.length > 1 ? lane.jointIds.slice() : [];
        lane.dragging = false;
        lane.dragClipId = -1;
        lane.jointIds = [];
        lane.jointSnap = {};
        if (lane.jointPolicy)
            lane.jointPolicy("end", 0);
        if (!d)
            return;
        if (moved) {
            // Values already sit final via nudges: one touch stages the
            // single undo entry that end() commits (formation included).
            if (joint.length > 1) {
                for (var i = 0; i < joint.length; i++) {
                    var o = d.anim.clipById(joint[i]);
                    if (o)
                        d.nudgeClip(joint[i], o.t0, o.duration);
                }
            } else {
                d.nudgeClip(id, t0, dur);
            }
            d.touch();
        }
        d.endTransaction();
    }
}
