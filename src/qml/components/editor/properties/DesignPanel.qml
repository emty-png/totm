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

    // Header name: selected shape's layer name (like the left
    // sidebar), count for multi-selections, fallback when empty.
    function headerName() {
        var tops = panel.snapshot.tops;
        if (tops.length === 1)
            return tops[0].name || qsTr("Design");
        if (tops.length > 1)
            return qsTr("%1 selected").arg(tops.length);
        return qsTr("Design");
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

        RowLayout {
            visible: panel.snapshot.sel.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.leftMargin: 12
            Layout.rightMargin: 4
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: panel.headerName()
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: AppTheme.foreground
                elide: Text.ElideRight
            }

            PanelIconButton {
                id: dotsBtn

                iconKind: "dots"
                filled: false
                iconSize: 14
                enabled: !!panel.doc
                onClicked: copyMenu.openNear(dotsBtn, dotsBtn.width / 2, dotsBtn.height / 2)
            }
        }

        PropCopyMenu {
            id: copyMenu

            doc: panel.doc
            scope: "design"
        }

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
