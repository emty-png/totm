import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Vertical document tab: full-width row, fixed 40px height. Mirrors
// TitleBarTab hover/active language; dividers run along the bottom.
// Draggable on Y: the bar drives gapShift (siblings slide, animated)
// and dragOffset (dragged tab follows, unanimated) through
// press/move/release policies; a moved press never clicks.
// Collapsed mode shows the title initial with a tooltip and keeps
// middle-click close; the inline close zone only shows expanded.
Rectangle {
    id: docTab

    property string title: "Untitled"
    property bool active: false
    property bool collapsed: false
    // Rail side for the active blend strip ("left" puts it on the row's
    // right edge, "right" on the left edge).
    property string side: "left"
    property real gapShift: 0
    property real dragOffset: 0
    property bool animateGap: true
    property bool animateFollow: true

    property var pressPolicy: null
    property var movePolicy: null
    property var releasePolicy: null

    signal clicked
    signal closeRequested

    Layout.fillWidth: true
    Layout.preferredHeight: 40
    implicitHeight: 40
    transform: Translate {
        y: docTab.gapShift + docTab.dragOffset
    }
    z: docTab.dragOffset !== 0 ? 10 : 0

    Behavior on gapShift {
        enabled: docTab.animateGap
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Behavior on dragOffset {
        enabled: docTab.animateFollow
        NumberAnimation {
            duration: 30
            easing.type: Easing.Linear
        }
    }
    color: docTab.active ? AppTheme.background : mouse.pressed || closeBtn.hovered ? AppTheme.pressed : mouse.containsMouse || closeBtn.hovered ? AppTheme.hover : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    // Active indicator: 2px accent on the outer edge is painted by the
    // rail; here the row just blends into the content background.
    Text {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: docTab.collapsed ? 12 : 40
        }
        horizontalAlignment: docTab.collapsed ? Text.AlignHCenter : Text.AlignLeft
        elide: Text.ElideRight
        text: docTab.collapsed ? (docTab.title.length > 0 ? docTab.title.charAt(0).toUpperCase() : "?") : docTab.title
        font.pixelSize: docTab.collapsed ? 14 : 12
        font.weight: docTab.collapsed ? Font.DemiBold : Font.Normal
        color: docTab.active || mouse.containsMouse || mouse.pressed || closeBtn.hovered ? AppTheme.foreground : AppTheme.muted

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
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

    // Active blend strip: 1px of content background over the rail's
    // outer-border segment, so the active row melts into the content
    // like the top bar's bottom-border cover. It rides inside the row,
    // so it tracks scrolling with zero math (and scrolls away with an
    // off-screen active row, correctly showing no cover).
    Rectangle {
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        x: docTab.side === "left" ? docTab.width - 1 : 0
        width: 1
        visible: docTab.active
        color: AppTheme.background
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        property real pressY: 0
        property bool armed: false
        property bool moved: false

        onPressed: event => {
            mouse.pressY = event.y;
            mouse.armed = event.button === Qt.LeftButton;
            mouse.moved = false;
            if (mouse.armed && docTab.pressPolicy)
                docTab.pressPolicy(event.x, event.y);
        }
        onPositionChanged: event => {
            if (!pressed || !mouse.armed)
                return;
            if (!mouse.moved && Math.abs(event.y - mouse.pressY) > 6)
                mouse.moved = true;
            if (mouse.moved && docTab.movePolicy)
                docTab.movePolicy(event.y - mouse.pressY);
        }
        onReleased: event => {
            mouse.armed = false;
            if (docTab.releasePolicy)
                docTab.releasePolicy();
        }
        onClicked: event => {
            if (mouse.moved) {
                mouse.moved = false;
                return;
            }
            if (event.button === Qt.MiddleButton)
                docTab.closeRequested();
            else
                docTab.clicked();
        }
    }

    ToolTip.visible: docTab.collapsed && mouse.containsMouse
    ToolTip.text: docTab.title
    ToolTip.delay: 500

    // Close zone: revealed when active or hovered, expanded only.
    // Declared after the tab MouseArea so it stays on top of it.
    Item {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 36
        visible: !docTab.collapsed && opacity > 0
        opacity: (docTab.active || mouse.containsMouse || closeBtn.hovered) ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        TitleBarButton {
            id: closeBtn
            anchors.fill: parent
            iconKind: "close"
            onClicked: docTab.closeRequested()
        }
    }
}
