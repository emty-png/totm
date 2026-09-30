import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Web font installer: curated open-licensed families (SIL OFL) from the
// pinned catalog in SettingsStore. Search filters locally; Install
// downloads through the C++ queue (one at a time) into the same
// <AppData>/totm/fonts/ store as manual imports, so installed faces
// appear in the editor picker immediately. Installed rows offer
// removal via the Appearance tab's import list.
Popup {
    id: installer

    parent: Overlay.overlay

    property string query: ""

    // Catalog snapshot plus live download state. Reading the busy/family
    // properties here re-evaluates rows on every progress tick.
    readonly property var catalog: SettingsStore.fontCatalog()
    readonly property bool busy: SettingsStore.fontDownloadBusy
    readonly property string activeFamily: SettingsStore.fontDownloadFamily
    readonly property double progress: SettingsStore.fontDownloadProgress
    readonly property var queue: SettingsStore.fontDownloadQueue
    readonly property int queueTotal: SettingsStore.fontDownloadQueueTotal
    readonly property int queueDone: SettingsStore.fontDownloadQueueDone
    readonly property double queueProgress: SettingsStore.fontDownloadQueueProgress

    // Selection for bulk install. Plain array; reassigned wholesale so
    // bindings update.
    property var selected: []

    function isSelected(family) {
        return installer.selected.indexOf(family) >= 0;
    }

    function toggleSelected(family) {
        var cur = installer.selected.slice();
        var at = cur.indexOf(family);
        if (at >= 0)
            cur.splice(at, 1);
        else
            cur.push(family);
        installer.selected = cur;
    }

    readonly property var filtered: {
        var q = installer.query.trim().toLowerCase();
        var out = [];
        var list = installer.catalog || [];
        for (var i = 0; i < list.length; i++) {
            var e = list[i] || {};
            var name = String(e.family || "");
            var cat = String(e.category || "");
            if (q !== "" && name.toLowerCase().indexOf(q) < 0 && cat.toLowerCase().indexOf(q) < 0)
                continue;
            out.push({
                family: name,
                category: cat,
                license: String(e.license || ""),
                fileCount: Number(e.fileCount) || 0
            });
        }
        return out;
    }

    width: 680
    height: Math.min(460, (Overlay.overlay ? Overlay.overlay.height : 500) - 48)
    x: Math.round(((installer.parent ? installer.parent.width : 680) - installer.width) / 2)
    y: Math.round(((installer.parent ? installer.parent.height : 460) - installer.height) / 2)
    padding: 12
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 0.97
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: 100
            easing.type: Easing.InCubic
        }
    }

    background: Rectangle {
        radius: AppTheme.radiusLarge
        color: AppTheme.surface
        border.width: 1
        border.color: AppTheme.border
    }

    contentItem: ColumnLayout {
        width: parent.width
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: qsTr("Install fonts")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: AppTheme.foreground
                elide: Text.ElideRight
            }

            PanelIconButton {
                iconKind: "close"
                filled: false
                iconSize: 12
                onClicked: installer.close()
            }
        }

        TextField {
            id: searchField

            Layout.fillWidth: true
            implicitHeight: 30
            placeholderText: qsTr("Search fonts...")
            placeholderTextColor: AppTheme.muted
            leftPadding: 10
            font.pixelSize: 12
            color: AppTheme.foreground
            selectByMouse: true
            onTextChanged: installer.query = text

            background: Rectangle {
                radius: AppTheme.radiusSmall
                color: AppTheme.background
                border.width: 1
                border.color: searchField.activeFocus ? AppTheme.selection : AppTheme.fieldBorder
            }
        }

        // Bulk install bar: appears with a selection, doubles as the
        // queue progress line while the queue runs.
        RowLayout {
            Layout.fillWidth: true
            visible: installer.selected.length > 0 || (installer.busy && installer.queueTotal > 1)
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: AppTheme.radiusSmall
                color: bulkMouse.pressed ? AppTheme.pressed : bulkMouse.containsMouse ? AppTheme.hover : AppTheme.foreground
                opacity: installer.busy ? 0.55 : 1

                Text {
                    anchors.centerIn: parent
                    text: installer.busy && installer.queueTotal > 1 ? qsTr("Installing %1/%2...").arg(Math.min(installer.queueDone + 1, installer.queueTotal)).arg(installer.queueTotal) : qsTr("Install selected (%1)").arg(installer.selected.length)
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: AppTheme.background
                }

                MouseArea {
                    id: bulkMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: installer.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: {
                        if (installer.busy)
                            return;
                        if (SettingsStore.installCatalogFonts(installer.selected))
                            installer.selected = [];
                    }
                }
            }

            Text {
                visible: !installer.busy && installer.selected.length > 0
                text: qsTr("Clear")
                font.pixelSize: 12
                color: AppTheme.muted

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: installer.selected = []
                }
            }
        }

        // Errors only: the helper line is gone, failures still surface.
        Text {
            Layout.fillWidth: true
            visible: SettingsStore.fontDownloadError !== ""
            wrapMode: Text.WordWrap
            text: SettingsStore.fontDownloadError
            font.pixelSize: 11
            color: AppTheme.snapGuide
        }

        ListView {
            id: familyList

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 200
            clip: true
            spacing: 4
            model: installer.filtered

            ScrollBar.vertical: ScrollBar {
                // Explicit overflow switch: AsNeeded alone can stick
                // visible after layout churn with a fitting model,
                // leaving a phantom track behind.
                policy: familyList.contentHeight > familyList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: AppTheme.border
                }
                background: Item {
                    implicitWidth: 6
                }
            }

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                // Touch live state so rows flip on progress/finish. The
                // installed check itself is a plain call (no notify), so
                // these reads are what re-evaluate the row.
                readonly property string dlFamily: installer.activeFamily
                readonly property bool dlBusy: installer.busy
                readonly property var dlQueue: installer.queue
                readonly property bool installed: SettingsStore.isFontInstalled(row.modelData.family) && !(row.dlBusy && row.dlFamily === row.modelData.family)
                readonly property bool active: row.dlBusy && row.dlFamily === row.modelData.family
                readonly property bool queued: !row.active && row.dlQueue.indexOf(row.modelData.family) >= 0
                readonly property bool isSelected: installer.isSelected(row.modelData.family)

                width: familyList.width
                height: 64
                radius: AppTheme.radiusMedium
                color: AppTheme.background
                border.width: 1
                border.color: row.isSelected ? AppTheme.selection : AppTheme.fieldBorder

                // Card tap toggles bulk selection; the Install button
                // sits above and keeps its own clicks.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!row.installed && !row.active)
                            installer.toggleSelected(row.modelData.family);
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        text: row.modelData.family
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: AppTheme.foreground
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.category
                        font.pixelSize: 12
                        color: AppTheme.muted
                        elide: Text.ElideRight
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.queued
                    text: qsTr("Queued")
                    font.pixelSize: 12
                    color: AppTheme.muted
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.installed && !row.active
                    text: qsTr("Installed")
                    font.pixelSize: 12
                    color: AppTheme.muted
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.active
                    text: Math.round(installer.progress * 100) + "%"
                    font.pixelSize: 13
                    color: AppTheme.foreground
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !row.installed && !row.active && !row.queued
                    implicitWidth: installLabel.implicitWidth + 32
                    implicitHeight: 34
                    radius: AppTheme.radiusMedium
                    color: installMouse.pressed ? AppTheme.pressed : installMouse.containsMouse ? AppTheme.hover : AppTheme.foreground
                    opacity: installer.busy ? 0.45 : 1

                    Text {
                        id: installLabel

                        anchors.centerIn: parent
                        text: qsTr("Install")
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: AppTheme.background
                    }

                    MouseArea {
                        id: installMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: installer.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (!installer.busy)
                                SettingsStore.installCatalogFont(row.modelData.family);
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: familyList.count === 0
                text: qsTr("No fonts match.")
                font.pixelSize: 12
                color: AppTheme.muted
            }
        }
    }

    function show() {
        installer.query = "";
        installer.selected = [];
        searchField.text = "";
        installer.open();
    }
}
