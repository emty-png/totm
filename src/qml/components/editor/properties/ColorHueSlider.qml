import QtQuick

// Rainbow hue bar. Drags report h through press and move policies so
// the caller owns transactions, release ends it. Stops are spectral
// (functional, like selection accents) rather than theme colors.
Item {
    id: bar

    property real hue: 0

    property var pressPolicy: null
    property var movePolicy: null
    property var releasePolicy: null

    implicitWidth: 224
    implicitHeight: 14

    Rectangle {
        anchors.fill: parent
        radius: 7
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: Qt.hsva(0, 1, 1, 1)
            }
            GradientStop {
                position: 0.167
                color: Qt.hsva(0.167, 1, 1, 1)
            }
            GradientStop {
                position: 0.333
                color: Qt.hsva(0.333, 1, 1, 1)
            }
            GradientStop {
                position: 0.5
                color: Qt.hsva(0.5, 1, 1, 1)
            }
            GradientStop {
                position: 0.667
                color: Qt.hsva(0.667, 1, 1, 1)
            }
            GradientStop {
                position: 0.833
                color: Qt.hsva(0.833, 1, 1, 1)
            }
            GradientStop {
                position: 1
                color: Qt.hsva(1, 1, 1, 1)
            }
        }
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.2)
    }

    // Handle: white ring riding the bar.
    Rectangle {
        x: Math.round(bar.hue * (bar.width - width))
        y: Math.round((bar.height - height) / 2)
        width: 16
        height: 16
        radius: 8
        color: "white"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.4)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        onPressed: mouse => bar.pick(mouse.x, bar.pressPolicy)
        onPositionChanged: mouse => {
            if (pressed)
                bar.pick(mouse.x, bar.movePolicy);
        }
        onReleased: {
            if (bar.releasePolicy)
                bar.releasePolicy();
        }
    }

    function pick(mx, policy) {
        if (!policy)
            return;
        policy(Math.min(1, Math.max(0, mx / bar.width)));
    }
}
