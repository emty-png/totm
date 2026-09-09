import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Custom animation gallery: grouped Add list (Transform / Style / Other
// plus motion Path) with existing custom clips below. From-to clips reuse
// the preset pipeline; Path enters canvas draw mode through drawPolicy.
// Seeded from the live selection so new clips start jump-free.
ScrollView {
    id: gallery

    required property var doc

    property var drawPolicy: null

    contentWidth: availableWidth
    clip: true

    Column {
        width: gallery.availableWidth
        spacing: 0

        // Breathing room below the switcher divider (matches the 12px
        // rhythm between sections); without it the first title sits
        // flush against the top edge.
        Item {
            width: parent.width
            height: 12
        }

        Text {
            visible: !gallery.hasSelection()
            width: parent.width - 32
            x: 16
            text: qsTr("Select a shape on the canvas to add a custom animation.")
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            color: AppTheme.muted
        }

        Repeater {
            model: gallery.sections()

            Column {
                width: parent.width
                spacing: 8

                Text {
                    width: parent.width - 24
                    x: 12
                    text: modelData.title
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: AppTheme.foreground
                }

                Column {
                    width: parent.width - 24
                    x: 12
                    spacing: 2

                    Repeater {
                        model: modelData.rows

                        Rectangle {
                            width: parent.width
                            height: 34
                            radius: 6
                            color: rowMouse.containsMouse || rowMouse.pressed ? AppTheme.hover : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: 100
                                    easing.type: Easing.OutCubic
                                }
                            }

                            RowLayout {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                spacing: 8

                                AppIcon {
                                    Layout.preferredWidth: 14
                                    Layout.preferredHeight: 14
                                    kind: modelData.icon
                                    iconColor: AppTheme.foreground
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    color: AppTheme.foreground
                                }

                                Text {
                                    visible: modelData.id === "customPath"
                                    text: qsTr("Draw")
                                    font.pixelSize: 11
                                    color: AppTheme.muted
                                }
                            }

                            MouseArea {
                                id: rowMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: gallery.activateRow(modelData.id)
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 12
                }
            }
        }

        Text {
            visible: gallery.hasSelection() && gallery.customCards().length > 0
            width: parent.width - 24
            x: 12
            text: qsTr("On this selection")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Column {
            width: parent.width - 24
            x: 12
            spacing: 8

            Repeater {
                model: gallery.customCards()

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: 8
                    color: cardMouse.containsMouse || cardMouse.pressed ? AppTheme.hover : AppTheme.surface
                    border.width: 1
                    border.color: AppTheme.fieldBorder

                    Behavior on color {
                        ColorAnimation {
                            duration: 100
                            easing.type: Easing.OutCubic
                        }
                    }

                    Column {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 12
                            rightMargin: 12
                        }
                        spacing: 2

                        Text {
                            width: parent.width
                            text: modelData.name
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            color: AppTheme.foreground
                        }

                        Text {
                            width: parent.width
                            text: modelData.detail
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            color: AppTheme.muted
                        }
                    }

                    MouseArea {
                        id: cardMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (gallery.doc)
                                gallery.doc.selectClip(modelData.id, false);
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 12
        }
    }

    function sections() {
        return [
            {
                title: qsTr("Transform"),
                rows: [
                    {
                        id: "customScale",
                        name: qsTr("Scale"),
                        icon: "square"
                    },
                    {
                        id: "customRotate",
                        name: qsTr("Rotate"),
                        icon: "rotate"
                    },
                    {
                        id: "customMove",
                        name: qsTr("Move"),
                        icon: "cursor"
                    }
                ]
            },
            {
                title: qsTr("Style"),
                rows: [
                    {
                        id: "customOpacity",
                        name: qsTr("Opacity"),
                        icon: "contrast"
                    },
                    {
                        id: "customColor",
                        name: qsTr("Color"),
                        icon: "apps"
                    }
                ]
            },
            {
                title: qsTr("Other"),
                rows: [
                    {
                        id: "customHide",
                        name: qsTr("Hide / Show"),
                        icon: "eye"
                    },
                    {
                        id: "customResize",
                        name: qsTr("Resize"),
                        icon: "maximize"
                    },
                    {
                        id: "customCorner",
                        name: qsTr("Corner Radius"),
                        icon: "corner"
                    },
                    {
                        id: "customStroke",
                        name: qsTr("Stroke"),
                        icon: "minimize"
                    }
                ]
            },
            {
                title: qsTr("Motion Path"),
                rows: [
                    {
                        id: "customPath",
                        name: qsTr("Path"),
                        icon: "pen"
                    }
                ]
            }
        ];
    }

    function activateRow(presetId) {
        if (presetId === "customPath") {
            if (gallery.drawPolicy)
                gallery.drawPolicy();
            return;
        }
        gallery.applyCustom(presetId);
    }

    function applyCustom(presetId) {
        var d = gallery.doc;
        if (!d)
            return;
        var tops = d.selectedTops();
        if (tops.length === 0)
            return;
        var uids = [];
        for (var i = 0; i < tops.length; i++)
            uids.push(tops[i].uid);
        var options = gallery.seededOptions(presetId, d, tops);
        var t0 = d.anim.currentTime;
        var made = d.applyPreset(presetId, uids, t0, 0.8, "in", options, null);
        if (made.length > 0) {
            d.anim.currentTime = t0;
            d.anim.play();
        }
    }

    // Seed from-to values from live nodes so new clips start at the
    // current look (no jump on first frame). Falls back to shared
    // defaults when the selection has no readable value.
    function seededOptions(presetId, d, tops) {
        var first = tops.length > 0 ? tops[0] : null;
        var leaf = first ? gallery.firstLeaf(d, first) : null;
        if (presetId === "customOpacity" && leaf) {
            var op = Math.min(1, Math.max(0, Number(leaf.opacity) || 0));
            return {
                from: Math.round(op * 100) / 100,
                to: op > 0.5 ? 0 : 1
            };
        }
        if (presetId === "customColor" && leaf) {
            var fill = String(leaf.fill || "#000000");
            return {
                from: fill,
                to: "#ff0000"
            };
        }
        if (presetId === "customResize" && leaf) {
            var fw = Math.max(1, Math.round(Number(leaf.w) || 100));
            var fh = Math.max(1, Math.round(Number(leaf.h) || 100));
            return {
                fromW: fw,
                fromH: fh,
                toW: Math.min(4000, Math.round(fw * 1.5)),
                toH: Math.min(4000, Math.round(fh * 1.5))
            };
        }
        if (presetId === "customCorner" && leaf) {
            var cr = Math.max(0, Number(leaf.radius) || 0);
            return {
                from: Math.round(cr * 100) / 100,
                to: cr === 0 ? 24 : 0
            };
        }
        if (presetId === "customStroke" && leaf) {
            var sw = Math.max(0, Number(leaf.strokeWidth) || 0);
            return {
                from: Math.round(sw * 100) / 100,
                to: sw === 0 ? 4 : 0
            };
        }
        return d.anim.presets.defaultsFor(presetId);
    }

    function firstLeaf(d, top) {
        if (!top)
            return null;
        if (top.kind === "shape")
            return top;
        var leaves = d._leavesUnder(top);
        return leaves.length > 0 ? leaves[0] : null;
    }

    function customCards() {
        var d = gallery.doc;
        if (!d)
            return [];
        d.rev;
        d.anim.clipRev;
        var tops = d.selectedTops();
        var ids = {};
        for (var i = 0; i < tops.length; i++)
            ids[tops[i].uid] = true;
        var out = [];
        var clips = d.anim.clips;
        for (var j = 0; j < clips.length; j++) {
            if (!ids[clips[j].targetUid])
                continue;
            if (!d.anim.presets.isCustom(clips[j].preset))
                continue;
            out.push({
                id: clips[j].id,
                name: d.anim.presets.presetName(clips[j].preset),
                detail: clips[j].t0.toFixed(1) + "s – " + (clips[j].t0 + clips[j].duration).toFixed(1) + "s · " + d.anim.presets.easingName(clips[j].easing.id)
            });
        }
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    function hasSelection() {
        var d = gallery.doc;
        if (!d)
            return false;
        d.rev;
        return d.selectedTops().length > 0;
    }
}
