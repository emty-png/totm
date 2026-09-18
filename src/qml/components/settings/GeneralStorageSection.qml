import QtQuick
import QtQuick.Layouts
import Totm

// Storage card: live media footprint plus the library location.
// Read-only on purpose: unreferenced blobs are swept at startup, and
// mid-session undo/clipboard can briefly hold files no saved scene
// points at yet, so there is nothing safe to purge by hand.
Rectangle {
    id: storageCard

    Layout.fillWidth: true
    implicitHeight: storageBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    // Footprint text, refreshed whenever the library changes. The
    // counters are Q_INVOKABLEs (not properties), so plain bindings
    // would evaluate once and go stale — hence the explicit refresh
    // below, same pattern as the design panel's refreshPlugins.
    property string imagesStat: ""
    property string audioStat: ""

    function formatBytes(bytes) {
        var b = Number(bytes) || 0;
        if (b < 1024)
            return qsTr("%1 B").arg(b);
        if (b < 1024 * 1024)
            return qsTr("%1 KB").arg((b / 1024).toFixed(1));
        if (b < 1024 * 1024 * 1024)
            return qsTr("%1 MB").arg((b / (1024 * 1024)).toFixed(1));
        return qsTr("%1 GB").arg((b / (1024 * 1024 * 1024)).toFixed(2));
    }

    function refresh() {
        storageCard.imagesStat = storageCard.formatBytes(LibraryStore.imagesDiskUsage());
        storageCard.audioStat = storageCard.formatBytes(LibraryStore.audioDiskUsage());
    }

    Component.onCompleted: storageCard.refresh()

    Connections {
        target: LibraryStore
        function onLibraryChanged() {
            storageCard.refresh();
        }
    }

    ColumnLayout {
        id: storageBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Storage")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: qsTr("Images")
                font.pixelSize: 12
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            Text {
                text: storageCard.imagesStat
                font.pixelSize: 12
                color: AppTheme.muted
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: qsTr("Audio")
                font.pixelSize: 12
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            Text {
                text: storageCard.audioStat
                font.pixelSize: 12
                color: AppTheme.muted
            }
        }
    }
}
