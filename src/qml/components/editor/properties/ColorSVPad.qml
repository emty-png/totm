import QtQuick

// Saturation/value square for one hue. White fades in from the left,
// black fades up from the bottom; drags report (s, v) through press
// and move policies so the caller owns transactions, release ends it.
// Layered gradients only (no shaders), so this works on every backend.
Item {
    id: pad

    property real hue: 0
    property real sat: 1
    property real val: 1

    property var pressPolicy: null
    property var movePolicy: null
    property var releasePolicy: null

    implicitWidth: 224
    implicitHeight: 190

    // Pure hue base.
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Qt.hsva(pad.hue, 1, 1, 1)
    }

    // White from the left (desaturate).
    Rectangle {
        anchors.fill: parent
        radius: 8
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: "white"
            }
            GradientStop {
                position: 1
                color: Qt.rgba(1, 1, 1, 0)
            }
        }
    }

    // Black from the bottom (darken).
    Rectangle {
        anchors.fill: parent
        radius: 8
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.rgba(0, 0, 0, 0)
            }
            GradientStop {
                position: 1
                color: "black"
            }
        }
    }

    // Handle: white ring, live color center.
    Rectangle {
        x: Math.round(pad.sat * (pad.width - width))
        y: Math.round((1 - pad.val) * (pad.height - height))
        width: 16
        height: 16
        radius: 8
        color: "white"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.4)

        Rectangle {
            anchors.centerIn: parent
            width: 10
            height: 10
            radius: 5
            color: Qt.hsva(pad.hue, pad.sat, pad.val, 1)
        }
    }

    // Hairline frame above the gradients, below nothing else.
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.2)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: Qt.CrossCursor
        onPressed: mouse => pad.pick(mouse.x, mouse.y, pad.pressPolicy)
        onPositionChanged: mouse => {
            if (pressed)
                pad.pick(mouse.x, mouse.y, pad.movePolicy);
        }
        onReleased: {
            if (pad.releasePolicy)
                pad.releasePolicy();
        }
    }

    function pick(mx, my, policy) {
        if (!policy)
            return;
        var s = Math.min(1, Math.max(0, mx / pad.width));
        var v = 1 - Math.min(1, Math.max(0, my / pad.height));
        policy(s, v);
    }
}
