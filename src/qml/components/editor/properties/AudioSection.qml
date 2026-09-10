import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtMultimedia
import Totm

// Audio properties for the selected timeline clips (animate mode).
// Timing, volume/mute and fades with mixed-value handling across the
// selection; replace swaps the file under every selected clip while
// keeping each clip's timing (trimmed to the new file).
ScrollView {
    id: panel

    required property var doc

    // Touched so value bindings follow in-place lane drags (which bump
    // rev without reassigning the clips array).
    readonly property int tick: panel.doc ? panel.doc.rev : 0
    readonly property int selCount: panel.doc ? panel.doc.audio.selectedAudioIds.length : 0

    contentWidth: availableWidth
    clip: true

    function common(role) {
        panel.tick;
        if (!panel.doc)
            return {
                mixed: true,
                value: 0
            };
        return panel.doc.audioCommon(role);
    }

    function commit(role, value) {
        if (panel.doc)
            panel.doc.setAudioProp(role, value);
    }

    function scrubStart() {
        if (panel.doc)
            panel.doc.beginTransaction();
    }

    function scrubEnd() {
        if (panel.doc)
            panel.doc.endTransaction();
    }

    ColumnLayout {
        width: panel.availableWidth
        spacing: 0

        PanelSection {
            Layout.fillWidth: true
            title: qsTr("Audio") + (panel.selCount > 1 ? " (" + panel.selCount + ")" : "")
            visible: panel.selCount > 0

            ColumnLayout {
                spacing: 4

                Text {
                    text: qsTr("Start")
                    font.pixelSize: 11
                    color: AppTheme.muted
                }

                RowLayout {
                    spacing: 8

                    NumberField {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: 0
                        prefix: qsTr("T")
                        suffix: qsTr("s")
                        value: panel.common("t0").value
                        mixed: panel.common("t0").mixed
                        minimum: 0
                        onCommitted: v => panel.commit("t0", v)
                        onScrubStarted: panel.scrubStart()
                        onScrubFinished: panel.scrubEnd()
                    }

                    NumberField {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: 0
                        prefix: qsTr("D")
                        suffix: qsTr("s")
                        value: panel.common("duration").value
                        mixed: panel.common("duration").mixed
                        minimum: 0.05
                        onCommitted: v => panel.commit("duration", v)
                        onScrubStarted: panel.scrubStart()
                        onScrubFinished: panel.scrubEnd()
                    }
                }
            }

            ColumnLayout {
                spacing: 4

                Text {
                    text: qsTr("File offset")
                    font.pixelSize: 11
                    color: AppTheme.muted
                }

                RowLayout {
                    spacing: 8

                    NumberField {
                        Layout.fillWidth: true
                        Layout.maximumWidth: Math.max(0, (panel.availableWidth - 24 - 8) / 2)
                        prefix: qsTr("O")
                        suffix: qsTr("s")
                        value: panel.common("offset").value
                        mixed: panel.common("offset").mixed
                        minimum: 0
                        onCommitted: v => panel.commit("offset", v)
                        onScrubStarted: panel.scrubStart()
                        onScrubFinished: panel.scrubEnd()
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }
            }

            // Labeled action in the popup-button language (surface rest,
            // hover fill, muted-to-foreground label).
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 6
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: replaceMouse.containsMouse || replaceMouse.pressed ? AppTheme.hover : AppTheme.surface

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Replace audio")
                    font.pixelSize: 12
                    color: replaceMouse.containsMouse || replaceMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: replaceMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: replacePicker.open()
                }
            }
        }

        PanelSection {
            Layout.fillWidth: true
            title: qsTr("Volume")
            visible: panel.selCount > 0

            RowLayout {
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    spacing: 4

                    Text {
                        text: qsTr("Level")
                        font.pixelSize: 11
                        color: AppTheme.muted
                    }

                    NumberField {
                        Layout.fillWidth: true
                        suffix: qsTr("%")
                        value: Math.round(panel.common("volume").value * 100)
                        mixed: panel.common("volume").mixed
                        minimum: 0
                        maximum: 100
                        onCommitted: v => panel.commit("volume", v / 100)
                        onScrubStarted: panel.scrubStart()
                        onScrubFinished: panel.scrubEnd()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    spacing: 4

                    Text {
                        text: qsTr("Mute")
                        font.pixelSize: 11
                        color: AppTheme.muted
                    }

                    PanelIconButton {
                        iconKind: "music"
                        filled: true
                        active: !panel.common("muted").mixed && panel.common("muted").value === true
                        onClicked: {
                            if (panel.doc)
                                panel.doc.toggleAudioMuted();
                        }
                    }
                }
            }
        }

        PanelSection {
            Layout.fillWidth: true
            title: qsTr("Fades")
            visible: panel.selCount > 0

            RowLayout {
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    spacing: 4

                    Text {
                        text: qsTr("Fade in")
                        font.pixelSize: 11
                        color: AppTheme.muted
                    }

                    NumberField {
                        Layout.fillWidth: true
                        suffix: qsTr("s")
                        value: panel.common("fadeIn").value
                        mixed: panel.common("fadeIn").mixed
                        minimum: 0
                        onCommitted: v => panel.commit("fadeIn", v)
                        onScrubStarted: panel.scrubStart()
                        onScrubFinished: panel.scrubEnd()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    spacing: 4

                    Text {
                        text: qsTr("Fade out")
                        font.pixelSize: 11
                        color: AppTheme.muted
                    }

                    NumberField {
                        Layout.fillWidth: true
                        suffix: qsTr("s")
                        value: panel.common("fadeOut").value
                        mixed: panel.common("fadeOut").mixed
                        minimum: 0
                        onCommitted: v => panel.commit("fadeOut", v)
                        onScrubStarted: panel.scrubStart()
                        onScrubFinished: panel.scrubEnd()
                    }
                }
            }
        }
    }

    // Replace flow: picker hands the user file to the probe, which reads
    // the duration before anything is copied (mirrors the timeline
    // import). The probe keeps its last file loaded: clearing the source
    // mid-demux tears down the backend pipeline under in-flight events.
    FileDialog {
        id: replacePicker

        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Audio (*.mp3 *.wav *.ogg *.flac)")]
        currentFolder: StandardPaths.writableLocation(StandardPaths.MusicLocation)
        onAccepted: panel.probeAudio(selectedFile)
    }

    MediaPlayer {
        id: replaceProbe

        property url probeSource
        property bool armed: false

        onDurationChanged: {
            if (replaceProbe.armed && duration > 0)
                panel.commitProbe();
        }
        onErrorOccurred: {
            replaceProbe.armed = false;
        }
    }

    Timer {
        id: probeTimeout

        interval: 5000
        onTriggered: replaceProbe.armed = false
    }

    function probeAudio(file) {
        replaceProbe.probeSource = file;
        replaceProbe.armed = true;
        replaceProbe.source = file;
        probeTimeout.restart();
    }

    function commitProbe() {
        replaceProbe.armed = false;
        probeTimeout.stop();
        var secs = replaceProbe.duration / 1000;
        if (!panel.doc || secs <= 0)
            return;
        var name = LibraryStore.importAudio(replaceProbe.probeSource);
        if (!name)
            return;
        panel.doc.replaceAudioSource(name, secs);
    }
}
