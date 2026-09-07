import QtQuick
import QtQuick.Layouts
import Totm

// Dimensions editors with aspect lock. Unlocked commits one axis;
// locked scales the other proportionally from the current box so the
// selection keeps its shape. Group selections edit the bbox.
PanelSection {
    id: section

    required property var snapshot
    required property var doc

    property bool locked: false

    title: qsTr("Layout")
    visible: section.snapshot.sel.length > 0
    enabled: !section.snapshot.allLocked

    ColumnLayout {
        spacing: 4

        Text {
            text: qsTr("Dimensions")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            spacing: 8

            // Pinned shares: content length must never move siblings.
            NumberField {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                prefix: "W"
                value: section.snapshot.commonOf("w").value
                mixed: section.snapshot.commonOf("w").mixed
                minimum: 1
                onCommitted: v => section.commitW(v)
            }

            NumberField {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                prefix: "H"
                value: section.snapshot.commonOf("h").value
                mixed: section.snapshot.commonOf("h").mixed
                minimum: 1
                onCommitted: v => section.commitH(v)
            }

            PanelIconButton {
                iconKind: section.locked ? "lock" : "unlock"
                active: section.locked
                onClicked: section.locked = !section.locked
            }
        }
    }

    function commitW(v) {
        if (!section.locked) {
            section.snapshot.setAll("w", v);
            return;
        }
        var cw = section.snapshot.commonOf("w");
        var ch = section.snapshot.commonOf("h");
        if (!cw.mixed && !ch.mixed && cw.value > 0) {
            section.snapshot.setAll("w", v);
            section.snapshot.setAll("h", Math.max(1, ch.value * (v / cw.value)));
            return;
        }
        var box = section.doc ? section.doc.selectionBBox() : null;
        if (box && box.w > 0) {
            section.snapshot.setAll("w", v);
            section.snapshot.setAll("h", Math.max(1, box.h * (v / box.w)));
        } else {
            section.snapshot.setAll("w", v);
        }
    }

    function commitH(v) {
        if (!section.locked) {
            section.snapshot.setAll("h", v);
            return;
        }
        var cw = section.snapshot.commonOf("w");
        var ch = section.snapshot.commonOf("h");
        if (!cw.mixed && !ch.mixed && ch.value > 0) {
            section.snapshot.setAll("h", v);
            section.snapshot.setAll("w", Math.max(1, cw.value * (v / ch.value)));
            return;
        }
        var box = section.doc ? section.doc.selectionBBox() : null;
        if (box && box.h > 0) {
            section.snapshot.setAll("h", v);
            section.snapshot.setAll("w", Math.max(1, box.w * (v / box.h)));
        } else {
            section.snapshot.setAll("h", v);
        }
    }
}
