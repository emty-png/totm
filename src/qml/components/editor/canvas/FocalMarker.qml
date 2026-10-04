import QtQuick
import Totm

// Focal-point marker for the selected video zoom clip. Shows where the
// clip's punch-in centers on the canvas (frame UV mapped through the
// leaf's fit mode, mirroring the export math) and drags it: press grabs
// the point, moves stream focusX/focusY into the clip options in one
// undo entry, release commits. Visible only for a single selected
// customVideoZoom clip on a video leaf with probed frame dims.
Item {
    id: marker

    anchors.fill: parent

    required property var doc
    required property real zoom
    required property real offsetX
    required property real offsetY

    readonly property real cz: marker.zoom > 0 ? marker.zoom : 1

    // Probed frame dims, refreshed when the target changes (never in a
    // binding: the first probe spawns ffmpeg and must not run per frame).
    property real frameW: 0
    property real frameH: 0

    property bool dragging: false
    property bool begun: false

    visible: marker.focal() !== null

    readonly property var fp: marker.focal()

    function clamp01(v) {
        if (!(v >= 0))
            return 0;
        if (!(v <= 1))
            return 1;
        return v;
    }

    // Single selected zoom clip on a video leaf, with focal UV. Null
    // unless everything resolves (single selection, right preset,
    // video target, known dims).
    function target() {
        var d = marker.doc;
        if (!d)
            return null;
        d.rev;
        var a = d.anim;
        if (!a)
            return null;
        var ids = a.selectedClipIds || [];
        if (ids.length !== 1)
            return null;
        var c = d.animClip(ids[0]);
        if (!c || c.preset !== "customVideoZoom")
            return null;
        var n = d.findNode(c.targetUid);
        if (!n || n.kind !== "shape" || n.shapeType !== "video")
            return null;
        if (!(marker.frameW > 0) || !(marker.frameH > 0))
            return null;
        if (!(n.w > 0) || !(n.h > 0))
            return null;
        var o = c.options || {};
        return {
            id: c.id,
            leaf: n,
            fw: marker.frameW,
            fh: marker.frameH,
            fx: marker.clamp01(Number(o.focusX !== undefined ? o.focusX : 0.5)),
            fy: marker.clamp01(Number(o.focusY !== undefined ? o.focusY : 0.5))
        };
    }

    // Probe key: clip + target + source. Focal edits keep the same key
    // so drags never re-probe mid-gesture.
    function probeKey() {
        var d = marker.doc;
        if (!d)
            return "";
        d.rev;
        var a = d.anim;
        if (!a)
            return "";
        var ids = a.selectedClipIds || [];
        if (ids.length !== 1)
            return "";
        var c = d.animClip(ids[0]);
        if (!c || c.preset !== "customVideoZoom")
            return "";
        var n = d.findNode(c.targetUid);
        if (!n || n.kind !== "shape" || n.shapeType !== "video")
            return "";
        return c.id + "|" + c.targetUid + "|" + String(n.videoSource ?? "");
    }

    readonly property string key: marker.probeKey()
    onKeyChanged: marker.refreshProbe()
    Component.onCompleted: marker.refreshProbe()

    function refreshProbe() {
        var d = marker.doc;
        if (!d) {
            marker.frameW = 0;
            marker.frameH = 0;
            return;
        }
        var a = d.anim;
        var ids = a ? (a.selectedClipIds || []) : [];
        var n = null;
        if (ids.length === 1) {
            var c = d.animClip(ids[0]);
            if (c && c.preset === "customVideoZoom")
                n = d.findNode(c.targetUid);
        }
        if (!n || n.kind !== "shape" || n.shapeType !== "video") {
            marker.frameW = 0;
            marker.frameH = 0;
            return;
        }
        var src = String(n.videoSource ?? "");
        if (src === "") {
            marker.frameW = 0;
            marker.frameH = 0;
            return;
        }
        var pr = LibraryStore.videoProbe(src);
        marker.frameW = Number(pr.width) || 0;
        marker.frameH = Number(pr.height) || 0;
    }

    // Frame UV (0..1 of the decoded frame) to content coords: fit
    // letterboxes centered, cover crops centered, fill stretches, then
    // the leaf rotation about its center.
    function frameToContent(fx, fy, t) {
        var n = t.leaf, fw = t.fw, fh = t.fh;
        var fit = n.videoFit;
        if (fit !== "cover" && fit !== "fill")
            fit = "fit";
        var bx, by;
        if (fit === "fill") {
            bx = fx * n.w;
            by = fy * n.h;
        } else {
            var s = fit === "cover" ? Math.max(n.w / fw, n.h / fh) : Math.min(n.w / fw, n.h / fh);
            if (!(s > 0))
                return null;
            if (fit === "cover") {
                var sw = n.w / s, sh = n.h / s;
                var sx = (fw - sw) / 2, sy = (fh - sh) / 2;
                bx = (fx * fw - sx) * s;
                by = (fy * fh - sy) * s;
            } else {
                var dw = fw * s, dh = fh * s;
                bx = (n.w - dw) / 2 + fx * dw;
                by = (n.h - dh) / 2 + fy * dh;
            }
        }
        var rad = (Number(n.rotation) || 0) * Math.PI / 180;
        var cx = n.x + n.w / 2, cy = n.y + n.h / 2;
        var dx = (n.x + bx) - cx, dy = (n.y + by) - cy;
        var cos = Math.cos(rad), sin = Math.sin(rad);
        return {
            x: cx + dx * cos - dy * sin,
            y: cy + dx * sin + dy * cos
        };
    }

    // Content coords back to frame UV (inverse of the above), clamped
    // to the frame like the sampler clamps the focal.
    function contentToFrame(px, py, t) {
        var n = t.leaf, fw = t.fw, fh = t.fh;
        var rad = (Number(n.rotation) || 0) * Math.PI / 180;
        var cx = n.x + n.w / 2, cy = n.y + n.h / 2;
        var dx = px - cx, dy = py - cy;
        var cos = Math.cos(rad), sin = Math.sin(rad);
        var bx = dx * cos + dy * sin + n.w / 2;
        var by = -dx * sin + dy * cos + n.h / 2;
        var fit = n.videoFit;
        if (fit !== "cover" && fit !== "fill")
            fit = "fit";
        var fx, fy;
        if (fit === "fill") {
            fx = bx / n.w;
            fy = by / n.h;
        } else {
            var s = fit === "cover" ? Math.max(n.w / fw, n.h / fh) : Math.min(n.w / fw, n.h / fh);
            if (!(s > 0))
                return null;
            if (fit === "cover") {
                var sw = n.w / s, sh = n.h / s;
                var sx = (fw - sw) / 2, sy = (fh - sh) / 2;
                fx = (sx + bx / s) / fw;
                fy = (sy + by / s) / fh;
            } else {
                var dw = fw * s, dh = fh * s;
                fx = (bx - (n.w - dw) / 2) / dw;
                fy = (by - (n.h - dh) / 2) / dh;
            }
        }
        return {
            fx: marker.clamp01(fx),
            fy: marker.clamp01(fy)
        };
    }

    function focal() {
        var t = marker.target();
        if (!t)
            return null;
        return marker.frameToContent(t.fx, t.fy, t);
    }

    function moveTo(sx, sy) {
        var t = marker.target();
        if (!t || !marker.doc)
            return;
        var uv = marker.contentToFrame((sx - marker.offsetX) / marker.cz, (sy - marker.offsetY) / marker.cz, t);
        if (!uv)
            return;
        var fx = Math.round(uv.fx * 10000) / 10000;
        var fy = Math.round(uv.fy * 10000) / 10000;
        if (fx === t.fx && fy === t.fy)
            return;
        if (!marker.begun) {
            marker.doc.beginTransaction();
            marker.begun = true;
        }
        marker.doc.setClipOptions(t.id, {
            focusX: fx,
            focusY: fy
        });
    }

    Item {
        id: grab

        x: marker.fp ? Math.round(marker.offsetX + marker.fp.x * marker.cz) - 9 : 0
        y: marker.fp ? Math.round(marker.offsetY + marker.fp.y * marker.cz) - 9 : 0
        width: 18
        height: 18

        Rectangle {
            x: 3
            y: 3
            width: 12
            height: 12
            radius: 6
            color: "#ffffff"
            border.width: 1.5
            border.color: AppTheme.selection
        }

        Rectangle {
            x: 7
            y: 7
            width: 4
            height: 4
            radius: 2
            color: AppTheme.selection
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.CrossCursor
            preventStealing: true
            onPressed: event => {
                marker.dragging = true;
                marker.begun = false;
                marker.moveTo(grab.x + event.x, grab.y + event.y);
                event.accepted = true;
            }
            onPositionChanged: event => {
                if (marker.dragging)
                    marker.moveTo(grab.x + event.x, grab.y + event.y);
            }
            onReleased: {
                if (marker.begun && marker.doc)
                    marker.doc.endTransaction();
                marker.begun = false;
                marker.dragging = false;
            }
        }

        MeasurePill {
            property var ft: marker.target()
            label: ft ? Math.round(ft.fx * 100) + "% · " + Math.round(ft.fy * 100) + "%" : ""
            shown: marker.dragging
            x: Math.min(Math.max(grab.x + 22, 4), Math.max(4, marker.width - width - 4))
            y: Math.min(Math.max(grab.y + 22, 4), Math.max(4, marker.height - height - 4))
        }
    }
}
