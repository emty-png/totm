import QtQuick
import QtQuick.Layouts
import Totm

// Pen-only properties: close/open every subpath, fill on/off for
// line-art, stroke cap/join, plus a subpath/point readout. Closed state
// reads live nodes (snapshots carry no pathData); touching sel keeps it
// fresh on every document mutation like the other sections.
PanelSection {
    id: section

    required property var snapshot
    required property var doc

    property var capCommon: section.snapshot.commonOf("strokeCap")
    property var joinCommon: section.snapshot.commonOf("strokeJoin")
    property var fillCommon: section.snapshot.commonOf("penFill")

    title: qsTr("Pen")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup && section.snapshot.allOfType("pen")
    enabled: !section.snapshot.allLocked

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: qsTr("Close path")
                font.pixelSize: 12
                color: AppTheme.foreground
            }

            Text {
                text: section.closedLabel()
                font.pixelSize: 11
                color: AppTheme.muted
            }

            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 22
                radius: AppTheme.radiusLarge
                color: section.closedState() === "closed" ? AppTheme.foreground : AppTheme.surface
                border.width: 1
                border.color: section.closedState() === "closed" ? AppTheme.foreground : AppTheme.fieldBorder

                Rectangle {
                    x: section.closedState() === "closed" ? parent.width - width - 3 : 3
                    y: 3
                    width: 16
                    height: 16
                    radius: AppTheme.radiusMedium
                    color: section.closedState() === "closed" ? AppTheme.background : AppTheme.muted
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: section.toggleClosed()
                }
            }
        }

        RowLayout {
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: qsTr("Fill")
                font.pixelSize: 12
                color: AppTheme.foreground
            }

            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 22
                radius: AppTheme.radiusLarge
                color: section.fillCommon.value === true ? AppTheme.foreground : AppTheme.surface
                border.width: 1
                border.color: section.fillCommon.value === true ? AppTheme.foreground : AppTheme.fieldBorder

                Rectangle {
                    x: section.fillCommon.value === true ? parent.width - width - 3 : 3
                    y: 3
                    width: 16
                    height: 16
                    radius: AppTheme.radiusMedium
                    color: section.fillCommon.value === true ? AppTheme.background : AppTheme.muted
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: section.snapshot.setAll("penFill", !(section.fillCommon.value === true))
                }
            }
        }

        Text {
            text: qsTr("Line cap")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            spacing: 8

            SegmentedOption {
                label: qsTr("Round")
                active: !section.capCommon.mixed && section.capCommon.value === "round"
                onClicked: section.snapshot.setAll("strokeCap", "round")
            }

            SegmentedOption {
                label: qsTr("Square")
                active: !section.capCommon.mixed && section.capCommon.value === "square"
                onClicked: section.snapshot.setAll("strokeCap", "square")
            }

            SegmentedOption {
                label: qsTr("Flat")
                active: !section.capCommon.mixed && section.capCommon.value === "flat"
                onClicked: section.snapshot.setAll("strokeCap", "flat")
            }
        }

        Text {
            text: qsTr("Line join")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            spacing: 8

            SegmentedOption {
                label: qsTr("Round")
                active: !section.joinCommon.mixed && section.joinCommon.value === "round"
                onClicked: section.snapshot.setAll("strokeJoin", "round")
            }

            SegmentedOption {
                label: qsTr("Bevel")
                active: !section.joinCommon.mixed && section.joinCommon.value === "bevel"
                onClicked: section.snapshot.setAll("strokeJoin", "bevel")
            }

            SegmentedOption {
                label: qsTr("Miter")
                active: !section.joinCommon.mixed && section.joinCommon.value === "miter"
                onClicked: section.snapshot.setAll("strokeJoin", "miter")
            }
        }
    }

    // "closed" when every qualifying subpath is closed, "open" when
    // none is, "mixed" otherwise. Single-point subpaths cannot close.
    function closedState() {
        var sel = section.snapshot.sel;
        if (!section.doc)
            return "mixed";
        var anyClosed = false, anyOpen = false;
        for (var i = 0; i < sel.length; i++) {
            var n = section.doc.findNode(sel[i].uid);
            var subs = (n && n.pathData) || [];
            for (var k = 0; k < subs.length; k++) {
                if (((subs[k] || {}).pts || []).length < 2)
                    continue;
                if (subs[k].closed === true)
                    anyClosed = true;
                else
                    anyOpen = true;
            }
        }
        if (anyClosed && !anyOpen)
            return "closed";
        if (anyOpen && !anyClosed)
            return "open";
        return "mixed";
    }

    function closedLabel() {
        var s = section.closedState();
        if (s === "closed")
            return qsTr("Closed");
        if (s === "open")
            return qsTr("Open");
        return qsTr("Mixed");
    }

    // Closing an open or mixed path closes everything; a fully closed
    // path opens back up.
    function toggleClosed() {
        if (section.doc)
            section.doc.setPenClosed(section.closedState() !== "closed");
    }
}
