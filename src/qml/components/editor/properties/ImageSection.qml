import QtCore
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import Totm

// Image source section: thumbnail plus Replace. Visible only when every
// selected leaf is an image; mixed selections keep shared sections only.
PanelSection {
    id: section

    required property var snapshot

    title: qsTr("Image")
    visible: section.snapshot.sel.length > 0 && section.snapshot.allOfType("image")
    enabled: !section.snapshot.allLocked

    function currentSource() {
        if (section.snapshot.sel.length === 0)
            return "";
        return section.snapshot.sel[0].imageSource ?? "";
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: AppTheme.surface
            border.width: 1
            border.color: AppTheme.fieldBorder
            clip: true

            Image {
                anchors.fill: parent
                source: section.currentSource() ? LibraryStore.imageUrl(section.currentSource()) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
            }

            AppIcon {
                anchors.centerIn: parent
                kind: "image"
                iconColor: AppTheme.muted
                visible: section.currentSource() === ""
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: section.snapshot.commonOf("imageSource").mixed ? qsTr("Mixed") : (section.currentSource() === "" ? qsTr("Missing image") : section.currentSource())
                font.pixelSize: 11
                color: AppTheme.muted
                elide: Text.ElideMiddle
            }

            SegmentedOption {
                label: qsTr("Replace")
                onClicked: replacePicker.open()
            }
        }
    }

    FileDialog {
        id: replacePicker

        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.webp *.gif *.svg)")]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: {
            var name = LibraryStore.importImage(selectedFile);
            if (name)
                section.snapshot.setAll("imageSource", name);
        }
    }
}
