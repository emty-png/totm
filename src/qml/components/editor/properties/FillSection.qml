import QtQuick
import QtQuick.Layouts
import Totm

// Single fill per shape. Transparent counts as missing: header + paints
// it black, header - clears the selection back to transparent, so shapes
// can carry no fill. Multi-selections list each distinct opaque fill;
// per-variant - shows only then. All edits stay selection-scoped.
PanelSection {
    id: section

    required property var snapshot
    required property var doc

    title: qsTr("Fill")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup
    enabled: !section.snapshot.allLocked
    compact: section.opaqueFills().length === 0
    showAdd: section.hasNoFill()
    showRemove: section.opaqueFills().length > 0
    onAddClicked: section.addFill()
    onRemoveClicked: section.removeFills()

    Repeater {
        model: section.opaqueFills()

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                radius: 6
                color: modelData
                border.width: 1
                border.color: AppTheme.border
            }

            HexField {
                Layout.fillWidth: true
                value: modelData
                onCommitted: c => section.doc.recolorSelected(modelData, c)
            }

            PanelIconButton {
                iconKind: "minimize"
                filled: false
                strong: true
                iconSize: 16
                visible: section.opaqueFills().length > 1
                onClicked: section.removeVariant(modelData)
            }
        }
    }

    function isNoFill(f) {
        var s = String(f).toLowerCase();
        if (s === "transparent" || s === "")
            return true;
        // Opaque serializes as #rrggbb, translucent as #aarrggbb.
        if (s.charAt(0) === "#" && s.length === 9)
            return s.slice(1, 3) === "00";
        return false;
    }

    function opaqueFills() {
        var out = [];
        var fills = section.snapshot.distinctFills();
        for (var i = 0; i < fills.length; i++) {
            if (!section.isNoFill(fills[i]))
                out.push(fills[i]);
        }
        return out;
    }

    function hasNoFill() {
        var fills = section.snapshot.distinctFills();
        for (var i = 0; i < fills.length; i++) {
            if (section.isNoFill(fills[i]))
                return true;
        }
        return false;
    }

    // Paint only the missing shapes black; opaque fills keep their color.
    function addFill() {
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            if (section.isNoFill(leaves[i].fill))
                section.doc.setShapeProp(leaves[i].uid, "fill", "#000000");
        }
    }

    // Clear the selection's fills (selection-scoped, lock-aware).
    function removeFills() {
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++)
            section.doc.setShapeProp(leaves[i].uid, "fill", "transparent");
    }

    // Clear one distinct fill variant within the selection only.
    function removeVariant(fillValue) {
        var leaves = section.snapshot.selLeaves;
        for (var i = 0; i < leaves.length; i++) {
            if (String(leaves[i].fill) === String(fillValue))
                section.doc.setShapeProp(leaves[i].uid, "fill", "transparent");
        }
    }
}
