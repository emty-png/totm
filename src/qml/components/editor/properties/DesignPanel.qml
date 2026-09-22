import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Design properties for the current selection. Single values show
// directly, disagreements show Mixed. Group selections edit the bbox;
// style sections stay shape-only.
ScrollView {
    id: panel

    required property var doc

    property var snapshot: SelectionSnapshot {
        doc: panel.doc
    }
    property var pluginSections: []

    function refreshPlugins() {
        panel.pluginSections = PluginStore.designSections();
    }

    Component.onCompleted: panel.refreshPlugins()

    contentWidth: availableWidth
    clip: true

    Connections {
        target: PluginStore
        function onPluginsChanged() {
            panel.refreshPlugins();
        }
    }

    ColumnLayout {
        width: panel.availableWidth
        spacing: 0

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: panel.availableHeight
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            visible: panel.snapshot.sel.length === 0
            text: qsTr("Nothing to see here...")
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            color: AppTheme.muted
        }

        PositionSection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
            doc: panel.doc
        }

        LayoutSection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
            doc: panel.doc
        }

        AppearanceSection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
        }

        ImageSection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
        }

        TypographySection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
        }

        FillSection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
            doc: panel.doc
        }

        StrokeSection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
            doc: panel.doc
        }

        PenSection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
            doc: panel.doc
        }

        EffectsSection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
        }

        ExportSection {
            Layout.fillWidth: true
            doc: panel.doc
        }

        // Plugin sections (ui.slots). Each entry gets doc + snapshot +
        // pluginId when it declares them; failures show a muted row.
        Repeater {
            model: panel.pluginSections

            delegate: PluginSlot {
                Layout.fillWidth: true
                entry: modelData
                doc: panel.doc
                snapshot: panel.snapshot
            }
        }
    }
}
