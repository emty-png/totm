import QtCore
import QtQuick
import QtQuick.Dialogs
import Totm

// Host file picker for plugins. Plugins request picks through
// PluginStore.requestImage/requestAudio and learn only the stored blob
// name via picked(); this host owns the dialogs and the LibraryStore
// import, so plugins never see paths or picker UI.
Item {
    id: picker

    property string pendingId: ""
    property string pendingKind: ""

    Connections {
        target: PluginStore
        function onPickRequested(pluginId, kind) {
            picker.pendingId = pluginId;
            picker.pendingKind = kind;
            if (kind === "audio")
                audioPicker.open();
            else
                imagePicker.open();
        }
    }

    FileDialog {
        id: imagePicker

        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.webp *.gif *.svg)")]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: {
            var name = LibraryStore.importImage(imagePicker.selectedFile);
            if (name)
                PluginStore.commitPick(picker.pendingId, "image", name);
            picker.pendingId = "";
            picker.pendingKind = "";
        }
        onRejected: {
            picker.pendingId = "";
            picker.pendingKind = "";
        }
    }

    FileDialog {
        id: audioPicker

        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Audio (*.mp3 *.wav *.ogg *.flac)")]
        currentFolder: StandardPaths.writableLocation(StandardPaths.MusicLocation)
        onAccepted: {
            var name = LibraryStore.importAudio(audioPicker.selectedFile);
            if (name)
                PluginStore.commitPick(picker.pendingId, "audio", name);
            picker.pendingId = "";
            picker.pendingKind = "";
        }
        onRejected: {
            picker.pendingId = "";
            picker.pendingKind = "";
        }
    }
}
