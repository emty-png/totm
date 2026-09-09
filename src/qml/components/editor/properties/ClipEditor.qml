import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Clip options editor shell: header (back plus preset name), Mode
// section (presets only; customs carry explicit from-to), per-preset
// and per-custom option sections plus the timing section. Back routes
// through backPolicy (shape panel) with a clear-selection fallback.
// Path redraw routes through redrawPolicy (canvas draw mode).
ScrollView {
    id: editor

    required property var doc
    required property int clipId

    property var backPolicy: null
    property var redrawPolicy: null

    readonly property var clipData: editor.doc ? editor.doc.animClip(editor.clipId) : null
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

                SegOption {
                    label: qsTr("In")
                    active: !!editor.clipData && editor.clipData.mode === "in"
                    onClicked: editor.setMode("in")
                }

                SegOption {
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

        // Custom Transform (scale / rotate / move).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "customScale" || editor.clipData.preset === "customRotate" || editor.clipData.preset === "customMove")

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
            visible: !!editor.clipData && (editor.clipData.preset === "customOpacity" || editor.clipData.preset === "customColor")

            ClipCustomStyleOptions {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
            }
        }

        // Custom Other (hide / resize / corner / stroke).
        PanelSection {
            width: parent.width
            title: editor.presetTitle()
            visible: !!editor.clipData && (editor.clipData.preset === "customHide" || editor.clipData.preset === "customResize" || editor.clipData.preset === "customCorner" || editor.clipData.preset === "customStroke")

            ClipCustomOtherOptions {
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

        // Timing and easing.
        PanelSection {
            width: parent.width
            title: qsTr("Animation")

            ClipTimingSection {
                Layout.fillWidth: true
                doc: editor.doc
                clipId: editor.clipId
                graphPolicy: () => graphPopup.open()
            }
        }

        Item {
            width: parent.width
            height: 12
        }
    }

    GraphEditorPopup {
        id: graphPopup

        doc: editor.doc
        clipId: editor.clipId
    }

    function presetTitle() {
        if (!editor.clipData || !editor.doc)
            return "";
        return editor.doc.anim.presets.presetName(editor.clipData.preset);
    }

    function setMode(mode) {
        if (editor.doc)
            editor.doc.setClipMode(editor.clipId, mode);
    }

    function redrawPath() {
        if (editor.redrawPolicy)
            editor.redrawPolicy();
        else if (editor.doc)
            editor.doc.clearClipSelection();
    }
}
