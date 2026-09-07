import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Preset gallery for the animate tab: category sections of live tiles.
// Clicking a tile applies the preset to the current selection at the
// playhead (0.8s, entrance) and starts playback from there. One shared
// phase driver loops all thumbnails; cards bind it directly like the
// FillSection delegates bind their section.
ScrollView {
    id: gallery

    required property var doc
    property bool playing: false

    // Pick flow: opened from the shape panel, back returns there and a
    // successful apply reports through appliedPolicy (the new clip
    // selection routes onward to the clip editor).
    property bool showBack: false
    property var backPolicy: null
    property var appliedPolicy: null

    // Shared thumbnail clock: plays the effect, holds the base frame,
    // then loops. One driver for every card keeps thumbs in sync.
    property real phase: 0

    SequentialAnimation on phase {
        running: gallery.playing
        loops: Animation.Infinite

        NumberAnimation {
            from: 0
            to: 1
            duration: 1300
            easing.type: Easing.Linear
        }

        PauseAnimation {
            duration: 500
        }
    }

    contentWidth: availableWidth
    clip: true

    Column {
        width: gallery.availableWidth
        spacing: 0

        // Back to the shape panel when picking (hidden by default).
        RowLayout {
            visible: gallery.showBack
            width: parent.width
            height: visible ? 48 : 0
            spacing: 4

            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.leftMargin: 4

                TitleBarIcon {
                    anchors.centerIn: parent
                    kind: "caret"
                    rotation: 90
                    width: 14
                    height: 14
                    iconColor: galleryBackMouse.containsMouse || galleryBackMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: galleryBackMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (gallery.backPolicy)
                            gallery.backPolicy();
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Presets")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }
        }

        Text {
            visible: !gallery.hasSelection()
            width: parent.width - 32
            x: 16
            text: qsTr("Select a shape on the canvas to apply a preset.")
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
                    visible: modelData.title !== ""
                    width: parent.width - 24
                    x: 12
                    text: modelData.title
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: AppTheme.foreground
                }

                Grid {
                    width: parent.width - 24
                    x: 12
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 12

                    Repeater {
                        model: modelData.cards

                        PresetCard {
                            presetId: modelData.id
                            presetName: modelData.name
                            thumbOptions: modelData.options
                            easingId: modelData.easing
                            driver: gallery
                            clickPolicy: presetId => gallery.applyPreset(presetId)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 12
                }
            }
        }

        Item {
            width: parent.width
            height: 12
        }
    }

    // Category sections with per-card thumbnail options (small travel
    // so slide presets stay inside the tile).
    function sections() {
        return [
            {
                title: qsTr("Fade"),
                cards: [gallery.cardFor("fade", qsTr("Fade")), gallery.cardFor("slide", qsTr("Slide"))]
            },
            {
                title: qsTr("Scale"),
                cards: [gallery.cardFor("grow", qsTr("Grow")), gallery.cardFor("shrink", qsTr("Shrink"))]
            },
            {
                title: "",
                cards: [gallery.cardFor("spin", qsTr("Spin")), gallery.cardFor("twist", qsTr("Twist")), gallery.cardFor("movescale", qsTr("Move & Scale"))]
            }
        ];
    }

    function cardFor(id, name) {
        var options = {};
        var easing = "easeOut";
        if (id === "slide")
            options = {
                direction: "left",
                distance: 34,
                fade: true
            };
        else if (id === "spin") {
            options = {
                direction: "cw",
                turns: 1
            };
            easing = "linear";
        } else if (id === "twist") {
            options = {
                direction: "cw"
            };
            easing = "easeInOut";
        } else if (id === "movescale")
            options = {
                direction: "left",
                distance: 34,
                scale: 0
            };
        return {
            id: id,
            name: name,
            options: options,
            easing: easing
        };
    }

    function applyPreset(presetId) {
        var d = gallery.doc;
        if (!d)
            return;
        var tops = d.selectedTops();
        if (tops.length === 0)
            return;
        var uids = [];
        for (var i = 0; i < tops.length; i++)
            uids.push(tops[i].uid);
        var t0 = d.anim.currentTime;
        var made = d.applyPreset(presetId, uids, t0, 0.8, "in", {}, null);
        if (made.length > 0) {
            d.anim.currentTime = t0;
            d.anim.play();
            if (gallery.appliedPolicy)
                gallery.appliedPolicy();
        }
    }

    function hasSelection() {
        var d = gallery.doc;
        if (!d)
            return false;
        d.rev;
        return d.selectedTops().length > 0;
    }
}
