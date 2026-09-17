import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

Window {
    id: root

    property bool copied: false

    visible: true
    width: 640
    height: 440
    minimumWidth: 520
    minimumHeight: 360
    title: qsTr("totm crashed")
    color: AppTheme.background

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Sorry, totm crashed")
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: AppTheme.foreground
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Your library autosaves as you work, so your designs should still be here. If this keeps happening, press Report on GitHub or copy the log into an issue.")
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            color: AppTheme.muted
        }

        Text {
            Layout.fillWidth: true
            visible: CrashReporter.crashSummary !== ""
            text: CrashReporter.crashSummary
            font.pixelSize: 11
            color: AppTheme.muted
            elide: Text.ElideRight
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            background: Rectangle {
                radius: AppTheme.radiusSmall
                color: AppTheme.background
                border.width: 1
                border.color: AppTheme.fieldBorder
            }

            TextArea {
                readOnly: true
                selectByMouse: true
                wrapMode: Text.NoWrap
                font.family: "monospace"
                font.pixelSize: 11
                color: AppTheme.foreground
                text: CrashReporter.crashLog
                placeholderText: qsTr("No log lines were recorded.")
                leftPadding: 8
                rightPadding: 8
                topPadding: 6
                bottomPadding: 6
                background: Rectangle {
                    color: "transparent"
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: copyMouse.containsMouse || copyMouse.pressed ? AppTheme.hover : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.copied ? qsTr("Copied") : qsTr("Copy log")
                    font.pixelSize: 12
                    color: AppTheme.foreground
                }

                MouseArea {
                    id: copyMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (CrashReporter.copyReport())
                            root.copied = true;
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.foreground
                color: AppTheme.foreground

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Report on GitHub")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: AppTheme.background
                }

                MouseArea {
                    id: issuesMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: CrashReporter.openIssues()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: AppTheme.radiusSmall
            border.width: 1
            border.color: AppTheme.fieldBorder
            color: closeMouse.containsMouse || closeMouse.pressed ? AppTheme.hover : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                anchors.centerIn: parent
                text: qsTr("Close")
                font.pixelSize: 12
                color: AppTheme.foreground
            }

            MouseArea {
                id: closeMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    CrashReporter.dismiss();
                    Qt.quit();
                }
            }
        }
    }
}
