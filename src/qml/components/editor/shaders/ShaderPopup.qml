import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Custom shader popup: centered modal that dims the app (like
// ConfirmPopup), preview on the left and shader settings on the right.
// Presets apply directly; the vertex/fragment tabs show the reference
// source for the active preset.
Popup {
    id: popup

    property var doc: null
    property string editPresetId: "plasma"
    property string editMode: "fill"
    property var editParams: ({
            "scale": 1.0,
            "speed": 1.0,
            "opacity": 1.0
        })
    property string editVertex: ""
    property string editFragment: ""
    property string editName: ""
    property string editShaderId: ""
    // Custom source state: "preset" edits a gallery preset, "scratch" is
    // a truly blank custom shader, "import" loads plain-GLSL files.
    property string sourceTab: "preset"
    property string editFallback: ""
    property string editSourceKind: "preset"
    property string editOriginFile: ""
    property var compiledUrls: ({
            "ok": false
        })
    property string compileError: ""
    property string compileLog: ""
    property string importInfo: ""
    property string importTarget: "fragment"
    property string pendingDeleteShaderId: ""
    // Fresh blank custom state (both editors empty): neutral guidance,
    // never a red validation error.
    property bool customBlank: popup.editPresetId === "custom" && String(popup.editVertex ?? "").trim() === "" && String(popup.editFragment ?? "").trim() === ""
    property bool customValid: popup.editPresetId !== "custom" || (popup.compiledUrls.ok === true)
    property double timeSec: 0
    property bool playing: true

    signal applied

    function openFor(snapshot) {
        if (snapshot && snapshot.doc)
            popup.doc = snapshot.doc;
        var leaves = snapshot ? snapshot.selLeaves : [];
        var sid = "";
        var m = "fill";
        var p = null;
        for (var i = 0; i < leaves.length; i++) {
            var s = String(leaves[i].shaderId ?? "");
            if (s !== "") {
                sid = s;
                m = String(leaves[i].shaderMode ?? "fill");
                p = leaves[i].shaderParams;
                break;
            }
        }
        if (sid.startsWith("preset:")) {
            popup.editPresetId = sid.slice(7);
            popup.editShaderId = sid;
            popup.editParams = JSON.parse(JSON.stringify(ShaderEngine.presetDefaults(popup.editPresetId)));
            if (p)
                popup.editParams = JSON.parse(JSON.stringify(ShaderEngine.normParams(popup.editPresetId, p)));
            popup.editMode = ShaderEngine.normMode(m, popup.editPresetId);
            popup.editVertex = ShaderEngine.presetVertex(popup.editPresetId);
            popup.editFragment = ShaderEngine.presetFragment(popup.editPresetId);
            popup.editName = ShaderEngine.presetName(popup.editPresetId);
            popup.sourceTab = "preset";
            popup.editFallback = "";
            popup.editSourceKind = "preset";
            popup.editOriginFile = "";
            popup.compiledUrls = ({
                    "ok": false
                });
            popup.compileError = "";
            popup.compileLog = "";
            popup.importInfo = "";
        } else if (sid !== "") {
            var found = null;
            for (var k = 0; k < LibraryStore.shaderList.length; k++) {
                if (LibraryStore.shaderList[k].shaderId === sid)
                    found = LibraryStore.shaderList[k];
            }
            if (found) {
                var pay = found.payload ?? {};
                var base = String(pay.basePreset ?? pay.presetId ?? "plasma");
                var pid = String(pay.presetId ?? base);
                // Live custom assets (from scratch / imported) reopen in
                // the code editor with their stored sources; the fallback
                // preset is export-only and never drives the preview.
                if (pid === "custom") {
                    popup.editPresetId = "custom";
                    popup.editShaderId = sid;
                    popup.editParams = JSON.parse(JSON.stringify(ShaderEngine.normParams("custom", (pay.uniforms ?? {}))));
                    if (p) {
                        var cmerged = Object.assign({}, popup.editParams, p);
                        popup.editParams = JSON.parse(JSON.stringify(ShaderEngine.normParams("custom", cmerged)));
                    }
                    popup.editMode = ShaderEngine.normMode(m, "custom");
                    popup.editVertex = String(pay.vertex ?? "");
                    popup.editFragment = String(pay.fragment ?? "");
                    popup.editName = String(found.name ?? "");
                    popup.editFallback = String(pay.basePreset ?? "");
                    popup.editSourceKind = String(pay.sourceKind ?? "scratch");
                    popup.editOriginFile = String(pay.originFile ?? "");
                    popup.sourceTab = popup.editSourceKind === "import" ? "import" : "scratch";
                    popup.importInfo = popup.editOriginFile !== "" ? qsTr("Loaded from %1").arg(popup.editOriginFile) : "";
                    popup.refreshCompile();
                } else {
                    popup.editPresetId = base;
                    popup.editShaderId = sid;
                    popup.editParams = JSON.parse(JSON.stringify(ShaderEngine.normParams(base, (pay.uniforms ?? {}))));
                    if (p) {
                        var merged = Object.assign({}, popup.editParams, p);
                        popup.editParams = JSON.parse(JSON.stringify(ShaderEngine.normParams(base, merged)));
                    }
                    popup.editMode = ShaderEngine.normMode(m, base);
                    popup.editVertex = String(pay.vertex ?? ShaderEngine.presetVertex(base));
                    popup.editFragment = String(pay.fragment ?? ShaderEngine.presetFragment(base));
                    popup.editName = String(found.name ?? "");
                    popup.editFallback = "";
                    popup.editSourceKind = "preset";
                    popup.editOriginFile = "";
                    popup.sourceTab = "preset";
                    popup.compiledUrls = ({
                            "ok": false
                        });
                    popup.compileError = "";
                    popup.compileLog = "";
                    popup.importInfo = "";
                }
            } else {
                popup.setPreset("plasma");
            }
        } else {
            popup.setPreset("plasma");
        }
        popup.timeSec = popup.doc && popup.doc.anim ? Math.floor(Number(popup.doc.anim.currentTime || 0) * 60) / 60 : 0;
        popup.open();
    }

    anchors.centerIn: Overlay.overlay
    // Never larger than the window, so the popup can't get clipped.
    implicitWidth: Math.min(760, (Overlay.overlay ? Overlay.overlay.width : 760) - 24)
    implicitHeight: Math.min(520, (Overlay.overlay ? Overlay.overlay.height : 520) - 24)
    padding: 0
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Explicit dim layer: covers the whole window except the popup itself.
    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.6)

        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }
        }
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 0.97
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: 100
            easing.type: Easing.InCubic
        }
    }

    // ---- Small local building blocks -------------------------------------

    component SectionLabel: Text {
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: AppTheme.foreground
    }

    component CodeBox: Rectangle {
        id: box

        property alias text: area.text

        radius: AppTheme.radiusSmall
        color: AppTheme.background
        border.width: 1
        border.color: area.activeFocus ? AppTheme.foreground : AppTheme.fieldBorder
        clip: true

        ScrollView {
            anchors.fill: parent
            anchors.margins: 1

            TextArea {
                id: area

                background: null
                color: AppTheme.foreground
                font.family: "monospace"
                font.pixelSize: 11
                leftPadding: 10
                rightPadding: 10
                topPadding: 8
                bottomPadding: 8
                wrapMode: TextArea.NoWrap
                selectByMouse: true
            }
        }
    }

    component ActionButton: Rectangle {
        id: btn

        property string text: ""
        property bool primary: false

        signal clicked

        implicitWidth: btnLabel.implicitWidth + 32
        implicitHeight: 36
        radius: AppTheme.radiusSmall
        border.width: primary ? 0 : 1
        border.color: AppTheme.fieldBorder
        color: primary ? AppTheme.foreground : (btnMouse.containsMouse ? AppTheme.hover : AppTheme.surface)
        opacity: !btn.enabled ? 0.4 : (primary && btnMouse.containsMouse ? 0.9 : 1)

        Text {
            id: btnLabel

            anchors.centerIn: parent
            text: btn.text
            font.pixelSize: 12
            font.weight: btn.primary ? Font.DemiBold : Font.Normal
            color: btn.primary ? AppTheme.background : AppTheme.foreground
        }

        MouseArea {
            id: btnMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (btn.enabled)
                    btn.clicked();
            }
        }
    }

    background: Rectangle {
        radius: AppTheme.radiusLarge
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border
    }

    contentItem: RowLayout {
        spacing: 0

        // ---- Left: title + preview + timeline dock -------------------
        ColumnLayout {
            Layout.preferredWidth: 332
            Layout.fillHeight: true
            spacing: 0

            Text {
                Layout.preferredHeight: 44
                Layout.leftMargin: 16
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Shader")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: AppTheme.foreground
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 16
                Layout.topMargin: 4
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: AppTheme.radiusSmall
                    color: AppTheme.background
                    border.width: 1
                    border.color: AppTheme.fieldBorder
                    clip: true

                    // Gradient sample so the shader reads clearly
                    // against a varied backdrop.
                    Rectangle {
                        id: sampleBase

                        anchors.centerIn: parent
                        width: Math.max(80, Math.min(parent.width - 48, 240))
                        height: Math.round(width * 0.7)
                        radius: 12
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: "#e8e8e8"
                            }

                            GradientStop {
                                position: 1
                                color: "#7fa8c9"
                            }
                        }
                    }

                    ShaderOverlay {
                        anchors.fill: sampleBase
                        z: 1
                        presetId: popup.editPresetId
                        mode: popup.editMode
                        params: popup.editParams
                        timeSec: popup.timeSec
                        maskKind: "rect"
                        maskRadius: 12
                        sourceItem: sampleBase
                        customVertUrl: popup.compiledUrls.vertUrl ?? ""
                        customFragUrl: popup.compiledUrls.fragUrl ?? ""
                        customTint: String((popup.editParams ?? {}).tint ?? "#ffffff")
                        customOpacity: Number((popup.editParams ?? {}).opacity ?? 1.0)
                        customSpeed: Number((popup.editParams ?? {}).speed ?? 1.0)
                    }

                    // Blank-custom hint over the preview until the pair
                    // compiles (Apply stays gated meanwhile).
                    Text {
                        anchors.centerIn: parent
                        z: 2
                        visible: popup.editPresetId === "custom" && popup.compiledUrls.ok !== true
                        width: parent.width - 32
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: popup.customBlank ? qsTr("Blank shader — import .frag/.vert files or press Insert contract.") : (popup.compileError !== "" ? popup.compileError : qsTr("Custom shader is not compiling."))
                        font.pixelSize: 11
                        color: AppTheme.muted
                    }
                }

                // Dock pinned to the bottom of the left pane.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: AppTheme.radiusSmall
                    color: AppTheme.background
                    border.width: 1
                    border.color: AppTheme.fieldBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 14
                        spacing: 6

                        // Play / pause toggle
                        Item {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32

                            Rectangle {
                                anchors.fill: parent
                                radius: AppTheme.radiusSmall
                                color: playMouse.containsMouse ? AppTheme.hover : "transparent"
                            }

                            Canvas {
                                id: playIcon

                                property color ink: AppTheme.foreground
                                property bool isPlaying: popup.playing

                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                onInkChanged: requestPaint()
                                onIsPlayingChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    ctx.fillStyle = ink;
                                    if (isPlaying) {
                                        ctx.fillRect(2, 1, 3.5, 12);
                                        ctx.fillRect(8.5, 1, 3.5, 12);
                                    } else {
                                        ctx.beginPath();
                                        ctx.moveTo(3, 1);
                                        ctx.lineTo(12, 7);
                                        ctx.lineTo(3, 13);
                                        ctx.closePath();
                                        ctx.fill();
                                    }
                                }
                            }

                            MouseArea {
                                id: playMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popup.playing = !popup.playing
                            }
                        }

                        Slider {
                            Layout.fillWidth: true
                            from: 0
                            to: 10
                            value: popup.timeSec
                            onMoved: popup.timeSec = value
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: AppTheme.border
        }

        // ---- Right: settings -----------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.rightMargin: 12
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }

                PanelIconButton {
                    iconKind: "close"
                    filled: false
                    iconSize: 14
                    onClicked: popup.close()
                }
            }

            ScrollView {
                id: settingsScroll

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    x: 16
                    width: settingsScroll.availableWidth - 32
                    spacing: 18

                    // Source: gallery preset, blank custom shader, or
                    // plain-GLSL file import. Scratch starts truly blank
                    // (Apply/Save gate on a successful live compile).
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8

                        SectionLabel {
                            text: qsTr("Source")
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            SegmentedOption {
                                label: qsTr("Preset")
                                active: popup.sourceTab === "preset"
                                onClicked: popup.showPresetTab()
                            }
                            SegmentedOption {
                                label: qsTr("From scratch")
                                active: popup.sourceTab === "scratch"
                                onClicked: popup.newScratch()
                            }
                            SegmentedOption {
                                label: qsTr("Import")
                                active: popup.sourceTab === "import"
                                onClicked: {
                                    popup.sourceTab = "import";
                                }
                            }
                        }
                    }

                    // Preset
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: popup.sourceTab === "preset"

                        SectionLabel {
                            text: qsTr("Preset")
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            columnSpacing: 8
                            rowSpacing: 8

                            Repeater {
                                model: ShaderEngine.presetIds()

                                SegmentedOption {
                                    label: ShaderEngine.presetName(modelData)
                                    active: popup.editPresetId === modelData
                                    onClicked: popup.setPreset(modelData)
                                }
                            }
                        }
                    }

                    // Saved shaders (only when there are any)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: LibraryStore.shaderList.length > 0

                        SectionLabel {
                            text: qsTr("Saved shaders (assets)")
                        }

                        Repeater {
                            model: LibraryStore.shaderList

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                SegmentedOption {
                                    label: modelData.name
                                    active: popup.editShaderId === modelData.shaderId
                                    onClicked: {
                                        var pay = modelData.payload ?? {};
                                        if (String(pay.presetId ?? "") === "custom") {
                                            popup.editPresetId = "custom";
                                            popup.editShaderId = modelData.shaderId;
                                            popup.editParams = ShaderEngine.normParams("custom", pay.uniforms ?? {});
                                            popup.editMode = ShaderEngine.normMode("fill", "custom");
                                            popup.editVertex = String(pay.vertex ?? "");
                                            popup.editFragment = String(pay.fragment ?? "");
                                            popup.editName = String(modelData.name ?? "");
                                            popup.editFallback = String(pay.basePreset ?? "");
                                            popup.editSourceKind = String(pay.sourceKind ?? "scratch");
                                            popup.editOriginFile = String(pay.originFile ?? "");
                                            popup.sourceTab = popup.editSourceKind === "import" ? "import" : "scratch";
                                            popup.importInfo = popup.editOriginFile !== "" ? qsTr("Loaded from %1").arg(popup.editOriginFile) : "";
                                            popup.refreshCompile();
                                        } else {
                                            var base = String(pay.basePreset ?? pay.presetId ?? "plasma");
                                            popup.editPresetId = base;
                                            popup.editShaderId = modelData.shaderId;
                                            popup.editParams = ShaderEngine.normParams(base, pay.uniforms ?? {});
                                            popup.editMode = ShaderEngine.normMode("fill", base);
                                            popup.editVertex = String(pay.vertex ?? "");
                                            popup.editFragment = String(pay.fragment ?? "");
                                            popup.editName = String(modelData.name ?? "");
                                            popup.editFallback = "";
                                            popup.editSourceKind = "preset";
                                            popup.editOriginFile = "";
                                            popup.sourceTab = "preset";
                                            popup.compiledUrls = ({
                                                    "ok": false
                                                });
                                            popup.compileError = "";
                                            popup.compileLog = "";
                                            popup.importInfo = "";
                                        }
                                    }
                                }

                                PanelIconButton {
                                    iconKind: "close"
                                    filled: false
                                    iconSize: 12
                                    onClicked: popup.askDeleteShader(modelData.shaderId, String(modelData.name ?? ""))
                                }
                            }
                        }
                    }

                    // Import plain-GLSL files (.vert/.frag/.vs/.fs/.glsl).
                    // Either stage may be imported alone; the editors stay
                    // live so an import is just a starting point.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: popup.sourceTab === "import"

                        SectionLabel {
                            text: qsTr("Import shader files")
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            SegmentedOption {
                                label: qsTr("Vertex file…")
                                active: false
                                onClicked: popup.pickShaderFile("vertex")
                            }
                            SegmentedOption {
                                label: qsTr("Fragment file…")
                                active: false
                                onClicked: popup.pickShaderFile("fragment")
                            }
                        }
                    }

                    // Live contract helpers for custom shaders.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: popup.editPresetId === "custom"

                        SectionLabel {
                            text: qsTr("Live shader")
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            SegmentedOption {
                                label: qsTr("Insert contract")
                                active: false
                                onClicked: popup.insertContract()
                            }
                            SegmentedOption {
                                label: qsTr("Recompile")
                                active: false
                                onClicked: popup.refreshCompile()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            visible: popup.customBlank
                            text: qsTr("Blank shader — import .frag/.vert files above or press Insert contract to begin.")
                            font.pixelSize: 11
                            color: AppTheme.muted
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            visible: !popup.customBlank && (popup.compileError !== "" || popup.compileLog !== "")
                            text: popup.compileError !== "" ? popup.compileError : popup.compileLog
                            font.pixelSize: 11
                            color: popup.compileError !== "" ? AppTheme.closeHover : AppTheme.muted
                        }
                    }

                    // Mode
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        SectionLabel {
                            text: qsTr("Mode")
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            SegmentedOption {
                                label: qsTr("Fill")
                                active: popup.editMode === "fill"
                                onClicked: popup.editMode = "fill"
                            }
                            SegmentedOption {
                                label: qsTr("Overlay")
                                active: popup.editMode === "overlay"
                                onClicked: popup.editMode = "overlay"
                            }
                        }
                    }

                    // Parameters
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        SectionLabel {
                            Layout.bottomMargin: 2
                            text: qsTr("Parameters")
                        }

                        Repeater {
                            model: ShaderEngine.presetSchema(popup.editPresetId)

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: (modelData.type ?? "float") === "float" || (modelData.type ?? "") === "color"

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    visible: (modelData.type ?? "float") === "float"

                                    Text {
                                        Layout.preferredWidth: 64
                                        text: modelData.name.charAt(0).toUpperCase() + modelData.name.slice(1)
                                        font.pixelSize: 12
                                        color: AppTheme.muted
                                        elide: Text.ElideRight
                                    }

                                    Slider {
                                        Layout.fillWidth: true
                                        from: Number(modelData.min ?? 0)
                                        to: Number(modelData.max ?? 1)
                                        value: Number((popup.editParams ?? {})[modelData.name] ?? modelData.def ?? 0)
                                        onMoved: {
                                            var next = JSON.parse(JSON.stringify(popup.editParams ?? {}));
                                            next[modelData.name] = value;
                                            popup.editParams = next;
                                        }
                                    }

                                    Text {
                                        Layout.preferredWidth: 36
                                        horizontalAlignment: Text.AlignRight
                                        text: Number((popup.editParams ?? {})[modelData.name] ?? 0).toFixed(2)
                                        font.pixelSize: 11
                                        color: AppTheme.muted
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    visible: (modelData.type ?? "") === "color"

                                    Text {
                                        Layout.preferredWidth: 64
                                        text: modelData.name.charAt(0).toUpperCase() + modelData.name.slice(1)
                                        font.pixelSize: 12
                                        color: AppTheme.muted
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 28
                                        radius: AppTheme.radiusSmall
                                        color: String((popup.editParams ?? {})[modelData.name] ?? modelData.def ?? "#ffffff")
                                        border.width: 1
                                        border.color: AppTheme.fieldBorder
                                    }

                                    HexField {
                                        Layout.fillWidth: true
                                        value: String((popup.editParams ?? {})[modelData.name] ?? modelData.def ?? "#ffffff")
                                        onCommitted: c => {
                                            var next = JSON.parse(JSON.stringify(popup.editParams ?? {}));
                                            next[modelData.name] = c;
                                            popup.editParams = next;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Export fallback for custom shaders: the CPU exporter
                    // cannot run arbitrary GLSL, so it renders this preset
                    // instead (None keeps the base paint). Preview always
                    // shows live GLSL; PNG/video show the fallback.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: popup.editPresetId === "custom"

                        SectionLabel {
                            text: qsTr("Export fallback")
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: popup.editFallback === "" ? qsTr("Preview shows live GLSL; PNG/video export shows base paint (no fallback). SVG always shows base paint.") : qsTr("Preview shows live GLSL; PNG/video export shows %1. SVG always shows base paint.").arg(ShaderEngine.presetName(popup.editFallback))
                            font.pixelSize: 11
                            color: AppTheme.muted
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            columnSpacing: 8
                            rowSpacing: 8

                            SegmentedOption {
                                label: qsTr("None")
                                active: popup.editFallback === ""
                                onClicked: popup.editFallback = ""
                            }

                            Repeater {
                                model: ShaderEngine.presetIds()

                                SegmentedOption {
                                    label: ShaderEngine.presetName(modelData)
                                    active: popup.editFallback === modelData
                                    onClicked: popup.editFallback = modelData
                                }
                            }
                        }
                    }

                    // Vertex source: reference for presets, editable for
                    // custom shaders (edits recompile live, debounced).
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        SectionLabel {
                            text: popup.editPresetId === "custom" ? qsTr("Vertex (custom)") : qsTr("Vertex")
                        }

                        CodeBox {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110
                            text: popup.editVertex
                            onTextChanged: {
                                popup.editVertex = text;
                                popup.scheduleCompile();
                            }
                        }
                    }

                    // Fragment source: reference for presets, editable for
                    // custom shaders (edits recompile live, debounced).
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 12
                        spacing: 8

                        SectionLabel {
                            text: popup.editPresetId === "custom" ? qsTr("Fragment (custom)") : qsTr("Fragment")
                        }

                        CodeBox {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140
                            text: popup.editFragment
                            onTextChanged: {
                                popup.editFragment = text;
                                popup.scheduleCompile();
                            }
                        }
                    }
                }
            }

            // Footer: always visible, never scrolls away.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: AppTheme.border
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.topMargin: 12
                spacing: 8

                TextField {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    text: popup.editName
                    placeholderText: qsTr("Shader name")
                    placeholderTextColor: AppTheme.muted
                    color: AppTheme.foreground
                    font.pixelSize: 12
                    leftPadding: 10
                    rightPadding: 10
                    selectByMouse: true
                    onTextChanged: popup.editName = text

                    background: Rectangle {
                        radius: AppTheme.radiusSmall
                        color: AppTheme.background
                        border.width: 1
                        border.color: parent.activeFocus ? AppTheme.foreground : AppTheme.fieldBorder
                    }
                }

                ActionButton {
                    text: qsTr("Save as asset")
                    enabled: popup.customValid
                    onClicked: popup.saveAsset()
                }

                ActionButton {
                    text: qsTr("Apply")
                    primary: true
                    enabled: popup.customValid
                    onClicked: {
                        if (!popup.customValid)
                            return;
                        popup.applyToSelection();
                        popup.close();
                    }
                }
            }
        }
    }

    Timer {
        interval: 33
        repeat: true
        running: popup.opened && popup.playing
        onTriggered: popup.timeSec = (popup.timeSec + 0.033) % 10
    }

    // Debounced live recompile while typing custom sources (in-process
    // bake is ~10-100ms on miss, cached hits are instant; the debounce
    // keeps keystrokes smooth and scheduleCompile invalidates first).
    Timer {
        id: compileDebounce

        interval: 600
        repeat: false
        onTriggered: popup.refreshCompile()
    }

    FilePicker {
        id: shaderFilePicker

        suffixes: ShaderEngine.shaderFileSuffixes()
        onAccepted: popup.onShaderFilePicked(selectedFile)
    }

    ConfirmPopup {
        id: deleteConfirm

        parent: Overlay.overlay
        onConfirmed: popup.commitDeleteShader()
    }

    function scheduleCompile() {
        if (popup.editPresetId !== "custom" || !popup.opened)
            return;
        // Invalidate synchronously so Apply/Save gate on freshness,
        // not on the previous successful compile during the debounce.
        popup.compiledUrls = ({
                "ok": false
            });
        compileDebounce.restart();
    }

    function refreshCompile() {
        compileDebounce.stop();
        if (popup.editPresetId !== "custom") {
            popup.compiledUrls = ({
                    "ok": false
                });
            popup.compileError = "";
            popup.compileLog = "";
            return;
        }
        var err = ShaderEngine.validateError(popup.editVertex, popup.editFragment);
        if (err !== "") {
            popup.compiledUrls = ({
                    "ok": false
                });
            popup.compileError = err;
            popup.compileLog = "";
            return;
        }
        var contract = ShaderEngine.customContractError(popup.editVertex, popup.editFragment);
        if (contract !== "") {
            popup.compiledUrls = ({
                    "ok": false
                });
            popup.compileError = contract;
            popup.compileLog = "";
            return;
        }
        var r = ShaderEngine.compileCustom(popup.editVertex, popup.editFragment);
        popup.compiledUrls = r;
        if (r.ok === true) {
            popup.compileError = "";
            // v1 binds only uTime/uOpacity/uTint (+source/vTexCoord):
            // surface declared-but-unbound uniforms instead of rendering
            // them as silent zeros.
            var note = "";
            try {
                var found = ShaderEngine.parseUniforms(popup.editFragment);
                var extra = [];
                for (var i = 0; i < found.length; i++) {
                    var nm = String(found[i].name ?? "");
                    if (nm !== "" && nm !== "uTime" && nm !== "uOpacity" && nm !== "uTint")
                        extra.push(nm);
                }
                if (extra.length > 0)
                    note = qsTr("Note: %1 declared but not bound (v1 binds uTime/uOpacity/uTint only).").arg(extra.join(", "));
            } catch (e) {}
            var baseLog = String(r.log ?? "");
            popup.compileLog = (note !== "" && baseLog !== "") ? (note + "\n" + baseLog) : (note !== "" ? note : baseLog);
        } else {
            popup.compileError = String(r.error ?? qsTr("Shader failed to compile."));
            popup.compileLog = String(r.log ?? "");
        }
    }

    function showPresetTab() {
        popup.sourceTab = "preset";
        if (popup.editPresetId === "custom")
            popup.setPreset("plasma");
    }

    function newScratch() {
        popup.sourceTab = "scratch";
        popup.editPresetId = "custom";
        popup.editShaderId = "";
        popup.editParams = JSON.parse(JSON.stringify(ShaderEngine.customDefaults()));
        popup.editMode = "fill";
        popup.editVertex = "";
        popup.editFragment = "";
        popup.editName = qsTr("Untitled shader");
        popup.editFallback = "";
        popup.editSourceKind = "scratch";
        popup.editOriginFile = "";
        popup.importInfo = "";
        popup.refreshCompile();
    }

    function insertContract() {
        if (popup.editPresetId !== "custom")
            popup.newScratch();
        popup.editVertex = ShaderEngine.customTemplateVertex();
        popup.editFragment = ShaderEngine.customTemplateFragment();
        popup.editSourceKind = popup.editSourceKind === "import" ? "import" : "scratch";
        popup.refreshCompile();
    }

    function pickShaderFile(target) {
        popup.importTarget = target === "vertex" ? "vertex" : "fragment";
        if (popup.editPresetId !== "custom") {
            popup.editPresetId = "custom";
            popup.editShaderId = "";
            popup.editParams = JSON.parse(JSON.stringify(ShaderEngine.customDefaults()));
            popup.editMode = "fill";
            popup.editVertex = "";
            popup.editFragment = "";
            popup.editName = qsTr("Imported shader");
            popup.editFallback = "";
            popup.editSourceKind = "import";
        }
        popup.sourceTab = "import";
        shaderFilePicker.open();
    }

    function onShaderFilePicked(url) {
        var r = ShaderEngine.readShaderFile(url);
        if (r.ok !== true) {
            popup.importInfo = String(r.error ?? qsTr("Could not read the shader file."));
            return;
        }
        var text = String(r.text ?? "");
        var name = String(r.fileName ?? "");
        if (popup.importTarget === "vertex")
            popup.editVertex = text;
        else
            popup.editFragment = text;
        // Single-file import just works: backfill the untouched stage
        // with the contract template (the vertex is boilerplate in
        // practice). Only blank stages are touched, never user code.
        var filledNote = "";
        if (String(popup.editVertex ?? "").trim() === "") {
            popup.editVertex = ShaderEngine.customTemplateVertex();
            filledNote = qsTr(" Empty vertex filled with the contract template.");
        } else if (String(popup.editFragment ?? "").trim() === "") {
            popup.editFragment = ShaderEngine.customTemplateFragment();
            filledNote = qsTr(" Empty fragment filled with the contract template.");
        }
        popup.editSourceKind = "import";
        popup.editOriginFile = name;
        if (String(popup.editName || "") === "" || popup.editName === qsTr("Untitled shader"))
            popup.editName = name.replace(/\.[^.]*$/, "");
        popup.importInfo = qsTr("Loaded %1 (%2 bytes).%3").arg(name).arg(Number(r.size ?? text.length)).arg(filledNote);
        popup.refreshCompile();
    }

    function askDeleteShader(id, name) {
        popup.pendingDeleteShaderId = String(id ?? "");
        if (popup.pendingDeleteShaderId === "")
            return;
        deleteConfirm.ask(qsTr("Delete shader?"), qsTr("“%1” will be removed from your library. Nodes using it fall back to Plasma.").arg(name), qsTr("Delete"));
    }

    function commitDeleteShader() {
        var id = popup.pendingDeleteShaderId;
        popup.pendingDeleteShaderId = "";
        if (id === "")
            return;
        // Retarget current-doc nodes explicitly so delete is undoable
        // and matches the confirm copy (fallback to Plasma).
        var d = popup.doc;
        if (d) {
            d.history.checkpoint();
            var leaves = d.styleTargets();
            var plasmaDef = ShaderEngine.presetDefaults("plasma");
            for (var i = 0; i < leaves.length; i++) {
                if (String(leaves[i].shaderId ?? "") === id) {
                    leaves[i].shaderId = "preset:plasma";
                    leaves[i].shaderMode = ShaderEngine.presetMode("plasma");
                    leaves[i].shaderParams = JSON.parse(JSON.stringify(plasmaDef));
                }
            }
            d.touch();
        }
        LibraryStore.deleteShader(id);
        if (popup.editShaderId === id)
            popup.editShaderId = "";
    }

    function saveAsset() {
        if (!popup.customValid)
            return null;
        var err = ShaderEngine.validateError(popup.editVertex, popup.editFragment);
        if (err !== "") {
            return null;
        }
        var isCustom = popup.editPresetId === "custom";
        if (isCustom) {
            var contract = ShaderEngine.customContractError(popup.editVertex, popup.editFragment);
            if (contract !== "")
                return null;
        }
        var payload = {
            presetId: popup.editPresetId,
            basePreset: isCustom ? popup.editFallback : popup.editPresetId,
            vertex: popup.editVertex,
            fragment: popup.editFragment,
            uniforms: JSON.parse(JSON.stringify(popup.editParams ?? {}))
        };
        if (isCustom) {
            payload.sourceKind = popup.editSourceKind === "import" ? "import" : "scratch";
            payload.originFile = String(popup.editOriginFile ?? "");
        }
        var name = String(popup.editName || "").trim();
        if (name === "")
            name = ShaderEngine.presetName(popup.editPresetId);
        // Custom edits always fork a new asset revision: nodes holding
        // the previous revision keep rendering while this one compiles.
        var id = LibraryStore.createShader(name, payload);
        if (id !== "") {
            popup.editShaderId = id;
            if (isCustom)
                popup.editSourceKind = String(payload.sourceKind);
        }
        return id;
    }

    function applyToSelection() {
        var d = popup.doc;
        if (!d)
            return;
        // Unsaved custom sources have no node payload to point at
        // ("preset:custom" carries no GLSL), so fork an asset first.
        // Edited custom assets also fork when sources differ: nodes
        // reference asset sources, so applying without forking would
        // point them at the old revision while the popup previews new.
        if (popup.editPresetId === "custom") {
            if (!popup.customValid)
                return;
            if (popup.editShaderId === "") {
                var freshId = popup.saveAsset();
                if (!freshId)
                    return;
            } else {
                var stored = null;
                for (var s = 0; s < LibraryStore.shaderList.length; s++) {
                    if (LibraryStore.shaderList[s].shaderId === popup.editShaderId) {
                        stored = LibraryStore.shaderList[s].payload ?? {};
                        break;
                    }
                }
                if (stored) {
                    var dirty = String(stored.vertex ?? "") !== String(popup.editVertex ?? "") || String(stored.fragment ?? "") !== String(popup.editFragment ?? "") || String(stored.basePreset ?? "") !== String(popup.editFallback ?? "");
                    if (dirty) {
                        var forkId = popup.saveAsset();
                        if (!forkId)
                            return;
                    }
                } else {
                    var missingId = popup.saveAsset();
                    if (!missingId)
                        return;
                }
            }
        }
        d.history.checkpoint();
        var leaves = d.styleTargets();
        var norm = ShaderEngine.normParams(popup.editPresetId, popup.editParams ?? {});
        for (var i = 0; i < leaves.length; i++) {
            if (d.isEffectivelyLocked(leaves[i]))
                continue;
            var t = leaves[i].shapeType ?? "";
            var isBool = leaves[i].kind === "group" && leaves[i].boolOp !== undefined && leaves[i].boolOp !== "none";
            if (!isBool && !ShaderEngine.isShaderableType(t))
                continue;
            leaves[i].shaderId = popup.editShaderId !== "" ? popup.editShaderId : ("preset:" + popup.editPresetId);
            leaves[i].shaderMode = (popup.editMode === "overlay") ? "overlay" : "fill";
            leaves[i].shaderParams = JSON.parse(JSON.stringify(norm));
        }
        d.touch();
        popup.applied();
    }

    function setPreset(pid) {
        popup.sourceTab = "preset";
        popup.editPresetId = pid;
        popup.editShaderId = "preset:" + pid;
        popup.editParams = JSON.parse(JSON.stringify(ShaderEngine.presetDefaults(pid)));
        popup.editMode = ShaderEngine.presetMode(pid);
        popup.editVertex = ShaderEngine.presetVertex(pid);
        popup.editFragment = ShaderEngine.presetFragment(pid);
        popup.editName = ShaderEngine.presetName(pid);
        popup.editFallback = "";
        popup.editSourceKind = "preset";
        popup.editOriginFile = "";
        popup.compiledUrls = ({
                "ok": false
            });
        popup.compileError = "";
        popup.compileLog = "";
        popup.importInfo = "";
    }
}
