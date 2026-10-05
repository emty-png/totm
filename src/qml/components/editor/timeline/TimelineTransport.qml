import QtQuick
import QtQuick.Layouts
import Totm

// Timeline transport block: play/pause, stop and composition duration.
// Sits atop the gutter beside the ruler; the hairline pairs with the
// tracks side so the header reads across the divider.
Item {
    id: transport

    required property var doc
    required property real headerHeight

    implicitHeight: transport.headerHeight

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 12
            rightMargin: 12
        }
        spacing: 8

        ToolbarButton {
            Layout.alignment: Qt.AlignVCenter
            iconKind: transport.doc && transport.doc.anim.playing ? "pause" : "play"
            onClicked: {
                if (!transport.doc)
                    return;
                if (transport.doc.anim.playing)
                    transport.doc.anim.pause();
                else
                    transport.doc.anim.play();
            }
        }

        ToolbarButton {
            Layout.alignment: Qt.AlignVCenter
            iconKind: "stop"
            onClicked: {
                if (transport.doc)
                    transport.doc.anim.stop();
            }
        }

        // Auto-key arm: selection edits capture keys at the playhead on
        // keyframeable clips covering the selection. Session-only.
        ToolbarButton {
            Layout.alignment: Qt.AlignVCenter
            iconKind: "circle"
            active: !!transport.doc && transport.doc.anim.recordArmed
            onClicked: {
                if (transport.doc)
                    transport.doc.anim.toggleRecord();
            }
        }

        // Composition loop: off stops at the end (default), on wraps.
        // Session-only like record; video footage loop stays per-shape.
        ToolbarButton {
            Layout.alignment: Qt.AlignVCenter
            iconKind: "refresh"
            active: !!transport.doc && transport.doc.anim.loop === true
            onClicked: {
                if (transport.doc)
                    transport.doc.anim.loop = !(transport.doc.anim.loop === true);
            }
        }

        NumberField {
            Layout.preferredWidth: 76
            Layout.alignment: Qt.AlignVCenter
            suffix: "s"
            scrubStep: 0.1
            minimum: 0.5
            maximum: 1800
            value: transport.doc ? transport.doc.anim.duration : 4.0
            onCommitted: v => {
                if (transport.doc)
                    transport.doc.setAnimDuration(v);
            }
            onScrubStarted: {
                if (transport.doc)
                    transport.doc.beginTransaction();
            }
            onScrubFinished: {
                if (transport.doc)
                    transport.doc.endTransaction();
            }
        }
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: AppTheme.border
    }
}
