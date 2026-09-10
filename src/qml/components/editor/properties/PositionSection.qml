import QtQuick
import QtQuick.Layouts
import Totm

// Position editors: X/Y plus rotation with quarter-turn and mirror
// actions. Group selections edit the bbox (scales the subtree); shape
// selections edit leaves via snapshot.setAll. Rotation row stays
// shape-only; flips mirror paint, bbox untouched.
// Alignment intentionally omitted: no canvas align model exists yet.
PanelSection {
    id: section

    required property var snapshot
    required property var doc

    title: qsTr("Position")
    visible: section.snapshot.sel.length > 0
    enabled: !section.snapshot.allLocked

    // True when every selected leaf shares the flip flag (uniform
    // false counts as off); mixed selections read as off.
    function flipCommon(role) {
        var c = section.snapshot.commonOf(role);
        return !c.mixed && c.value === true;
    }

    ColumnLayout {
        spacing: 4

        Text {
            text: qsTr("Position")
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
                prefix: "X"
                value: section.snapshot.commonOf("x").value
                mixed: section.snapshot.commonOf("x").mixed
                onCommitted: v => section.snapshot.setAll("x", v)
                onScrubStarted: section.snapshot.beginScrub()
                onScrubFinished: section.snapshot.endScrub()
            }

            NumberField {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                prefix: "Y"
                value: section.snapshot.commonOf("y").value
                mixed: section.snapshot.commonOf("y").mixed
                onCommitted: v => section.snapshot.setAll("y", v)
                onScrubStarted: section.snapshot.beginScrub()
                onScrubFinished: section.snapshot.endScrub()
            }
        }
    }

    ColumnLayout {
        visible: !section.snapshot.hasGroup
        spacing: 4

        Text {
            text: qsTr("Rotation")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            spacing: 8

            NumberField {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                prefix: "∠"
                suffix: "°"
                value: section.snapshot.commonOf("rotation").value
                mixed: section.snapshot.commonOf("rotation").mixed
                onCommitted: v => section.snapshot.setAll("rotation", v)
                onScrubStarted: section.snapshot.beginScrub()
                onScrubFinished: section.snapshot.endScrub()
            }

            // Button trio takes the second half, split in thirds.
            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                spacing: 8

                PanelIconButton {
                    Layout.fillWidth: true
                    iconKind: "rotate"
                    onClicked: section.doc.rotateSelected90()
                }

                PanelIconButton {
                    Layout.fillWidth: true
                    iconKind: "flipH"
                    active: section.flipCommon("flipH")
                    onClicked: section.doc.flipSelectedH()
                }

                PanelIconButton {
                    Layout.fillWidth: true
                    iconKind: "flipV"
                    active: section.flipCommon("flipV")
                    onClicked: section.doc.flipSelectedV()
                }
            }
        }
    }
}
