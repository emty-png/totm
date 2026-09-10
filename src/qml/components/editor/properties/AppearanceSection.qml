import QtQuick
import QtQuick.Layouts
import Totm

// Opacity and corner radius with glyph adornments like the other
// sections (contrast/corner icons plus % unit). Shapes only; radius
// shows for every pointed shape except the ellipse, points for stars.
// The toggle after radius opens per-corner inputs in paint order:
// rectangle uses corner icons, triangle/star use numbers, stars show
// the first four with a Show more for the rest.
PanelSection {
    id: section

    required property var snapshot

    title: qsTr("Appearance")
    visible: section.snapshot.sel.length > 0 && !section.snapshot.hasGroup
    enabled: !section.snapshot.allLocked

    property bool showAllCorners: false
    // Expanded/collapsed is UI-only: collapsing hides the inputs but
    // never flattens the shape back to the uniform radius.
    property bool cornersExpanded: false

    function cornerType() {
        if (section.snapshot.allOfType("rectangle"))
            return "rectangle";
        if (section.snapshot.allOfType("triangle"))
            return "triangle";
        if (section.snapshot.allOfType("star"))
            return "star";
        return "";
    }

    function cornerCount() {
        var t = section.cornerType();
        if (t === "rectangle")
            return 4;
        if (t === "triangle")
            return 3;
        if (t === "star") {
            var top = 0;
            for (var i = 0; i < section.snapshot.sel.length; i++)
                top = Math.max(top, Math.max(3, Math.min(12, Math.round(section.snapshot.sel[i].points))));
            return top;
        }
        return 0;
    }

    function independentActive() {
        if (section.snapshot.sel.length === 0 || !section.snapshot.supportsRadius())
            return false;
        for (var i = 0; i < section.snapshot.sel.length; i++) {
            if (section.snapshot.sel[i].independentCorners !== true)
                return false;
        }
        return true;
    }

    function cornerAt(i) {
        var vals = [];
        for (var j = 0; j < section.snapshot.sel.length; j++) {
            var s = section.snapshot.sel[j];
            var arr = Array.isArray(s.cornerRadii) ? s.cornerRadii : [];
            vals.push(i < arr.length ? Math.max(0, Number(arr[i]) || 0) : Math.max(0, Number(s.radius) || 0));
        }
        return vals;
    }

    function cornerValue(i) {
        var vals = section.cornerAt(i);
        return vals.length > 0 ? vals[0] : 0;
    }

    function cornerMixed(i) {
        var vals = section.cornerAt(i);
        for (var k = 1; k < vals.length; k++) {
            if (vals[k] !== vals[0])
                return true;
        }
        return false;
    }

    function cornerIcon(i) {
        if (section.cornerType() !== "rectangle")
            return "";
        return ["cornerTL", "cornerTR", "cornerBR", "cornerBL"][i] || "";
    }

    function nodeCornerCount(s) {
        if (s.type === "rectangle")
            return 4;
        if (s.type === "triangle")
            return 3;
        if (s.type === "star")
            return Math.max(3, Math.min(12, Math.round(s.points)));
        return 0;
    }

    // Every corner value across the selection: independent nodes read
    // their array, linked ones repeat radius once (uniform by definition).
    function allCornerValues() {
        var out = [];
        for (var j = 0; j < section.snapshot.sel.length; j++) {
            var s = section.snapshot.sel[j];
            if (s.independentCorners === true && Array.isArray(s.cornerRadii) && s.cornerRadii.length > 0) {
                var n = Math.max(section.nodeCornerCount(s), s.cornerRadii.length);
                for (var i = 0; i < n; i++)
                    out.push(i < s.cornerRadii.length ? Math.max(0, Number(s.cornerRadii[i]) || 0) : Math.max(0, Number(s.radius) || 0));
            } else {
                out.push(Math.max(0, Number(s.radius) || 0));
            }
        }
        return out;
    }

    function uniformValue() {
        if (!section.independentActive())
            return section.snapshot.commonOf("radius").value;
        var vals = section.allCornerValues();
        return vals.length > 0 ? vals[0] : 0;
    }

    function uniformMixed() {
        if (!section.independentActive())
            return section.snapshot.commonOf("radius").mixed;
        var vals = section.allCornerValues();
        for (var k = 1; k < vals.length; k++) {
            if (vals[k] !== vals[0])
                return true;
        }
        return false;
    }

    function visibleCount() {
        var n = section.cornerCount();
        if (section.cornerType() === "star" && !section.showAllCorners && n > 4)
            return 4;
        return n;
    }

    RowLayout {
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            spacing: 4

            Text {
                text: qsTr("Opacity")
                font.pixelSize: 11
                color: AppTheme.muted
            }

            NumberField {
                Layout.fillWidth: true
                prefixIcon: "contrast"
                suffix: "%"
                value: Math.round(section.snapshot.commonOf("opacity").value * 100)
                mixed: section.snapshot.commonOf("opacity").mixed
                minimum: 0
                maximum: 100
                onCommitted: v => section.snapshot.setAll("opacity", v / 100)
                onScrubStarted: section.snapshot.beginScrub()
                onScrubFinished: section.snapshot.endScrub()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            visible: section.snapshot.supportsRadius()
            spacing: 4

            Text {
                text: qsTr("Corner radius")
                font.pixelSize: 11
                color: AppTheme.muted
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                NumberField {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    prefixIcon: "corner"
                    value: section.uniformValue()
                    mixed: section.uniformMixed()
                    minimum: 0
                    onCommitted: v => section.snapshot.doc.setUniformRadius(v)
                    onScrubStarted: section.snapshot.beginScrub()
                    onScrubFinished: section.snapshot.endScrub()
                }

                PanelIconButton {
                    iconKind: "corner"
                    filled: true
                    active: section.cornersExpanded
                    visible: !section.snapshot.allOfType("image")
                    onClicked: {
                        if (!section.independentActive())
                            section.snapshot.doc.toggleIndependentCorners(true);
                        section.cornersExpanded = !section.cornersExpanded;
                    }
                }
            }
        }
    }

    ColumnLayout {
        visible: section.cornersExpanded && section.independentActive() && section.cornerType() !== "" && !section.snapshot.allOfType("image")
        spacing: 8

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: section.visibleCount()

                delegate: Item {
                    required property int index

                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    implicitHeight: cornerField.implicitHeight

                    NumberField {
                        id: cornerField

                        anchors.fill: parent
                        prefixIcon: section.cornerIcon(index)
                        prefix: section.cornerIcon(index) === "" ? String(index + 1) : ""
                        value: section.cornerValue(index)
                        mixed: section.cornerMixed(index)
                        minimum: 0
                        onCommitted: v => section.snapshot.doc.setCornerRadius(index, v)
                        onScrubStarted: section.snapshot.beginScrub()
                        onScrubFinished: section.snapshot.endScrub()
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: section.cornerType() === "star" && section.cornerCount() > 4
            text: section.showAllCorners ? qsTr("Show less") : qsTr("Show more")
            font.pixelSize: 11
            color: showMoreMouse.containsMouse ? AppTheme.foreground : AppTheme.muted

            MouseArea {
                id: showMoreMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: section.showAllCorners = !section.showAllCorners
            }
        }
    }

    ColumnLayout {
        visible: section.snapshot.allOfType("star")
        spacing: 4

        Text {
            text: qsTr("Points")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        RowLayout {
            spacing: 8

            NumberField {
                Layout.fillWidth: true
                Layout.maximumWidth: Math.max(0, (section.width - 32) / 2)
                prefixIcon: "starFill"
                value: section.snapshot.commonOf("points").value
                mixed: section.snapshot.commonOf("points").mixed
                minimum: 3
                maximum: 12
                onCommitted: v => section.snapshot.setAll("points", v)
                onScrubStarted: section.snapshot.beginScrub()
                onScrubFinished: section.snapshot.endScrub()
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
