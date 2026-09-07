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

    contentWidth: availableWidth
    clip: true

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

        FillSection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
            doc: panel.doc
        }

        StrokeSection {
            Layout.fillWidth: true
            snapshot: panel.snapshot
        }
    }
}
