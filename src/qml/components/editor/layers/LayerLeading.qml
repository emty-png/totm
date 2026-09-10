import QtQuick
import QtQuick.Layouts
import Totm

// Leading slot of a layers row: group chevron or shape-type icon.
RowLayout {
    id: leading

    required property bool isGroup
    required property bool nodeExpanded
    required property string rowType
    required property bool selected
    required property bool rowVisible
    property var togglePolicy: null

    readonly property alias hovered: chevronMouse.containsMouse

    spacing: 8

    Item {
        Layout.preferredWidth: 16
        Layout.preferredHeight: 16
        Layout.alignment: Qt.AlignVCenter
        visible: leading.isGroup

        AppIcon {
            anchors.centerIn: parent
            width: 12
            height: 12
            kind: "caret"
            rotation: leading.nodeExpanded ? 0 : -90
            iconColor: leading.selected ? AppTheme.foreground : AppTheme.muted

            Behavior on rotation {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on iconColor {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: chevronMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (leading.togglePolicy)
                    leading.togglePolicy();
            }
        }
    }

    AppIcon {
        Layout.preferredWidth: 16
        Layout.preferredHeight: 16
        Layout.alignment: Qt.AlignVCenter
        visible: !leading.isGroup
        opacity: leading.rowVisible ? 1 : 0.45
        kind: ToolState.shapeIconFor(leading.rowType)
        iconColor: leading.selected ? AppTheme.foreground : AppTheme.muted

        Behavior on opacity {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
        Behavior on iconColor {
            ColorAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }
    }
}
