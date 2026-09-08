import QtQuick
import QtQuick.Layouts
import Totm

// Editor right panel. Holds the mode switcher; design shows the
// properties panel, animate shows the preset/custom switcher with
// per-mode content below.
// Matches web `.editor-right-sidebar`: 280px, background fill, 1px left
// border, 6px resize handle on the left edge.
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
        var d = TabStore.documentFor(TabStore.currentIndex);
        return !!d && d.anim.selectedClipIds.length > 0;
    }

    function shapeSelected() {
        var d = TabStore.documentFor(TabStore.currentIndex);
        if (!d)
            return false;
        d.rev;
        return d.selectedTops().length > 0;
    }

    function selectedClipId() {
        var d = TabStore.documentFor(TabStore.currentIndex);
        if (!d || d.anim.selectedClipIds.length === 0)
            return -1;
        return d.anim.selectedClipIds[d.anim.selectedClipIds.length - 1];
    }

    // Back from the clip editor: land on the shape panel when a shape
    // is still selected, else the gallery.
    function goShapePanel() {
        rightPanel.pickingPreset = false;
        var d = TabStore.documentFor(TabStore.currentIndex);
        if (d)
            d.clearClipSelection();
    }

    // Animate tab needs a shape or a clip to show anything (mirrors the
    // design panel's empty state).
    function hasAnimContext() {
        return rightPanel.shapeSelected() || rightPanel.clipSelected();
    }

    // Text has no animation presets yet: any text in the selection parks
    // the animate UI on a coming-soon note instead of the gallery.
    function isTextSelection() {
        var d = TabStore.documentFor(TabStore.currentIndex);
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
            doc: TabStore.documentFor(TabStore.currentIndex)
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
            // Text selections park on coming-soon (no text presets yet).
            PresetGallery {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "preset" && rightPanel.hasAnimContext() && !rightPanel.clipSelected() && (!rightPanel.shapeSelected() || rightPanel.pickingPreset) && !rightPanel.isTextSelection()
                doc: TabStore.documentFor(TabStore.currentIndex)
                playing: visible
                showBack: rightPanel.pickingPreset
                backPolicy: () => rightPanel.pickingPreset = false
                appliedPolicy: () => rightPanel.pickingPreset = false
            }

            // Shape panel: "+ New Animation" plus this selection's clips.
            // Shared with text: clip cards are preset-agnostic.
            ShapeAnimsPanel {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "preset" && !rightPanel.clipSelected() && rightPanel.shapeSelected() && !rightPanel.pickingPreset
                doc: TabStore.documentFor(TabStore.currentIndex)
                newPolicy: () => rightPanel.pickingPreset = true
            }

            // Text preset gallery: Basic/Slide/Scale cards. Mirrors the
            // shape flow (panel first, gallery while picking).
            PresetGallery {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "preset" && rightPanel.hasAnimContext() && !rightPanel.clipSelected() && rightPanel.isTextSelection() && rightPanel.pickingPreset
                doc: TabStore.documentFor(TabStore.currentIndex)
                playing: visible
                textMode: true
                showBack: rightPanel.pickingPreset
                backPolicy: () => rightPanel.pickingPreset = false
                appliedPolicy: () => rightPanel.pickingPreset = false
            }

            ClipEditor {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "preset" && rightPanel.clipSelected()
                doc: TabStore.documentFor(TabStore.currentIndex)
                clipId: rightPanel.selectedClipId()
                backPolicy: () => rightPanel.goShapePanel()
            }

            // Custom keyframes live here; empty for now.
            Text {
                width: parent.width
                height: parent.height - animateSwitcher.height
                visible: animateSwitcher.mode === "custom" && rightPanel.hasAnimContext()
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                leftPadding: 16
                rightPadding: 16
                text: qsTr("Nothing to see here...")
                font.pixelSize: 13
                color: AppTheme.muted
            }
        }
    }

    // Resize handle straddling the left edge, like web `.resize-handle`.
    MouseArea {
        id: handle
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            leftMargin: -3
        }
        width: 6
        cursorShape: Qt.SplitHCursor
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true

        property real startX: 0
        property real startW: 280

        Rectangle {
            anchors.fill: parent
            color: handle.containsMouse || handle.pressed ? AppTheme.border : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }

        onPressed: mouse => {
            // Window-stable coordinates: the handle moves with the panel,
            // so measuring in handle space would feed back and judder.
            handle.startX = handle.mapToGlobal(mouse.x, mouse.y).x;
            handle.startW = rightPanel.panelWidth;
        }
        onPositionChanged: mouse => {
            if (!handle.pressed)
                return;
            var globalX = handle.mapToGlobal(mouse.x, mouse.y).x;
            rightPanel.panelWidth = Math.min(rightPanel.maxPanelWidth, Math.max(rightPanel.minPanelWidth, handle.startW - (globalX - handle.startX)));
        }
    }
}
