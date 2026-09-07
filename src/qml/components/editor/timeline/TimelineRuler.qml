import QtQuick
import Totm

// Timeline ruler: adaptive ticks plus click/drag seeking. Majors
// every second; halves gain labels once spread out, tenths appear
// with labels when zoomed deep. The playhead itself lives in
// TimelineView so one overlay spans the ruler and all lanes.
Item {
    id: ruler

    required property var doc
    required property real pxPerSec
    required property real originX

    readonly property real seconds: ruler.doc ? Math.max(0.5, ruler.doc.anim.duration) : 4.0
    // Label tiers by zoom so text never collides: halves from 200px/s
    // (100px apart), tenths from 400px/s (40px apart).
    readonly property bool showHalfLabels: ruler.pxPerSec >= 200
    readonly property bool showTenths: ruler.pxPerSec >= 160
    readonly property bool showTenthLabels: ruler.pxPerSec >= 400

    implicitHeight: 28

    // Second ticks with labels every second.
    Repeater {
        model: Math.floor(ruler.seconds) + 1

        Item {
            x: ruler.originX + index * ruler.pxPerSec
            width: 1
            height: parent.height

            Rectangle {
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                }
                width: 1
                height: 8
                color: AppTheme.border
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 5
                    bottom: parent.bottom
                    bottomMargin: 10
                }
                text: index === 0 ? qsTr("0s") : qsTr("%1s").arg(index)
                font.pixelSize: 10
                color: AppTheme.muted
            }
        }
    }

    // Half-second ticks between the majors, labeled once spread out.
    Repeater {
        model: Math.floor(ruler.seconds * 2) + 1

        Item {
            visible: index % 2 === 1 && index * 0.5 <= ruler.seconds
            x: ruler.originX + index * 0.5 * ruler.pxPerSec
            width: 1
            height: parent.height

            Rectangle {
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                }
                width: 1
                height: 6
                color: AppTheme.border
            }

            Text {
                visible: ruler.showHalfLabels
                anchors {
                    left: parent.left
                    leftMargin: 5
                    bottom: parent.bottom
                    bottomMargin: 10
                }
                text: qsTr("%1s").arg((index * 0.5).toFixed(1))
                font.pixelSize: 9
                color: AppTheme.muted
            }
        }
    }

    // Tenth-second ticks for zoomed-in timing, labeled when deep.
    // Multiples of a half already draw above, so these skip them.
    Repeater {
        model: ruler.showTenths ? Math.floor(ruler.seconds * 10) + 1 : 0

        Item {
            visible: index % 5 !== 0 && index * 0.1 <= ruler.seconds + 1e-6
            x: ruler.originX + index * 0.1 * ruler.pxPerSec
            width: 1
            height: parent.height

            Rectangle {
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                }
                width: 1
                height: 3
                color: AppTheme.border
            }

            Text {
                visible: ruler.showTenthLabels && index % 5 !== 0
                anchors {
                    left: parent.left
                    leftMargin: 4
                    bottom: parent.bottom
                    bottomMargin: 10
                }
                text: qsTr("%1s").arg((index * 0.1).toFixed(1))
                font.pixelSize: 9
                color: AppTheme.muted
            }
        }
    }

    // Seek: press or drag anywhere on the ruler. Sampling is silent,
    // so scrubbing previews frames without dirtying the document.
    MouseArea {
        id: seekMouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        preventStealing: true

        function seekAt(x) {
            if (ruler.doc)
                ruler.doc.seekPlayhead(Math.min(ruler.seconds, Math.max(0, (x - ruler.originX) / ruler.pxPerSec)));
        }

        // Grabbing the ruler stops playback and finishes any open field
        // editor; the seek below lands the frozen frame where pressed.
        onPressed: mouse => {
            ruler.forceActiveFocus();
            if (ruler.doc && ruler.doc.anim.playing)
                ruler.doc.anim.pause();
            seekMouse.seekAt(mouse.x);
        }
        onPositionChanged: mouse => {
            if (seekMouse.pressed)
                seekMouse.seekAt(mouse.x);
        }
    }
}
