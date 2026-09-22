import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Figma-style component export: one row per setting (PNG at 1x/2x/3x,
// or resolution-independent SVG) plus an Export button rendering
// every selected top. PNG renders through the shared CPU painter; SVG
// writes vector-native documents through SvgPaint (same scene
// handling, effects as per-leaf filters except background blur). A
// single file saves directly; several pack into a {Design}.zip of
// layer-named files.
// Stills paint base values on transparency; PNG grain freezes at the
// playhead. Settings live in the section (not the scene), so they
// reset with the panel.
PanelSection {
    id: section

    required property var doc

    title: qsTr("Export")
    // Collapsible: + expands the options, - collapses them again.
    // The scale-row + lives inside the body (see below) now that the
    // header toggle owns expand/collapse.
    showAdd: !section.expanded
    showRemove: section.expanded
    compact: !section.expanded
    onAddClicked: section.expanded = true
    onRemoveClicked: section.expanded = false
    visible: section.hasSelection()

    // Collapsed by default; expands on + and stays until - .
    property bool expanded: false

    // Export format (PNG raster at scales, SVG vector without scales)
    // plus per-row scales for PNG. Reassigned wholesale so Repeaters
    // update (same rule as the tab clipboards).
    property string format: "png"
    property var scales: [1]
    property string notice: ""
    property bool noticeError: false
    property var plan: ({})
    property url pendingSaveUrl: ""

    function hasSelection() {
        if (!section.doc)
            return false;
        section.doc.rev;
        return section.doc.selectedTops().length > 0;
    }

    function addScale() {
        for (var s = 1; s <= 3; s++) {
            if (section.scales.indexOf(s) < 0) {
                section.scales = section.scales.concat([s]);
                return;
            }
        }
    }

    function removeScaleAt(i) {
        if (section.scales.length <= 1)
            return;
        var out = section.scales.slice();
        out.splice(i, 1);
        section.scales = out;
    }

    // Picking a taken scale swaps the two rows (never duplicates).
    function setScaleAt(i, s) {
        var out = section.scales.slice();
        var at = out.indexOf(s);
        if (at >= 0)
            out[at] = out[i];
        out[i] = s;
        section.scales = out;
    }

    function selectionNames() {
        var tops = section.doc.selectedTops();
        var names = [];
        for (var i = 0; i < tops.length; i++)
            names.push(tops[i].name || qsTr("Component"));
        return names;
    }

    function designName() {
        return TabState.titleAt(TabState.currentIndex) || qsTr("Design");
    }

    function startExport() {
        section.notice = "";
        section.noticeError = false;
        if (!section.doc || section.doc.selectedTops().length === 0) {
            section.notice = qsTr("Select components to export.");
            section.noticeError = true;
            return;
        }
        section.plan = ComponentExporter.planExport(section.selectionNames(), section.scales, section.designName(), section.format);
        if (!section.plan || section.plan.fileCount < 1) {
            section.notice = qsTr("Select components to export.");
            section.noticeError = true;
            return;
        }
        savePicker.currentFolder = StandardPaths.writableLocation(StandardPaths.PicturesLocation);
        savePicker.fileName = section.plan.defaultName;
        savePicker.open();
    }

    function fileLabel(url) {
        return String(url).split("/").pop();
    }

    function runExport(dest, overwrite) {
        var tops = section.doc.selectedTops();
        var snaps = [];
        for (var i = 0; i < tops.length; i++)
            snaps.push(section.doc.snapshotNode(tops[i]));
        var frameNo = Math.floor(Number(section.doc.anim.currentTime || 0) * 60);
        var ok = ComponentExporter.exportSelection(snaps, section.selectionNames(), section.scales, section.designName(), dest, overwrite, frameNo, section.format);
        if (ok) {
            section.notice = section.plan.zip ? qsTr("Exported %1 (%2 files)").arg(section.fileLabel(dest)).arg(section.plan.fileCount) : qsTr("Exported %1").arg(section.fileLabel(dest));
            section.noticeError = false;
        } else {
            section.notice = ComponentExporter.lastError !== "" ? ComponentExporter.lastError : qsTr("Export failed.");
            section.noticeError = true;
        }
    }

    // Format switch: PNG raster rows below, SVG vector without scales.
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        SegmentedOption {
            label: qsTr("PNG")
            active: section.format === "png"
            onClicked: section.format = "png"
        }

        SegmentedOption {
            label: qsTr("SVG")
            active: section.format === "svg"
            onClicked: section.format = "svg"
        }
    }

    // Scale rows own their + now that the header toggle owns
    // expand/collapse.
    RowLayout {
        visible: section.format === "png"
        Layout.fillWidth: true
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: qsTr("Scales")
            font.pixelSize: 11
            color: AppTheme.muted
        }

        PanelIconButton {
            iconKind: "plus"
            filled: false
            strong: true
            iconSize: 16
            visible: section.scales.length < 3
            onClicked: section.addScale()
        }
    }

    Repeater {
        model: section.format === "png" ? section.scales : []

        onItemAdded: (index, item) => {
            item.pickPolicy = s => section.setScaleAt(index, s);
            item.removePolicy = () => section.removeScaleAt(index);
        }

        delegate: RowLayout {
            property var pickPolicy: null
            property var removePolicy: null
            property int rowScale: modelData

            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.preferredWidth: 36
                text: "PNG"
                font.pixelSize: 12
                color: AppTheme.muted
            }

            SegmentedOption {
                label: qsTr("1x")
                active: parent.rowScale === 1
                onClicked: parent.pickPolicy(1)
            }

            SegmentedOption {
                label: qsTr("2x")
                active: parent.rowScale === 2
                onClicked: parent.pickPolicy(2)
            }

            SegmentedOption {
                label: qsTr("3x")
                active: parent.rowScale === 3
                onClicked: parent.pickPolicy(3)
            }

            PanelIconButton {
                iconKind: "minimize"
                filled: false
                strong: true
                iconSize: 16
                enabled: section.scales.length > 1
                onClicked: parent.removePolicy()
            }
        }
    }

    // Primary action, in the panel-button language (inverted fill).
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: AppTheme.radiusSmall
        border.width: 1
        border.color: AppTheme.foreground
        color: exportMouse.pressed ? AppTheme.pressed : AppTheme.foreground

        Behavior on color {
            ColorAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }

        Text {
            anchors.centerIn: parent
            text: qsTr("Export")
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: AppTheme.background
        }

        MouseArea {
            id: exportMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: section.startExport()
        }
    }

    // Error-only notice: successes stay silent, failures still surface
    // (without this, a failed export would vanish without a trace).
    Text {
        Layout.fillWidth: true
        visible: section.noticeError && section.notice !== ""
        text: section.notice
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        color: "#e81123"
    }

    FilePicker {
        id: savePicker

        saveMode: true
        suffixes: section.plan && section.plan.suffix ? [section.plan.suffix] : ["png"]
        onAccepted: {
            var dest = savePicker.selectedFile;
            if (ComponentExporter.destinationExists(dest, section.plan.suffix)) {
                section.pendingSaveUrl = dest;
                overwritePopup.ask(qsTr("Overwrite export?"), qsTr("“%1” already exists. Overwriting replaces it.").arg(section.fileLabel(dest)), qsTr("Overwrite"));
            } else {
                section.runExport(dest, false);
            }
        }
    }

    ConfirmPopup {
        id: overwritePopup

        onConfirmed: section.runExport(section.pendingSaveUrl, true)
    }
}
