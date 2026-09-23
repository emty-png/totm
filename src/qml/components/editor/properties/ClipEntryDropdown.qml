import QtQuick
import QtQuick.Layouts
import Totm

// Stack-entry target dropdown shared by style/effect clip editors.
// Lists the target's stack top-first with off/inner badges and reseeds
// only the From side on retarget, so the clip start never jumps.
// Index 0 is the top entry; missing keys read 0.
ColumnLayout {
    id: entry

    required property var doc
    required property var clip
    required property int clipId
    required property string entryKind

    readonly property var opts: entry.clip ? entry.clip.options || {} : ({})
    readonly property var entryDefaults: DocCustomDefaults {}
    readonly property var targetTop: {
        if (entry.doc)
            entry.doc.rev;
        if (!entry.doc || !entry.clip)
            return null;
        var n = entry.doc.findNode(entry.clip.targetUid);
        if (!n)
            return null;
        if (n.kind === "shape")
            return n;
        var leaves = entry.doc._leavesUnder(n);
        return leaves.length > 0 ? leaves[0] : null;
    }
    readonly property string indexKey: entry.entryKind === "fills" ? "fillIndex" : entry.entryKind === "strokes" ? "strokeIndex" : entry.entryKind === "shadows" ? "shadowIndex" : "glowIndex"

    spacing: 8
    Layout.fillWidth: true

    Text {
        text: entry.entryKind === "fills" ? qsTr("Fill entry") : entry.entryKind === "strokes" ? qsTr("Stroke entry") : entry.entryKind === "shadows" ? qsTr("Shadow entry") : qsTr("Glow entry")
        font.pixelSize: 11
        color: AppTheme.muted
    }

    PanelDropdown {
        Layout.fillWidth: true
        options: entry.entryOptions()
        currentId: String(entry.entryIndex())
        onPicked: id => entry.retargetEntry(Number(id))
    }

    function entryIndex() {
        var raw = entry.opts[entry.indexKey];
        if (raw === undefined)
            return 0;
        var n = Math.round(Number(raw));
        if (isNaN(n))
            return 0;
        return Math.min(32, Math.max(0, n));
    }

    function entryOptions() {
        var out = [];
        var list = (entry.targetTop && entry.targetTop[entry.entryKind]) || [];
        var base = entry.entryKind === "fills" ? qsTr("Fill ") : entry.entryKind === "strokes" ? qsTr("Stroke ") : entry.entryKind === "shadows" ? qsTr("Shadow ") : qsTr("Glow ");
        var showInner = entry.entryKind === "shadows" || entry.entryKind === "glows";
        for (var i = 0; i < list.length; i++) {
            var e = list[i] || {};
            out.push({
                id: String(i),
                name: base + (i + 1) + (e.enabled === false ? qsTr(" (off)") : "") + (showInner && e.inner === true ? qsTr(" · inner") : "")
            });
        }
        if (out.length === 0)
            out.push({
                id: "0",
                name: base + "1"
            });
        return out;
    }

    function retargetEntry(i) {
        if (!entry.doc || !entry.clip || i === entry.entryIndex())
            return;
        var node = entry.doc.findNode(entry.clip.targetUid);
        var tops = node ? [node] : [];
        var patch = entry.entryDefaults.fromPatchForEntry(entry.doc.anim.presets, entry.doc, tops, entry.clip.preset, i);
        entry.doc.setClipOptions(entry.clipId, patch);
    }
}
