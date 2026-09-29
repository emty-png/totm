import QtQuick
import QtQuick.Layouts
import Totm

// Editor right panel: mode switcher on top (hidden while a clip is
// being edited, so the clip editor owns the column); design shows the
// properties panel, animate shows the preset/custom switcher with
// per-mode content below. 320px, background fill, 1px left border,
// shared resize strip on the left edge.
Item {
    id: rightPanel

    property int panelWidth: 320
    readonly property int minPanelWidth: 180
    readonly property int maxPanelWidth: 480

    // Editor mode, owned by the switcher below.
    readonly property alias mode: modeSwitcher.mode
    // Animate sub-mode, owned by the animate switcher below.
    readonly property alias animateMode: animateSwitcher.mode
    // Pick flow: shape panel ("+ New Animation") borrows the gallery;
    // applying or going back clears it.
    property bool pickingPreset: false

    // Mode writes for shortcuts (mode itself stays a readonly alias).
    function setMode(m) {
        if (m === "design" || m === "animate")
            modeSwitcher.mode = m;
    }

    function toggleMode() {
        modeSwitcher.mode = modeSwitcher.mode === "design" ? "animate" : "design";
    }

    // Clip selection helpers for the gallery/shape/editor routing. Last
    // selected clip drives the editor; empty selection shows the shape
    // panel (shape selected) or the gallery.
    function clipSelected() {
        var d = TabState.documentFor(TabState.currentIndex);
        return !!d && d.anim.selectedClipIds.length > 0;
    }

    // True while the clip editor owns the column: a selected clip in
    // animate mode. Both switchers hide then (the editor's back chevron
    // is the way out); design mode keeps them so shortcuts that flip
    // modes mid-selection never strand the panel.
    function editingClip() {
        return rightPanel.clipSelected() && modeSwitcher.mode === "animate";
    }

    function shapeSelected() {
        var d = TabState.documentFor(TabState.currentIndex);
        if (!d)
            return false;
        d.rev;
        return d.selectedTops().length > 0;
    }

    // Audio selection drives the audio panel. Clip selection keeps
    // priority when both are selected (existing editor behavior wins).
    function audioSelected() {
        var d = TabState.documentFor(TabState.currentIndex);
        return !!d && d.audio.selectedAudioIds.length > 0;
    }

    // Audio panel takes the animate column (switcher hides with it).
    function audioPanel() {
        return rightPanel.audioSelected() && !rightPanel.clipSelected();
    }

    function selectedClipId() {
        var d = TabState.documentFor(TabState.currentIndex);
        if (!d || d.anim.selectedClipIds.length === 0)
            return -1;
        return d.anim.selectedClipIds[d.anim.selectedClipIds.length - 1];
    }

    // Back from the clip editor: land on the shape panel when a shape
    // is still selected, else the gallery.
    function goShapePanel() {
        rightPanel.pickingPreset = false;
        var d = TabState.documentFor(TabState.currentIndex);
        if (d)
            d.clearClipSelection();
    }

    // Motion-path draw entry from the Custom gallery (new clip).
    function startPathDraw() {
        var d = TabState.documentFor(TabState.currentIndex);
        if (!d)
            return;
        var tops = d.selectedTops();
        if (tops.length === 0)
            return;
        ToolState.startPathDraw(tops[0].uid, -1);
    }

    // Redraw an existing Path clip's points (toggles preserved).
    function redrawPathClip() {
        var d = TabState.documentFor(TabState.currentIndex);
        if (!d || d.anim.selectedClipIds.length === 0)
            return;
        var id = d.anim.selectedClipIds[d.anim.selectedClipIds.length - 1];
        var c = d.animClip(id);
        if (!c)
            return;
        ToolState.startPathDraw(c.targetUid, id);
    }

    // Animate tab needs a shape, a clip or audio to show anything
    // (mirrors the design panel's empty state).
    function hasAnimContext() {
        return rightPanel.shapeSelected() || rightPanel.clipSelected() || rightPanel.audioSelected();
    }

    // Text selections use the text preset gallery variant (Basic/Slide/
    // Scale) instead of the shape gallery.
    function isTextSelection() {
        var d = TabState.documentFor(TabState.currentIndex);
        if (!d)
            return false;
        d.rev;
        var tops = d.selectedTops();
        for (var i = 0; i < tops.length; i++) {
            if (tops[i].kind === "shape" && tops[i].shapeType === "text")
                return true;
        }
        return false;
    }

    Layout.preferredWidth: rightPanel.panelWidth
    Layout.fillHeight: true

    Behavior on Layout.preferredWidth {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    // Bare-chrome clicks steal focus (settles any open field editor),
    // like the left panel deselect area. Declared first so panels,
    // switchers and menus above win their presses.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: rightPanel.forceActiveFocus()
    }

    Rectangle {
        anchors.fill: parent
        color: AppTheme.background
    }

    Rectangle {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: AppTheme.border
    }

    Column {
        anchors.fill: parent
        spacing: 0

        EditorModeSwitcher {
            id: modeSwitcher
            width: parent.width
            // A selected clip owns the column: both switchers hide and
            // the clip editor (with its back chevron out) takes over.
            height: rightPanel.editingClip() ? 0 : 48
            visible: !rightPanel.editingClip()
        }

        // Design properties for the selection.
        DesignPanel {
            width: parent.width
            height: parent.height - modeSwitcher.height
            visible: modeSwitcher.mode === "design"
            doc: TabState.documentFor(TabState.currentIndex)
        }

        // Animate mode: preset/custom toggle plus per-mode content.
        Column {
            width: parent.width
            height: parent.height - modeSwitcher.height
            visible: modeSwitcher.mode === "animate"
            spacing: 0

            AnimateModeSwitcher {
                id: animateSwitcher
                width: parent.width
                height: rightPanel.hasAnimContext() && !rightPanel.audioPanel() && !rightPanel.editingClip() ? 48 : 0
                visible: rightPanel.hasAnimContext() && !rightPanel.audioPanel() && !rightPanel.editingClip()
            }

            // Empty selection: same nothing-here as the design panel.
            Text {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: !rightPanel.hasAnimContext()
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                leftPadding: 16
                rightPadding: 16
                text: qsTr("Nothing to see here...")
                font.pixelSize: 13
                color: AppTheme.muted
            }

            // Preset gallery: live thumbnails, click applies to selection.
            // Shown by default, or borrowed by the shape panel picker.
            // Hidden for text selections (separate gallery below).
            PresetGallery {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "preset" && rightPanel.hasAnimContext() && !rightPanel.clipSelected() && !rightPanel.audioSelected() && (!rightPanel.shapeSelected() || rightPanel.pickingPreset) && !rightPanel.isTextSelection()
                doc: TabState.documentFor(TabState.currentIndex)
                playing: visible
                showBack: rightPanel.pickingPreset
                backPolicy: () => rightPanel.pickingPreset = false
                appliedPolicy: () => rightPanel.pickingPreset = false
            }

            // Shape panel: "+ New Animation" plus this selection's clips.
            // Shared with text: clip cards are preset-agnostic.
            ShapeAnimationsPanel {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "preset" && !rightPanel.clipSelected() && !rightPanel.audioSelected() && rightPanel.shapeSelected() && !rightPanel.pickingPreset
                doc: TabState.documentFor(TabState.currentIndex)
                newPolicy: () => rightPanel.pickingPreset = true
            }

            // Text preset gallery: Basic/Slide/Scale cards while picking.
            PresetGallery {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "preset" && rightPanel.hasAnimContext() && !rightPanel.clipSelected() && !rightPanel.audioSelected() && rightPanel.isTextSelection() && rightPanel.pickingPreset
                doc: TabState.documentFor(TabState.currentIndex)
                playing: visible
                textMode: true
                showBack: rightPanel.pickingPreset
                backPolicy: () => rightPanel.pickingPreset = false
                appliedPolicy: () => rightPanel.pickingPreset = false
            }

            ClipEditor {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: rightPanel.clipSelected()
                doc: TabState.documentFor(TabState.currentIndex)
                clipId: rightPanel.selectedClipId()
                backPolicy: () => rightPanel.goShapePanel()
                redrawPolicy: () => rightPanel.redrawPathClip()
                onVisibleChanged: {
                    // Switchers hide while editing (mid-focus strand risk):
                    // drop picker state and settle focus on the panel so
                    // hidden controls never keep it.
                    if (visible) {
                        rightPanel.pickingPreset = false;
                        rightPanel.forceActiveFocus();
                    }
                }
            }

            // Audio properties: timing, volume/mute, fades and source
            // replace for the selected timeline clips.
            AudioSection {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: rightPanel.audioPanel()
                doc: TabState.documentFor(TabState.currentIndex)
            }

            // Custom gallery: grouped from-to Add list plus custom clips.
            // Path rows enter canvas draw mode through drawPolicy.
            CustomGallery {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "custom" && rightPanel.hasAnimContext() && !rightPanel.clipSelected() && !rightPanel.audioSelected()
                doc: TabState.documentFor(TabState.currentIndex)
                drawPolicy: () => rightPanel.startPathDraw()
            }
        }
    }

    // Resize strip on the left edge, shared with every panel.
    PanelResizeHandle {
        edge: "left"
        minimum: rightPanel.minPanelWidth
        maximum: rightPanel.maxPanelWidth
        size: rightPanel.panelWidth
        onResized: v => {
            rightPanel.panelWidth = v;
        }
    }
}
