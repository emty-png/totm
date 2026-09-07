import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

ApplicationWindow {
    id: root
    visible: true
    width: 900
    height: 640
    minimumWidth: 480
    minimumHeight: 360
    title: qsTr("totm")

    flags: Qt.Window | Qt.FramelessWindowHint
    color: AppTheme.background

    onClosing: TabStore.saveAllOpen()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TitleBar {
            Layout.fillWidth: true
            Layout.preferredHeight: 45
            window: root
        }

        // Library/persistence errors. Hidden when clear; dismiss calls
        // back into the store so the next error can surface again.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            visible: LibraryStore.lastError !== ""
            color: AppTheme.surface

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: 1
                color: AppTheme.border
            }

            Text {
                anchors {
                    left: parent.left
                    right: dismissButton.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 8
                }
                text: LibraryStore.lastError
                font.pixelSize: 12
                color: AppTheme.foreground
                elide: Text.ElideRight
            }

            Item {
                id: dismissButton

                anchors {
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                width: 32

                TitleBarIcon {
                    anchors.centerIn: parent
                    kind: "close"
                    width: 12
                    height: 12
                    iconColor: dismissMouse.containsMouse ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: dismissMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LibraryStore.clearError()
                }
            }
        }

        // Home tab content
        HomeView {
            visible: TabStore.isHomeSelected
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // Document tab content
        EditorView {
            visible: !TabStore.isHomeSelected
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    WindowResizeHandles {
        window: root
    }
}
