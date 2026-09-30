import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Clip options editor shell: header (back plus preset name), Mode
// section (presets only; customs carry explicit from-to), per-preset
// and per-custom option sections, timing, keyframes, then the clip
// clipboard. Back routes
// through backPolicy (shape panel) with a clear-selection fallback.
// Path redraw routes through redrawPolicy (canvas draw mode).
ScrollView {
    id: editor

    required property var doc
    required property int clipId

    property var backPolicy: null
    property var redrawPolicy: null

    readonly property var clipData: {
        if (!editor.doc)
            return null;
        editor.doc.anim.clipRev;
        return editor.doc.animClip(editor.clipId);
    }
    readonly property bool isCustom: !!editor.clipData && !!editor.doc && editor.doc.anim.presets.isCustom(editor.clipData.preset)

    contentWidth: availableWidth
    clip: true
    onVisibleChanged: {
        if (!editor.visible)
            graphPopup.close();
    }

    Column {
        width: editor.availableWidth
        spacing: 0

        // Header: back to gallery, preset name plus span, graph editor.
        RowLayout {
            width: parent.width
            height: 48
            spacing: 4

            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.leftMargin: 4

                AppIcon {
                    anchors.centerIn: parent
                    kind: "caret"
                    rotation: 90
                    width: 14
                    height: 14
                    iconColor: backMouse.containsMouse || backMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: backMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (editor.backPolicy)
                            editor.backPolicy();
                        else if (editor.doc)
                            editor.doc.clearClipSelection();
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                verticalAlignment: Text.AlignVCenter
                text: editor.presetTitle()
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            PanelIconButton {
                id: dotsBtn

                iconKind: "dots"
                filled: false
                iconSize: 12
                enabled: !!editor.doc
                onClicked: copyMenu.openNear(dotsBtn, dotsBtn.width / 2, dotsBtn.height / 2)
            }

            PanelIconButton {
                Layout.rightMargin: 4
                iconKind: "close"
                filled: false
                iconSize: 12
                onClicked: editor.deleteClip()
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: AppTheme.border
        }

        PanelSection {
            width: parent.width
            title: qsTr("Mode")
            visible: !editor.isCustom

            RowLayout {
                spacing: 8

                SegmentedOption {
                    label: qsTr("In")
                    active: !!editor.clipData && editor.clipData.mode === "in"
                    onClicked: editor.setMode("in")
                }

                SegmentedOption {
                    label: qsTr("Out")
                    active: !!editor.clipData && editor.clipData.mode === "out"
                    onClicked: editor.setMode("out")
                }
            }
        }

        // Slide / Move & Scale options.
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "slide" || editor.clipData.preset === "movescale")

            ClipSlideOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Spin / Twist options.
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "spin" || editor.clipData.preset === "twist")

            ClipSpinOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Grow / Shrink options (sized end of the gesture).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "grow" || editor.clipData.preset === "shrink")

            ClipGrowOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Typewriter options (reveal unit, speed, cursor).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && editor.clipData.preset === "type"

            ClipTextOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Custom Transform (scale / rotate / move).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "customScale" || editor.clipData.preset === "customRotate" || editor.clipData.preset === "customMove" || editor.clipData.preset === "customFontSize" || editor.clipData.preset === "customFontWeight")

            ClipCustomTransformOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Custom Style (opacity / color).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "customOpacity" || editor.clipData.preset === "customColor" || editor.clipData.preset === "customStrokeColor")

            ClipCustomStyleOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Custom Gradient (fill-gradient stops + angle, or
        // stroke-gradient for the stroke variant).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "customGradient" || editor.clipData.preset === "customStrokeGradient")

            ClipCustomGradientOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
                gradientKind: !!editor.clipData && editor.clipData.preset === "customStrokeGradient" ? "stroke" : "fill"
            }
        }

        // Custom Other (hide / resize / corner / stroke).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "customHide" || editor.clipData.preset === "customResize" || editor.clipData.preset === "customCorner" || editor.clipData.preset === "customStroke" || editor.clipData.preset === "customFlip")

            ClipCustomOtherOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Custom Shadow (outer-shadow color / offsets / blur / spread).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && editor.clipData.preset === "customShadow"

            ClipCustomShadowOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Custom Blurs (radius + opacity from-to, layer vs background).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "customLayerBlur" || editor.clipData.preset === "customBackgroundBlur")

            ClipCustomBlurOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
                blurKind: !!editor.clipData && editor.clipData.preset === "customBackgroundBlur" ? "backgroundBlur" : "layerBlur"
            }
        }

        // Custom Glow (color / blur / spread from-to plus inner toggle).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && editor.clipData.preset === "customGlow"

            ClipCustomGlowOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Custom Grain (amount + size from-to; seed follows the clock).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && editor.clipData.preset === "customGrain"

            ClipCustomGrainOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Motion path (closed / orient / redraw).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && editor.clipData.preset === "customPath"

            ClipPathOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
                redrawPolicy: () => editor.redrawPath()
            }
        }

        // Mask wipe / iris (direction, feather, invert, keyframes).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "maskWipe" || editor.clipData.preset === "maskIris")

            ClipMaskOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Timing and easing. Collapses entirely for instant hide/show
        // (customHide with fade off), whose hidden rows would otherwise
        // leave a titled but empty gap.
        PanelSection {
            width: parent.width
            title: qsTr("Animation")
            visible: !timingOpts.isInstantHide()

            ClipTimingOptions {
                id: timingOpts

                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
                graphPolicy: () => graphPopup.open()
            }
        }

        // Keyframes (header add button captures the live look at the
        // playhead). One key stores, two or more drive multi-stop
        // motion with per-key easing. From-to stays as the fallback.
        PanelSection {
            width: parent.width
            title: qsTr("Keyframes")
            visible: !!editor.clipData && !!editor.doc && editor.doc.anim.presets.isKeyframeable(editor.clipData.preset)
            showAdd: true
            onAddClicked: clipKeys.addKey()

            ClipKeys {
                id: clipKeys

                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
                graphKeyPolicy: keyIndex => editor.openKeyGraph(keyIndex)
            }
        }

        // Clip clipboard: duplicate plus app-wide copy/paste. Lives
        // below Keyframes so capture controls sit closest to the keys.
        PanelSection {
            width: parent.width
            title: qsTr("Clip")

            ColumnLayout {
                spacing: 8

                // Copies this clip to the playhead (one undo entry, copy selected).
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: AppTheme.radiusSmall
                    color: dupMouse.containsMouse || dupMouse.pressed ? AppTheme.hover : AppTheme.surface
                    border.width: 1
                    border.color: AppTheme.fieldBorder

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Duplicate clip")
                        font.pixelSize: 12
                        color: AppTheme.foreground
                    }

                    MouseArea {
                        id: dupMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: editor.duplicateClip()
                    }
                }

                // Cross-shape/design copy: templates live app-wide in
                // TabState.animClipboard (same store the shortcuts use),
                // paste re-anchors earliest at the playhead onto the
                // selected tops.
                RowLayout {
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: AppTheme.radiusSmall
                        border.width: 1
                        border.color: AppTheme.fieldBorder
                        color: copyMouse.containsMouse || copyMouse.pressed ? AppTheme.hover : AppTheme.surface
                        opacity: editor.clipData !== null ? 1 : 0.4

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Copy clip")
                            font.pixelSize: 12
                            color: AppTheme.foreground
                        }

                        MouseArea {
                            id: copyMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: editor.clipData !== null ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: editor.copyClip()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: AppTheme.radiusSmall
                        border.width: 1
                        border.color: AppTheme.fieldBorder
                        color: pasteMouse.containsMouse || pasteMouse.pressed ? AppTheme.hover : AppTheme.surface
                        opacity: editor.canPasteClips() ? 1 : 0.4

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Paste clips")
                            font.pixelSize: 12
                            color: AppTheme.foreground
                        }

                        MouseArea {
                            id: pasteMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: editor.canPasteClips() ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: editor.pasteClips()
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 12
        }

        PropCopyMenu {
            id: copyMenu

            doc: editor.doc
            scope: "anim"
            clipIds: [editor.clipId]
            targetUids: editor.targetTopUids()
        }
    }

    GraphEditorPopup {
        id: graphPopup

        doc: editor.doc
        clipId: editor.clipId
    }

    function duplicateClip() {
        if (editor.doc)
            editor.doc.duplicateClips([editor.clipId]);
    }

    function canPasteClips() {
        if (!editor.doc)
            return false;
        editor.doc.rev;
        return TabState.animClipboard.length > 0 && editor.doc.selectedTops().length > 0;
    }

    function copyClip() {
        if (editor.doc && editor.clipData)
            TabState.animClipboard = editor.doc.copyClips([editor.clipId]);
    }

    function pasteClips() {
        if (!editor.doc || !editor.canPasteClips())
            return;
        var tops = editor.doc.selectedTops();
        var uids = [];
        for (var i = 0; i < tops.length; i++)
            uids.push(tops[i].uid);
        editor.doc.pasteClips(TabState.animClipboard, uids);
    }

    function presetTitle() {
        if (!editor.clipData || !editor.doc)
            return "";
        return editor.doc.anim.presets.presetName(editor.clipData.preset) + editor.doc.anim.presets.entrySuffix(editor.clipData.preset, editor.clipData.options);
    }

    function targetTopUids() {
        if (!editor.doc)
            return [];
        editor.doc.rev;
        var out = [];
        var tops = editor.doc.selectedTops();
        for (var i = 0; i < tops.length; i++)
            out.push(tops[i].uid);
        return out;
    }

    function setMode(mode) {
        if (editor.doc)
            editor.doc.setClipMode(editor.clipId, mode);
    }

    // Delete the open clip (plus any other selected clips, like shape
    // delete removes the whole selection). deleteSelectedClips filters
    // the selection, so the editor hides on its own once its clip is
    // gone; no back navigation needed.
    function deleteClip() {
        if (!editor.doc)
            return;
        if (editor.doc.anim.isClipSelected(editor.clipId))
            editor.doc.deleteSelectedClips();
        else
            editor.doc.deleteClips([editor.clipId]);
    }

    // Segment popup: the shared Animation-type editor scoped to one
    // stored key (dropdown picks and handle drags land on its easing).
    function openKeyGraph(keyIndex) {
        graphPopup.keyIndex = keyIndex;
        graphPopup.open();
    }

    function redrawPath() {
        if (editor.redrawPolicy)
            editor.redrawPolicy();
        else if (editor.doc)
            editor.doc.clearClipSelection();
    }
}
