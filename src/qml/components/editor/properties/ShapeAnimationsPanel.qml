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

        Row {
            width: parent.width - 24
            x: 12
            height: 28
            spacing: 4

            Text {
                width: parent.width - 28
                anchors.verticalCenter: parent.verticalCenter
                text: panel.headerName()
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: AppTheme.foreground
                elide: Text.ElideRight
            }

            PanelIconButton {
                id: dotsBtn

                iconKind: "dots"
                filled: false
                iconSize: 14
                enabled: !!panel.doc
                onClicked: copyMenu.openNear(dotsBtn, dotsBtn.width / 2, dotsBtn.height / 2)
            }
        }

        PropCopyMenu {
            id: copyMenu

            doc: panel.doc
            scope: "anim"
            clipIds: panel.copySourceIds()
            targetUids: panel.targetTopUids()
        }

        // Primary action: pick another preset from the gallery.
        Rectangle {
            width: parent.width - 24
            x: 12
            height: 40
            radius: AppTheme.radiusMedium
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
                radius: AppTheme.radiusMedium
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
                        right: deleteButton.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                        rightMargin: 8
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

                PanelIconButton {
                    id: deleteButton

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 8
                    }
                    iconKind: "close"
                    filled: false
                    iconSize: 12
                    onClicked: {
                        if (panel.doc)
                            panel.doc.deleteClips([modelData.id]);
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 12
        }
    }

    // Clip ids to copy: the selection when clips are selected,
    // else every card on the current selection.
    function copySourceIds() {
        var d = panel.doc;
        if (!d)
            return [];
        if (d.anim.selectedClipIds.length > 0)
            return d.anim.selectedClipIds.slice();
        var out = [];
        var cards = panel.cards;
        for (var i = 0; i < cards.length; i++)
            out.push(cards[i].id);
        return out;
    }

    function targetTopUids() {
        var d = panel.doc;
        if (!d)
            return [];
        d.rev;
        var out = [];
        var tops = d.selectedTops();
        for (var i = 0; i < tops.length; i++)
            out.push(tops[i].uid);
        return out;
    }

    // Header name: selected shape's layer name (like the left
    // sidebar), count for multi-selections, fallback when empty.
    function headerName() {
        var d = panel.doc;
        if (!d)
            return qsTr("Animations");
        d.rev;
        var tops = d.selectedTops();
        if (tops.length === 1)
            return tops[0].name || qsTr("Animations");
        if (tops.length > 1)
            return qsTr("%1 selected").arg(tops.length);
        return qsTr("Animations");
    }

    // Clips on the selected tops, earliest first. Reads rev (selection)
    // plus clips so both refresh the list, plus clipRev so card time
    // ranges follow lane drags live (right-panel rebuilds are harmless;
    // the gesture lives in the timeline, not here).
    function collectCards() {
        var d = panel.doc;
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
            var loopSuffix = clips[j].loop === "loop" ? " · " + qsTr("Loop") : clips[j].loop === "pingpong" ? " · " + qsTr("Ping-pong") : "";
            var detail = clips[j].t0.toFixed(1) + "s – " + (clips[j].t0 + clips[j].duration).toFixed(1) + "s · " + d.anim.presets.easingName(clips[j].easing.id) + loopSuffix;
            if (d.anim.presets.isStepped(clips[j].preset))
                detail = qsTr("at %1s · Instant").arg(clips[j].t0.toFixed(1)) + loopSuffix;
            out.push({
                id: clips[j].id,
                name: d.anim.presets.presetName(clips[j].preset) + d.anim.presets.entrySuffix(clips[j].preset, clips[j].options),
                detail: detail
            });
        }
        out.sort((a, b) => a.id - b.id);
        return out;
    }
}
