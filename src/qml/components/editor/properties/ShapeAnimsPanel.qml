import QtQuick
import QtQuick.Controls
import Totm

// Shape animations panel: "+ New Animation" plus one card per clip on
// the current selection. Cards open their clip in the clip editor;
// the button routes to the preset gallery through newPolicy.
ScrollView {
    id: panel

    required property var doc

    property var newPolicy: null

    readonly property var cards: panel.collectCards()

    contentWidth: availableWidth
    clip: true

    Column {
        width: panel.availableWidth
        spacing: 12

        Item {
            width: parent.width
            height: 4
        }

        // Primary action: pick another preset from the gallery.
        Rectangle {
            width: parent.width - 24
            x: 12
            height: 40
            radius: 8
            scale: newMouse.pressed ? 0.98 : 1
            transformOrigin: Item.Center
            color: AppTheme.foreground

            Behavior on scale {
                NumberAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                anchors.centerIn: parent
                text: qsTr("New Animation")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: AppTheme.background
            }

            MouseArea {
                id: newMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (panel.newPolicy)
                        panel.newPolicy();
                }
            }
        }

        Repeater {
            model: panel.cards

            Rectangle {
                width: panel.availableWidth - 24
                x: 12
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
                        if (panel.doc)
                            panel.doc.selectClip(modelData.id, false);
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 12
        }
    }

    // Clips on the selected tops, earliest first. Reads rev (selection)
    // plus clips so both refresh the list.
    function collectCards() {
        var d = panel.doc;
        if (!d)
            return [];
        d.rev;
        var tops = d.selectedTops();
        var ids = {};
        for (var i = 0; i < tops.length; i++)
            ids[tops[i].uid] = true;
        var out = [];
        var clips = d.anim.clips;
        for (var j = 0; j < clips.length; j++) {
            if (!ids[clips[j].targetUid])
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
}
