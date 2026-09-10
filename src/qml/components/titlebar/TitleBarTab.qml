import QtQuick
import QtQuick.Layouts
import Totm

// Document tab: 4x the 46px home tab = 184px. Same hover behavior as
// the window-control buttons; no hover feedback while active.
// Draggable: the bar drives gapShift (siblings slide, animated) and
// dragOffset (the dragged tab follows the cursor, unanimated) through
// press/move/release policies; a moved press never clicks.
Rectangle {
    id: docTab

    property string title: "Untitled"
    property bool active: false
    property real gapShift: 0
    property real dragOffset: 0
    // Animation gates: drop commits stage instant offsets with the gates
    // off, then animate home. The follow gate stays on during drags: a
    // short linear trail absorbs +-1px event noise that otherwise reads
    // as horizontal jitter (integer snapping only makes it flip-flop).
    property bool animateGap: true
    property bool animateFollow: true

    property var pressPolicy: null
    property var movePolicy: null
    property var releasePolicy: null

    signal clicked
    signal closeRequested

    Layout.preferredWidth: 184
    Layout.fillHeight: true
    // No scaling while dragging: fractional scales make the tab title
    // shimmer as it slides. The z-lift alone carries the dragged look.
    transform: Translate {
        x: docTab.gapShift + docTab.dragOffset
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

    Text {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: 52
        }
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: docTab.title
        font.pixelSize: 12
        color: docTab.active || mouse.containsMouse || mouse.pressed || closeBtn.hovered ? AppTheme.foreground : AppTheme.muted

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    // Right divider.
    Rectangle {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: AppTheme.border
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        property real pressX: 0
        property bool armed: false
        property bool moved: false

        onPressed: event => {
            mouse.pressX = event.x;
            mouse.armed = event.button === Qt.LeftButton;
            mouse.moved = false;
            if (mouse.armed && docTab.pressPolicy)
                docTab.pressPolicy(event.x, event.y);
        }
        onPositionChanged: event => {
            if (!pressed || !mouse.armed)
                return;
            if (!mouse.moved && Math.abs(event.x - mouse.pressX) > 6)
                mouse.moved = true;
            if (mouse.moved && docTab.movePolicy)
                docTab.movePolicy(event.x - mouse.pressX);
        }
        // Arrow form: a bare block would inject the signal parameter and
        // shadow this MouseArea's own id.
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

    // Close zone: same hover language as the rest of the bar, revealed
    // when active or hovered. Declared after the tab MouseArea so it
    // stays on top of it.
    Item {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 46
        visible: opacity > 0
        // closeBtn keeps the zone visible once hovered (hover doesn't
        // propagate to the tab MouseArea underneath).
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
