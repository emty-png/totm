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
