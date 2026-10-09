import QtQuick
import QtQuick.Layouts
import Totm

// Shader assignment for vector shapes + pen + live booleans.
// Nodes carry shaderId ("preset:<id>" or custom asset uuid, "" = none)
// plus shaderMode ("fill"|"overlay") and shaderParams overrides.
// + opens the preset picker; Custom opens the centered shader popup
// (preview left, settings right) which saves to LibraryStore shaders.
PanelSection {
    id: section

    required property var snapshot
    property var popup: null

    title: qsTr("Shader")
    visible: section.snapshot.sel.length > 0 && section.shaderable()
    enabled: !section.snapshot.allLocked
    compact: !section.hasShader()
    showAdd: !section.hasShader()
    showRemove: section.hasShader()
    onAddClicked: section.applyPreset("plasma")
    onRemoveClicked: section.clearShader()

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: section.hasShader()

        Text {
            Layout.fillWidth: true
            text: section.shaderLabel()
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: AppTheme.foreground
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SegmentedOption {
                label: qsTr("Fill")
                active: section.commonMode() === "fill"
                onClicked: section.setMode("fill")
            }
            SegmentedOption {
                label: qsTr("Overlay")
                active: section.commonMode() === "overlay"
                onClicked: section.setMode("overlay")
            }
        }

        SegmentedOption {
            label: qsTr("Customize")
            active: false
            onClicked: {
                if (section.popup)
                    section.popup.openFor(section.snapshot);
            }
        }
    }

    // Only vector primitives + pen + live booleans. Text/image/video
    // and plain frames never show this section.
    function shaderable() {
        var leaves = section.snapshot.selLeaves;
        if (leaves.length === 0)
            return false;
        for (var i = 0; i < leaves.length; i++) {
            var t = leaves[i].type;
            if (!ShaderEngine.isShaderableType(t))
                return false;
            if (t === "frame")
                return false;
        }
        return true;
    }

    function hasShader() {
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            if (String(leaves[i].shaderId ?? "") !== "")
                return true;
        }
        return false;
    }

    function shaderLabel() {
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            var sid = String(leaves[i].shaderId ?? "");
            if (sid !== "")
                return section.resolveName(sid);
        }
        return qsTr("None");
    }

    function resolveName(sid) {
        if (sid.startsWith("preset:")) {
            var pid = sid.slice(7);
            return ShaderEngine.presetName(pid);
        }
        for (var i = 0; i < LibraryStore.shaderList.length; i++) {
            var s = LibraryStore.shaderList[i];
            if (s.shaderId === sid)
                return String(s.name ?? qsTr("Custom"));
        }
        return qsTr("Custom");
    }

    function commonMode() {
        var leaves = section.snapshot.selLeaves;
        if (leaves.length === 0)
            return "fill";
        var m = String(leaves[0].shaderMode ?? "fill");
        for (var i = 1; i < leaves.length; i++) {
            if (String(leaves[i].shaderMode ?? "fill") !== m)
                return m;
        }
        return (m === "overlay") ? "overlay" : "fill";
    }

    function applyPreset(pid) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d.styleTargets();
        var def = ShaderEngine.presetDefaults(pid);
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var t = leaves[i].shapeType ?? (leaves[i].boolOp !== undefined && leaves[i].boolOp !== "none" ? "boolean" : "");
            if (t !== "" && !ShaderEngine.isShaderableType(t === "boolean" ? "boolean" : t))
                continue;
            leaves[i].shaderId = "preset:" + pid;
            leaves[i].shaderMode = ShaderEngine.presetMode(pid);
            leaves[i].shaderParams = JSON.parse(JSON.stringify(def));
        }
        d.touch();
    }

    function setMode(v) {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d.styleTargets();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            if (String(leaves[i].shaderId ?? "") === "")
                continue;
            leaves[i].shaderMode = (v === "overlay") ? "overlay" : "fill";
        }
        d.touch();
    }

    function clearShader() {
        var d = section.snapshot.doc;
        if (!d)
            return;
        d.history.checkpoint();
        var leaves = d.styleTargets();
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            leaves[i].shaderId = "";
            leaves[i].shaderMode = "fill";
            leaves[i].shaderParams = ({});
        }
        d.touch();
    }
}
