import QtQuick
import QtQuick.Layouts

// macOS traffic lights for the frameless window: native apps show
// close/minimize/zoom left-aligned, so we mirror that instead of the
// Windows-style right controls. Circles only; glyphs appear on hover
// of the whole cluster like the real thing. Zoom toggles maximize.
RowLayout {
    id: lights

    required property Window window

    spacing: 8
    Layout.fillHeight: true
    Layout.leftMargin: 20
    Layout.rightMargin: 4

    component Light: Rectangle {
        id: light

        required property color fill
        required property string glyph
        signal clicked

        Layout.preferredWidth: 12
        Layout.preferredHeight: 12
        Layout.alignment: Qt.AlignVCenter
        radius: 6
        color: mouse.pressed ? Qt.darker(light.fill, 1.15) : light.fill
        border.width: 1
        border.color: Qt.darker(light.fill, 1.25)

        Text {
            anchors.centerIn: parent
            visible: lightsHover.hovered
            text: light.glyph
            font.pixelSize: 9
            font.weight: Font.DemiBold
            color: "#66000000"
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: false
            acceptedButtons: Qt.LeftButton
            onClicked: light.clicked()
        }
    }

    HoverHandler {
        id: lightsHover
    }

    Light {
        fill: "#ff5f57"
        glyph: "×"
        onClicked: lights.window.close()
    }

    Light {
        fill: "#febc2e"
        glyph: "–"
        onClicked: lights.window.showMinimized()
    }

    Light {
        fill: "#28c840"
        glyph: "+"
        onClicked: {
            if (lights.window.visibility === Window.Maximized)
                lights.window.showNormal();
            else
                lights.window.showMaximized();
        }
    }
}
