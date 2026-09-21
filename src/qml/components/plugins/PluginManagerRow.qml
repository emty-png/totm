import QtQuick
import QtQuick.Layouts
import Totm

// One plugin card in the settings panel: enable checkbox, name/version,
// description or error, granted count, plus Review. Self-contained for
// Repeater use; the panel wires togglePolicy/reviewPolicy in onItemAdded.
Rectangle {
    id: row

    property var entry: null
    property var togglePolicy: null
    property var reviewPolicy: null

    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: hoverMouse.containsMouse ? AppTheme.hover : AppTheme.surface
    // Self-sizing for layout use: content height plus the 12px margins.
    implicitHeight: body.implicitHeight + 24

    Behavior on color {
        ColorAnimation {
            duration: 100
            easing.type: Easing.OutCubic
        }
    }

    MouseArea {
        id: hoverMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    RowLayout {
        id: body

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 2
            radius: AppTheme.radiusSmall
            border.width: 1
            border.color: AppTheme.fieldBorder
            color: row.entry && row.entry.enabled ? AppTheme.foreground : AppTheme.surface

            AppIcon {
                anchors.centerIn: parent
                kind: "plus"
                rotation: 45
                width: 12
                height: 12
                visible: row.entry && row.entry.enabled
                iconColor: AppTheme.background
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (row.togglePolicy)
                        row.togglePolicy(row.entry ? row.entry.id : "");
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: row.entry ? (row.entry.name || row.entry.id) : ""
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: AppTheme.foreground
                    elide: Text.ElideRight
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    visible: row.entry && !row.entry.error && !!row.entry.version
                    text: row.entry && row.entry.version ? qsTr("v%1").arg(row.entry.version) : ""
                    font.pixelSize: 11
                    color: AppTheme.muted
                    elide: Text.ElideRight
                }

                Row {
                    Layout.alignment: Qt.AlignVCenter
                    visible: row.entry && !row.entry.error && !!row.entry.official
                    spacing: 4

                    OfficialBadge {
                        anchors.verticalCenter: parent.verticalCenter
                        badgeSize: 14
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Official")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: AppTheme.selection
                        elide: Text.ElideRight
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    visible: row.entry && !row.entry.error
                    text: qsTr("Review")
                    font.pixelSize: 11
                    font.underline: true
                    color: reviewMouse.containsMouse ? AppTheme.foreground : AppTheme.muted

                    MouseArea {
                        id: reviewMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (row.reviewPolicy)
                                row.reviewPolicy(row.entry ? row.entry.id : "");
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: row.entry && !!row.entry.error
                text: row.entry ? (row.entry.error || "") : ""
                font.pixelSize: 11
                color: AppTheme.muted
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: row.entry && !row.entry.error && !!row.entry.description
                text: row.entry ? (row.entry.description || "") : ""
                font.pixelSize: 11
                color: AppTheme.muted
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
