import QtQuick
import QtQuick.Layouts
import Totm

// One plugin UI slot: mediated Loader with an error boundary so a broken
// plugin shows a muted row instead of breaking the host panel. Passes
// doc/snapshot/pluginId into the loaded item when it declares them.
ColumnLayout {
    id: slot

    property var entry: null
    property var doc: null
    property var snapshot: null

    spacing: 0
    visible: slot.entry !== null && slot.entry !== undefined

    Loader {
        id: loader

        Layout.fillWidth: true
        active: slot.entry !== null && slot.entry !== undefined && slot.entry.url !== undefined
        source: slot.entry !== null && slot.entry !== undefined ? slot.entry.url : ""
        asynchronous: true

        onLoaded: {
            if (item) {
                if ("pluginId" in item)
                    item.pluginId = slot.entry.pluginId;
                if ("doc" in item)
                    item.doc = slot.doc;
                if ("snapshot" in item)
                    item.snapshot = slot.snapshot;
            }
        }
    }

    Connections {
        target: slot.doc
        ignoreUnknownSignals: true
        function onRevChanged() {
            if (loader.item && "doc" in loader.item)
                loader.item.doc = slot.doc;
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        visible: loader.status === Loader.Error
        text: qsTr("Plugin \"%1\" failed to load.").arg(slot.entry ? slot.entry.pluginName || slot.entry.pluginId : "")
        font.pixelSize: 11
        color: AppTheme.muted
        wrapMode: Text.WordWrap
    }
}
