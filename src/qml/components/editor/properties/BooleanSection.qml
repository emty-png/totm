import QtQuick
import QtQuick.Layouts
import Totm

// Boolean group editors: op switching plus release. Visible only for a
// single selected boolean group. Style stays live: Fill, Stroke,
// Appearance and Effects sections edit the group's own stacks directly
// (seeded from the bottommost donor at combine time).
PanelSection {
    id: section

    required property var snapshot
    required property var doc

    title: qsTr("Boolean")
    visible: {
        var tops = section.snapshot.tops;
        if (tops.length !== 1 || !section.doc)
            return false;
        return section.doc.isBooleanGroup(tops[0]);
    }
    enabled: !section.snapshot.allLocked

    function currentOp() {
        var tops = section.snapshot.tops;
        if (tops.length !== 1)
            return "";
        return String(tops[0].boolOp || "union").toLowerCase();
    }

    ColumnLayout {
        spacing: 4

        RowLayout {
            spacing: 4

            SegmentedOption {
                label: qsTr("Union")
                active: section.currentOp() === "union"
                onClicked: section.doc.setBoolOp(section.snapshot.tops[0].uid, "union")
            }
            SegmentedOption {
                label: qsTr("Subtract")
                active: section.currentOp() === "subtract"
                onClicked: section.doc.setBoolOp(section.snapshot.tops[0].uid, "subtract")
            }
        }

        RowLayout {
            spacing: 4

            SegmentedOption {
                label: qsTr("Intersect")
                active: section.currentOp() === "intersect"
                onClicked: section.doc.setBoolOp(section.snapshot.tops[0].uid, "intersect")
            }
            SegmentedOption {
                label: qsTr("Exclude")
                active: section.currentOp() === "exclude"
                onClicked: section.doc.setBoolOp(section.snapshot.tops[0].uid, "exclude")
            }
        }

        SegmentedOption {
            label: qsTr("Release")
            active: false
            onClicked: section.doc.releaseBoolean()
        }
    }
}
