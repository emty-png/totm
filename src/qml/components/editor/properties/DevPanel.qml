import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Dev tools panel for the right sidebar: HTML/CSS/JS switcher on top,
// a mono editor per tab, and a Run bar. Run compiles the HTML subset
// with the cascaded CSS plus the sandboxed JS ops into script-owned
// native nodes (one undo entry).
Item {
    id: devPanel

    property string mode: "html"
    property var doc: null

    // Console diagnostics across all tabs (errors first).
    function diagnostics() {
        var d = devPanel.doc;
        if (!d || !d.devScript)
            return [];
        var r = d.devScript.lastRun ?? {
            diagnostics: []
        };
        return r.diagnostics ?? [];
    }

    function diagnosticLabel(e) {
        var tab = String(e.tab ?? "").toUpperCase();
        if ((e.line ?? 0) > 0)
            return qsTr("%1 · Line %2: %3").arg(tab).arg(e.line).arg(e.message);
        return qsTr("%1: %2").arg(tab).arg(e.message);
    }

    // First Run error (or outcome) for the status line.
    function statusText() {
        var d = devPanel.doc;
        if (d && d.devScript && d.devScript.jsRunning)
            return qsTr("Running JS…");
        if (d && d.devScript && d.devScript.jsPickFlow) {
            var rows = devPanel.pickRows();
            var done = 0;
            for (var i = 0; i < rows.length; i++) {
                if (rows[i].done)
                    done++;
            }
            return qsTr("Pick %1 of %2 files…").arg(done).arg(rows.length);
        }
        var diags = devPanel.diagnostics();
        for (var i = 0; i < diags.length; i++) {
            if (diags[i].kind === "error")
                return devPanel.diagnosticLabel(diags[i]);
        }
        var made = (d && d.devScript && d.devScript.lastRun && d.devScript.lastRun.created) || [];
        if (made.length > 0)
            return qsTr("Created %n shape(s)", "", made.length);
        if (diags.length > 0)
            return qsTr("%n warning(s)", "", diags.length);
        return qsTr("No elements to run");
    }

    function statusIsError() {
        var diags = devPanel.diagnostics();
        for (var i = 0; i < diags.length; i++) {
            if (diags[i].kind === "error")
                return true;
        }
        return false;
    }

    function setTabCode(tab, code) {
        var d = devPanel.doc;
        if (!d || !d.script)
            return;
        if (String(d.script[tab] ?? "") === code)
            return;
        d.script[tab] = code;
        d.touch();
    }

    // Pick-flow rows: [{index, label, done}] from the script's pending
    // pick definitions plus already-chosen blobs.
    function pickRows() {
        var d = devPanel.doc;
        if (!d || !d.devScript || !d.devScript.jsPickFlow)
            return [];
        var defs = d.devScript.pickDefs ?? [];
        var blobs = d.devScript.pickBlobs ?? {};
        var rows = [];
        var counts = {};
        for (var i = 0; i < defs.length; i++) {
            var kind = String(defs[i].kind ?? "image");
            counts[kind] = (counts[kind] || 0) + 1;
            var label = qsTr("%1 %2").arg(kind === "audio" ? qsTr("Audio") : kind === "video" ? qsTr("Video") : qsTr("Image")).arg(counts[kind]);
            rows.push({
                index: defs[i].index,
                label: label,
                kind: kind,
                done: !!blobs[defs[i].index]
            });
        }
        return rows;
    }

    // Row kind for the file dialog currently choosing.
    property int choosingPick: -1

    function choosePickFile(index) {
        var d = devPanel.doc;
        if (!d || !d.devScript)
            return;
        var defs = d.devScript.pickDefs ?? [];
        var kind = "image";
        for (var i = 0; i < defs.length; i++) {
            if (defs[i].index === index)
                kind = String(defs[i].kind ?? "image");
        }
        devPanel.choosingPick = index;
        if (kind === "video")
            pickVideoFile.open();
        else if (kind === "audio")
            pickAudioFile.open();
        else
            pickImageFile.open();
    }

    function commitPickFile(kind, file) {
        var d = devPanel.doc;
        var index = devPanel.choosingPick;
        devPanel.choosingPick = -1;
        if (!d || !d.devScript || index < 0 || !file)
            return;
        var blob = "";
        if (kind === "video")
            blob = LibraryStore.importVideo(file);
        else if (kind === "audio")
            blob = LibraryStore.importAudio(file);
        else
            blob = LibraryStore.importImage(file);
        if (!blob)
            return;
        d.devScript.resolvePick(index, blob);
    }

    function cancelPickFile() {
        devPanel.choosingPick = -1;
        if (devPanel.doc && devPanel.doc.devScript)
            devPanel.doc.devScript.cancelPicks();
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // Track.
        Item {
            width: parent.width
            height: 48

            Rectangle {
                id: track
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 8
                    rightMargin: 8
                }
                height: 32
                radius: AppTheme.radiusMedium
                color: AppTheme.hover

                // Sliding thumb (a third of the track minus gaps).
                Rectangle {
                    id: thumb
                    x: devPanel.mode === "html" ? 2 : devPanel.mode === "css" ? thumb.width + 4 : track.width - width - 2
                    y: 2
                    width: (track.width - 8) / 3
                    height: 28
                    radius: AppTheme.radiusSmall
                    color: AppTheme.foreground

                    Behavior on x {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutBack
                            easing.overshoot: 0.85
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    spacing: 0

                    // Three static segments (a Repeater would hide outer
                    // scope from qmllint inside its delegate).
                    Item {
                        width: track.width / 3
                        height: track.height

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("HTML")
                            font.pixelSize: 12
                            font.weight: devPanel.mode === "html" ? Font.DemiBold : Font.Medium
                            color: devPanel.mode === "html" ? AppTheme.background : htmlMouse.containsMouse || htmlMouse.pressed ? AppTheme.foreground : AppTheme.muted

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        MouseArea {
                            id: htmlMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: devPanel.mode = "html"
                        }
                    }

                    Item {
                        width: track.width / 3
                        height: track.height

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("CSS")
                            font.pixelSize: 12
                            font.weight: devPanel.mode === "css" ? Font.DemiBold : Font.Medium
                            color: devPanel.mode === "css" ? AppTheme.background : cssMouse.containsMouse || cssMouse.pressed ? AppTheme.foreground : AppTheme.muted

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        MouseArea {
                            id: cssMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: devPanel.mode = "css"
                        }
                    }

                    Item {
                        width: track.width / 3
                        height: track.height

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("JS")
                            font.pixelSize: 12
                            font.weight: devPanel.mode === "js" ? Font.DemiBold : Font.Medium
                            color: devPanel.mode === "js" ? AppTheme.background : jsMouse.containsMouse || jsMouse.pressed ? AppTheme.foreground : AppTheme.muted

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        MouseArea {
                            id: jsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: devPanel.mode = "js"
                        }
                    }
                }
            }

            // Bottom divider.
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: 1
                color: AppTheme.border
            }
        }

        // One editor per tab; only the active tab shows. While the
        // pick flow waits for files, a pick list takes this space.
        Item {
            width: parent.width
            height: parent.height - 48 - 52 - consoleBox.consoleH

            property bool picking: devPanel.doc && devPanel.doc.devScript && devPanel.doc.devScript.jsPickFlow

            ScriptEditor {
                anchors.fill: parent
                anchors.margins: 8
                visible: devPanel.mode === "html" && !parent.picking
                language: "html"
                code: devPanel.doc ? String(devPanel.doc.script.html ?? "") : ""
                onCodeChanged: devPanel.setTabCode("html", code)
            }

            ScriptEditor {
                anchors.fill: parent
                anchors.margins: 8
                visible: devPanel.mode === "css" && !parent.picking
                language: "css"
                code: devPanel.doc ? String(devPanel.doc.script.css ?? "") : ""
                onCodeChanged: devPanel.setTabCode("css", code)
            }

            ScriptEditor {
                anchors.fill: parent
                anchors.margins: 8
                visible: devPanel.mode === "js" && !parent.picking
                language: "js"
                code: devPanel.doc ? String(devPanel.doc.script.js ?? "") : ""
                onCodeChanged: devPanel.setTabCode("js", code)
            }

            // Pick flow: one row per requested file. Choosing imports
            // into the library (scripts only ever learn blob names);
            // rejecting any dialog cancels the whole run cleanly.
            ScrollView {
                anchors.fill: parent
                anchors.margins: 8
                visible: parent.picking
                clip: true

                Column {
                    width: parent.width
                    spacing: 8
                    topPadding: 4

                    Text {
                        width: parent.width
                        text: qsTr("The script needs files. Choose one per row; the run replays automatically when all are set. Cancel stops the run.")
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        color: AppTheme.muted
                    }

                    Repeater {
                        model: devPanel.pickRows()

                        RowLayout {
                            width: parent.width
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                font.pixelSize: 12
                                color: AppTheme.foreground
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 32
                                radius: AppTheme.radiusSmall
                                border.width: 1
                                border.color: AppTheme.fieldBorder
                                color: pickMouse.containsMouse ? AppTheme.hover : AppTheme.surface

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.done ? qsTr("Set") : qsTr("Choose…")
                                    font.pixelSize: 12
                                    color: modelData.done ? AppTheme.muted : AppTheme.foreground
                                }

                                MouseArea {
                                    id: pickMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !modelData.done
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: devPanel.choosePickFile(modelData.index)
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 120
                        height: 32
                        radius: AppTheme.radiusSmall
                        border.width: 1
                        border.color: AppTheme.fieldBorder
                        color: cancelPickMouse.containsMouse ? AppTheme.hover : AppTheme.surface

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Cancel run")
                            font.pixelSize: 12
                            color: AppTheme.muted
                        }

                        MouseArea {
                            id: cancelPickMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (devPanel.doc && devPanel.doc.devScript)
                                    devPanel.doc.devScript.cancelPicks();
                            }
                        }
                    }
                }
            }
        }

        // Diagnostics console: every HTML/CSS/JS error and
        // warning with its tab and line. Collapses when clean.
        Item {
            id: consoleBox

            property int consoleH: devPanel.diagnostics().length > 0 ? 104 : 0

            width: parent.width
            height: consoleBox.consoleH
            visible: consoleBox.consoleH > 0

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: 1
                color: AppTheme.border
            }

            ScrollView {
                anchors.fill: parent
                anchors.margins: 1
                clip: true

                Column {
                    width: consoleBox.width - 24
                    spacing: 2
                    topPadding: 6
                    leftPadding: 12
                    rightPadding: 12
                    bottomPadding: 6

                    Repeater {
                        model: devPanel.diagnostics()

                        TextEdit {
                            width: parent.width - 24
                            text: devPanel.diagnosticLabel(modelData)
                            font.family: "monospace"
                            font.pixelSize: 11
                            wrapMode: TextEdit.WordWrap
                            readOnly: true
                            selectByMouse: true
                            color: modelData.kind === "error" ? AppTheme.closeHover : AppTheme.muted
                        }
                    }
                }
            }
        }

        // Run bar: status line plus Run.
        Item {
            width: parent.width
            height: 52

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: 1
                color: AppTheme.border
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: devPanel.statusText()
                    font.pixelSize: 12
                    color: devPanel.statusIsError() ? AppTheme.closeHover : AppTheme.muted
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: guideBtn
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 32
                    radius: AppTheme.radiusSmall
                    border.width: 1
                    border.color: AppTheme.fieldBorder
                    color: guideMouse.containsMouse ? AppTheme.hover : AppTheme.surface

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Guide")
                        font.pixelSize: 12
                        color: AppTheme.foreground
                    }

                    MouseArea {
                        id: guideMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ScriptRunner.openGuide()
                    }
                }

                Rectangle {
                    id: runBtn
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 32
                    radius: AppTheme.radiusSmall
                    color: AppTheme.foreground
                    opacity: runBtn.enabled ? (runMouse.containsMouse ? 0.9 : 1) : 0.4

                    Text {
                        anchors.centerIn: parent
                        text: devPanel.doc && devPanel.doc.devScript && devPanel.doc.devScript.jsRunning ? qsTr("…") : qsTr("Run")
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: AppTheme.background
                    }

                    MouseArea {
                        id: runMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: runBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (devPanel.doc && devPanel.doc.devScript)
                                devPanel.doc.devScript.run();
                        }
                    }
                }
            }
        }
    }

    // Hang watchdog: the worker evaluates off-thread, so the UI stays
    // alive; after 3s without resolution this asks whether to stop the
    // script (abort) or keep waiting (re-arm). Cancel keeps waiting.
    Timer {
        id: watchdog
        interval: 3000
        repeat: false
        running: devPanel.doc && devPanel.doc.devScript && devPanel.doc.devScript.jsRunning
        onTriggered: {
            if (devPanel.doc && devPanel.doc.devScript && devPanel.doc.devScript.jsRunning)
                timeoutPopup.ask(qsTr("Script is taking too long"), qsTr("The JS tab has been running for 3 seconds. Stop it, or keep waiting?"), qsTr("Stop script"));
        }
    }

    // Pick-flow file dialogs (same suffixes/folders as the canvas
    // tools). The script only ever learns the imported blob name.
    FilePicker {
        id: pickImageFile

        suffixes: ["png", "jpg", "jpeg", "webp", "gif", "svg"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: devPanel.commitPickFile("image", selectedFile)
        onRejected: devPanel.cancelPickFile()
    }

    FilePicker {
        id: pickVideoFile

        suffixes: ["mp4", "webm", "mov", "m4v", "mkv"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.MoviesLocation)
        onAccepted: devPanel.commitPickFile("video", selectedFile)
        onRejected: devPanel.cancelPickFile()
    }

    FilePicker {
        id: pickAudioFile

        suffixes: ["mp3", "wav", "ogg", "flac"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.MusicLocation)
        onAccepted: devPanel.commitPickFile("audio", selectedFile)
        onRejected: devPanel.cancelPickFile()
    }

    ConfirmPopup {
        id: timeoutPopup

        onConfirmed: {
            if (devPanel.doc && devPanel.doc.devScript)
                devPanel.doc.devScript.abortJs();
        }
        onClosed: {
            // Dismissed (Cancel/Escape/outside) while still running:
            // give it another window before asking again.
            if (devPanel.doc && devPanel.doc.devScript && devPanel.doc.devScript.jsRunning)
                watchdog.restart();
        }
    }
}
