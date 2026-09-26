import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Panel three-dot menu: copy/paste design properties or animation
// clips in three flavors (values, structure, both). Copy snapshots
// into TabState.propClipboard; paste applies onto the current
// selection. Rows enable only when their source exists and the
// clipboard carries a compatible payload.
Item {
    id: menu

    property var doc: null
    // "design" (fills/strokes/effects + everything) or "anim"
    // (same-preset clips across objects).
    property string scope: "design"
    // Anim scope: clip ids to copy (selected or all cards / open clip).
    property var clipIds: []
    // Anim scope: target top uids for paste (current selection).
    property var targetUids: []

    readonly property var clip: TabState.propClipboard
    readonly property bool clipMatches: !!menu.clip && menu.clip.scope === menu.scope
    readonly property bool hasValues: menu.clipMatches && !!menu.clip.payload.values
    readonly property bool hasProps: menu.clipMatches && !!menu.clip.payload.props
    readonly property bool hasClips: menu.clipMatches && !!(menu.clip.payload.clips || []).length

    readonly property bool canCopy: menu.scope === "design" ? (!!menu.doc && menu.doc.canCopyDesign()) : (!!menu.doc && menu.doc.canCopyAnimClips(menu.clipIds))
    readonly property bool hasDesignTarget: !!menu.doc && menu.doc.canPasteDesign()
    readonly property bool hasAnimTarget: !!menu.doc && menu.doc.canPasteAnimClips(menu.targetUids)
    readonly property bool canPasteValues: menu.scope === "design" ? (menu.hasValues && menu.hasDesignTarget) : (menu.hasClips && menu.hasAnimTarget)
    readonly property bool canPasteProps: menu.scope === "design" ? (menu.hasProps && menu.hasDesignTarget) : (menu.hasClips && menu.hasAnimTarget)
    readonly property bool canPasteBoth: menu.scope === "design" ? (menu.hasValues && menu.hasProps && menu.hasDesignTarget) : (menu.hasClips && menu.hasAnimTarget)

    function openNear(anchor, ax, ay) {
        popup.placeNear(anchor, ax, ay);
        popup.open();
    }

    Popup {
        id: popup

        parent: Overlay.overlay

        width: 264
        padding: 12
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

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

        background: Rectangle {
            radius: AppTheme.radiusLarge
            color: AppTheme.surface
            border.width: 1
            border.color: AppTheme.border
        }

        contentItem: ColumnLayout {
            spacing: 2

            MenuItem {
                label: qsTr("Copy properties value")
                enabled: menu.canCopy
                onClicked: {
                    menu.doCopy("values");
                    popup.close();
                }
            }
            MenuItem {
                label: qsTr("Copy properties")
                enabled: menu.canCopy
                onClicked: {
                    menu.doCopy("props");
                    popup.close();
                }
            }
            MenuItem {
                label: qsTr("Copy properties and values")
                enabled: menu.canCopy
                onClicked: {
                    menu.doCopy("both");
                    popup.close();
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 6
                Layout.bottomMargin: 6
                color: AppTheme.border
            }

            MenuItem {
                label: qsTr("Paste properties value")
                enabled: menu.canPasteValues
                onClicked: {
                    menu.doPaste("values");
                    popup.close();
                }
            }
            MenuItem {
                label: qsTr("Paste properties")
                enabled: menu.canPasteProps
                onClicked: {
                    menu.doPaste("props");
                    popup.close();
                }
            }
            MenuItem {
                label: qsTr("Paste properties and values")
                enabled: menu.canPasteBoth
                onClicked: {
                    menu.doPaste("both");
                    popup.close();
                }
            }
        }

        // Anchor-relative placement in overlay coords: below the
        // button when it fits, above otherwise, clamped with an 8px
        // margin (same rule as the entry menus).
        function placeNear(anchor, ax, ay) {
            var ov = popup.parent;
            var w = popup.width;
            var h = popup.implicitHeight > 0 ? popup.implicitHeight : 320;
            if (!anchor || !ov) {
                popup.x = 8;
                popup.y = 8;
                return;
            }
            var p = anchor.mapToItem(ov, ax, ay);
            popup.x = Math.min(Math.max(8, Math.round(p.x - w / 2)), Math.max(8, ov.width - w - 8));
            var maxY = Math.max(8, ov.height - h - 8);
            var below = Math.round(p.y + 12);
            if (below + h <= ov.height - 8)
                popup.y = below;
            else
                popup.y = Math.max(8, Math.min(Math.round(p.y - 12 - h), maxY));
        }
    }

    function doCopy(mode) {
        if (!menu.doc)
            return;
        if (menu.scope === "design")
            menu.doc.copyDesignProps(mode);
        else
            menu.doc.copyAnimClips(mode, menu.clipIds);
    }

    function doPaste(mode) {
        if (!menu.doc)
            return;
        if (menu.scope === "design")
            menu.doc.pasteDesignProps(mode);
        else
            menu.doc.pasteAnimClips(mode, menu.targetUids);
    }
}
