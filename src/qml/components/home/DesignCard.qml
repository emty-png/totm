import QtQuick
import QtQuick.Layouts
import Totm

// One design card: bordered live scene tile with a hover-revealed
// star toggle, divider, then name and edited stamp. Click selects just
// this card, Ctrl-click toggles selection, double-click opens the design,
// drag onto a sidebar workspace moves, right-click opens the card menu.
// Marquee selection draws an outline. Rename lives in the context menu
// and the F2 shortcut.
Item {
    id: card

    // Plain props with defaults (never required): Repeater delegates
    // evaluate required bindings before the model context attaches,
    // which breaks modelData reads. Same rule as LayersRow/TitleBarTab.
    property string designId: ""
    property string designName: ""
    property string updatedAt: ""
    property var scene: null
    property bool starred: false
    property bool selected: false
    property var selectedIds: []
    property bool editing: false

    property var selectOnlyPolicy: null
    property var togglePolicy: null
    property var openPolicy: null
    property var contextPolicy: null
    property var starPolicy: null
    property var commitPolicy: null
    property var cancelPolicy: null

    property bool dragMoved: false
    property real pressX: 0
    property real pressY: 0

    width: 220
    height: 188

    // Multi-drag: the whole selection travels when a selected card
    // moves, otherwise just this card.
    readonly property var dragIds: card.selected && card.selectedIds.indexOf(card.designId) >= 0 ? card.selectedIds : [card.designId]

    Drag.mimeData: {
        "application/x-totm-designs": JSON.stringify(card.dragIds)
    }
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.MoveAction

    Rectangle {
        anchors.fill: parent
        radius: AppTheme.radiusXLarge
        color: cardMouse.pressed ? AppTheme.pressed : cardMouse.containsMouse || card.Drag.active ? AppTheme.hover : AppTheme.surface
        border.width: 1
        border.color: AppTheme.border

        Behavior on color {
            ColorAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 104
            radius: AppTheme.radiusMedium
            color: AppTheme.canvas

            // Clipping happens a pixel inside so content never touches
            // the outline below.
            Item {
                anchors.fill: parent
                anchors.margins: 1
                clip: true

                DesignCardPreview {
                    anchors.fill: parent
                    scene: card.scene
                }
            }

            // Border overlay on top: children paint over their own
            // parent's border, so a square scene corner would swallow
            // the rounded outline if it lived on the base box.
            Rectangle {
                anchors.fill: parent
                radius: AppTheme.radiusMedium
                color: "transparent"
                border.width: 1
                border.color: AppTheme.border
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: AppTheme.border
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                visible: !card.editing
                text: card.designName
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            RenameField {
                id: editField

                Layout.fillWidth: true
                visible: card.editing
                initialText: card.designName
                onCommitted: text => {
                    if (card.commitPolicy)
                        card.commitPolicy(card.designId, text);
                }
                onCancelled: {
                    if (card.cancelPolicy)
                        card.cancelPolicy(card.designId);
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !card.editing
                text: card.editedLabel()
                font.pixelSize: 11
                elide: Text.ElideRight
                color: AppTheme.muted
            }
        }
    }

    // Star toggle over the preview corner. Hover-revealed only; the
    // Starred sidebar section carries the persistent starred state.
    Item {
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: 16
            topMargin: 16
        }
        width: 22
        height: 22
        z: 2
        visible: (cardMouse.containsMouse || starMouse.containsMouse) && !card.editing

        Rectangle {
            anchors.fill: parent
            radius: AppTheme.radiusSmall
            color: starMouse.containsMouse || card.starred ? AppTheme.hover : AppTheme.surface
            border.width: 1
            border.color: AppTheme.border
        }

        AppIcon {
            anchors.centerIn: parent
            width: 13
            height: 13
            kind: card.starred ? "starFill" : "star"
            iconColor: card.starred || starMouse.containsMouse ? AppTheme.foreground : AppTheme.muted

            Behavior on iconColor {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: starMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (card.starPolicy)
                    card.starPolicy(card.designId);
            }
        }
    }

    // Selected outline (marquee or click).
    Rectangle {
        anchors.fill: parent
        radius: AppTheme.radiusXLarge
        visible: card.selected
        color: "transparent"
        border.width: 1
        border.color: AppTheme.fieldBorder
    }

    MouseArea {
        id: cardMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            // Pressing anywhere settles this card's own edit first, so a
            // click never opens or menus behind a half-typed rename.
            if (card.editing)
                editField.settle();
            if (mouse.button === Qt.RightButton) {
                if (!card.selected && card.selectOnlyPolicy)
                    card.selectOnlyPolicy(card.designId);
                if (card.contextPolicy)
                    card.contextPolicy(card, mouse.x, mouse.y);
                return;
            }
            if (mouse.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) {
                if (card.togglePolicy)
                    card.togglePolicy(card.designId);
                mouse.accepted = true;
                return;
            }
            card.pressX = mouse.x;
            card.pressY = mouse.y;
            card.dragMoved = false;
            if (!card.selected && card.selectOnlyPolicy)
                card.selectOnlyPolicy(card.designId);
        }
        onPositionChanged: mouse => {
            if (pressed && !card.dragMoved && Math.hypot(mouse.x - card.pressX, mouse.y - card.pressY) > 6) {
                card.dragMoved = true;
                card.Drag.active = true;
            }
        }
        onReleased: {
            card.Drag.active = false;
        }
        onClicked: mouse => {
            if (mouse.button !== Qt.LeftButton || card.dragMoved)
                return;
            if (mouse.modifiers & (Qt.ControlModifier | Qt.MetaModifier))
                return;
            // Click only selects (single). Opening is double-click, so a
            // click never navigates away and selection stays put for the
            // shortcuts. Repeats are idempotent, no timer needed.
            if (card.selectOnlyPolicy)
                card.selectOnlyPolicy(card.designId);
        }
        onDoubleClicked: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            if (card.openPolicy)
                card.openPolicy(card.designId);
        }
    }

    function editedLabel() {
        if (!card.updatedAt)
            return qsTr("Never saved");
        var then = Date.parse(card.updatedAt);
        if (isNaN(then))
            return qsTr("Edited");
        var mins = Math.max(0, Math.round((Date.now() - then) / 60000));
        if (mins < 1)
            return qsTr("Edited just now");
        if (mins < 60)
            return qsTr("Edited %1m ago").arg(mins);
        var hours = Math.round(mins / 60);
        if (hours < 24)
            return qsTr("Edited %1h ago").arg(hours);
        var days = Math.round(hours / 24);
        if (days < 7)
            return days === 1 ? qsTr("Edited 1 day ago") : qsTr("Edited %1 days ago").arg(days);
        var d = new Date(then);
        return qsTr("Edited %1").arg(d.toLocaleDateString(Qt.locale(), "MMM d"));
    }
}
