import QtQuick
import QtQuick.Layouts
import Totm

// Editor right panel: mode switcher on top; design shows the
// properties panel, animate shows the preset/custom switcher with
// per-mode content below. 280px, background fill, 1px left border,
// shared resize strip on the left edge.
Item {
    id: rightPanel

    property int panelWidth: 280
    readonly property int minPanelWidth: 180
    readonly property int maxPanelWidth: 480

    // Editor mode, owned by the switcher below.
    readonly property alias mode: modeSwitcher.mode
    // Animate sub-mode, owned by the animate switcher below.
    readonly property alias animateMode: animateSwitcher.mode
    // Pick flow: shape panel ("+ New Animation") borrows the gallery;
    // applying or going back clears it.
    property bool pickingPreset: false

    // Clip selection helpers for the gallery/shape/editor routing. Last
    // selected clip drives the editor; empty selection shows the shape
    // panel (shape selected) or the gallery.
    function clipSelected() {
        var d = TabState.documentFor(TabState.currentIndex);
        return !!d && d.anim.selectedClipIds.length > 0;
    }

    function shapeSelected() {
        var d = TabState.documentFor(TabState.currentIndex);
        if (!d)
            return false;
        d.rev;
        return d.selectedTops().length > 0;
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

    // Animate tab needs a shape or a clip to show anything (mirrors the
    // design panel's empty state).
    function hasAnimContext() {
        return rightPanel.shapeSelected() || rightPanel.clipSelected();
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
            height: 48
        }

        // Design properties for the selection.
        DesignPanel {
            width: parent.width
            height: parent.height - 48
            visible: modeSwitcher.mode === "design"
            doc: TabState.documentFor(TabState.currentIndex)
        }

        // Animate mode: preset/custom toggle plus per-mode content.
        Column {
            width: parent.width
            height: parent.height - 48
            visible: modeSwitcher.mode === "animate"
            spacing: 0

            AnimateModeSwitcher {
                id: animateSwitcher
                width: parent.width
                height: rightPanel.hasAnimContext() ? 48 : 0
                visible: rightPanel.hasAnimContext()
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
                visible: animateSwitcher.mode === "preset" && rightPanel.hasAnimContext() && !rightPanel.clipSelected() && (!rightPanel.shapeSelected() || rightPanel.pickingPreset) && !rightPanel.isTextSelection()
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
                visible: animateSwitcher.mode === "preset" && !rightPanel.clipSelected() && rightPanel.shapeSelected() && !rightPanel.pickingPreset
                doc: TabState.documentFor(TabState.currentIndex)
                newPolicy: () => rightPanel.pickingPreset = true
            }

            // Text preset gallery: Basic/Slide/Scale cards while picking.
            PresetGallery {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "preset" && rightPanel.hasAnimContext() && !rightPanel.clipSelected() && rightPanel.isTextSelection() && rightPanel.pickingPreset
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
            }

            // Custom gallery: grouped from-to Add list plus custom clips.
            // Path rows enter canvas draw mode through drawPolicy.
            CustomGallery {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "custom" && rightPanel.hasAnimContext() && !rightPanel.clipSelected()
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
