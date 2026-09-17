import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// In-app file picker: places sidebar plus a navigable file list in the
// app modal language, replacing the stock Qt Quick dialog (unthemeable,
// unfamiliar breadcrumb, cramped buttons). All filesystem reads go
// through FileBrowser; QML only renders rows and owns picked urls.
// Modes mirror FileDialog: open picks an existing file (double-click
// accepts), save types a name (Save confirms). Emits accepted with
// selectedFile set, or rejected on dismiss. Callers preset
// currentFolder (and fileName for save) before open().
Popup {
    id: picker

    property bool saveMode: false
    property var suffixes: []
    property url currentFolder
    property string fileName: ""
    property url selectedFile

    signal accepted
    signal rejected

    // Live state, rebuilt wholesale per navigation so bindings update.
    property url folder
    property var rows: []
    property var crumbs: []
    property var places: []
    property bool readable: true
    property url pickedUrl
    property bool resolved: false

    readonly property var imageSuffixes: ["png", "jpg", "jpeg", "webp", "gif", "svg"]
    readonly property var audioSuffixes: ["mp3", "wav", "ogg", "flac"]

    anchors.centerIn: parent
    implicitWidth: 640
    implicitHeight: 500
    padding: 8
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onOpened: picker.reset()
    onClosed: {
        if (!picker.resolved)
            picker.rejected();
    }

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
        spacing: 8

        // Breadcrumb: up one level plus the root-to-folder chain pinned
        // to the trailing edge, so deep paths read from the useful end.
        // No header row: Cancel and outside-press dismiss the dialog.
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Item {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28

                // Borderless like the dismiss X: a boxed button here
                // doubles the hairline below into a second rule.
                AppIcon {
                    anchors.centerIn: parent
                    kind: "caret"
                    rotation: 180
                    width: 12
                    height: 12
                    iconColor: upMouse.containsMouse || upMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: upMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: picker.go(FileBrowser.parentOf(picker.folder))
                }
            }

            Flickable {
                id: crumbFlick

                Layout.fillWidth: true
                Layout.preferredHeight: 28
                contentWidth: crumbRow.implicitWidth
                clip: true
                flickableDirection: Flickable.HorizontalFlick

                Row {
                    id: crumbRow

                    height: 28
                    spacing: 2

                    Repeater {
                        model: picker.crumbs

                        Row {
                            height: 28
                            spacing: 2

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: index > 0
                                text: "›"
                                font.pixelSize: 12
                                color: AppTheme.muted
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(crumbLabel.implicitWidth + 16, 160)
                                height: 28
                                radius: AppTheme.radiusSmall
                                color: crumbMouse.containsMouse || crumbMouse.pressed ? AppTheme.hover : "transparent"

                                Text {
                                    id: crumbLabel

                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 8
                                        rightMargin: 8
                                    }
                                    text: modelData.name
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    color: index === picker.crumbs.length - 1 ? AppTheme.foreground : AppTheme.muted
                                }

                                MouseArea {
                                    id: crumbMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: picker.go(modelData.url)
                                }
                            }
                        }
                    }
                }

                // New folders land scrolled to the trailing crumb.
                onContentWidthChanged: {
                    if (contentWidth > width)
                        contentX = contentWidth - width;
                    else
                        contentX = 0;
                }
            }
        }

        // Full-bleed separators, edge to edge like the section hairlines.
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: -8
            Layout.rightMargin: -8
            Layout.preferredHeight: 1
            color: AppTheme.border
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Pulled into the surrounding gaps so the sidebar divider
            // touches both hairlines edge to edge.
            Layout.topMargin: -8
            Layout.bottomMargin: -8
            spacing: 8

            // Places sidebar: well-known dirs that exist on this box.
            // Fixed width (min=max): fillWidth rows inside an auto-sized
            // column would otherwise balloon it and starve the file list.
            ColumnLayout {
                Layout.minimumWidth: 150
                Layout.preferredWidth: 150
                Layout.maximumWidth: 150
                Layout.fillHeight: true
                // Breathing room between the top hairline and Home,
                // matching the popup side padding.
                Layout.topMargin: 8
                spacing: 2

                Repeater {
                    model: picker.places

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: AppTheme.radiusSmall
                        color: placeMouse.containsMouse || placeMouse.pressed ? AppTheme.hover : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Item {
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16

                                PickerIcons {
                                    anchors.centerIn: parent
                                    kind: picker.placeKind(modelData.id)
                                    iconColor: AppTheme.muted
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                color: AppTheme.foreground
                            }
                        }

                        MouseArea {
                            id: placeMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: picker.go(modelData.url)
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: AppTheme.border
            }

            // File list: dirs first, single click selects, double-click
            // enters dirs and accepts files in open mode.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: fileList

                    anchors.fill: parent
                    anchors.topMargin: 8
                    clip: true
                    model: picker.rows
                    spacing: 0

                    ScrollBar.vertical: ScrollBar {
                        // Explicit overflow switch: AsNeeded alone can
                        // stick visible after layout churn with a fitting
                        // model, leaving a phantom track behind.
                        policy: fileList.contentHeight > fileList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
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
                        width: fileList.width
                        height: 40
                        radius: AppTheme.radiusSmall
                        color: picker.pickedUrl.toString() === modelData.url.toString() ? AppTheme.layerSelected : rowMouse.containsMouse || rowMouse.pressed ? AppTheme.hover : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                                easing.type: Easing.OutCubic
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Item {
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16

                                PickerIcons {
                                    anchors.centerIn: parent
                                    kind: picker.fileKind(modelData.isDir, modelData.suffix)
                                    iconColor: AppTheme.muted
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.fileName
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    color: AppTheme.foreground
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.isDir ? qsTr("Folder") : picker.detailOf(modelData)
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    color: AppTheme.muted
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            onClicked: {
                                if (modelData.isDir)
                                    picker.pickedUrl = "";
                                else
                                    picker.pickedUrl = modelData.url;
                            }
                            onDoubleClicked: {
                                if (modelData.isDir) {
                                    picker.go(modelData.url);
                                } else if (!picker.saveMode) {
                                    picker.pickedUrl = modelData.url;
                                    picker.acceptOpen();
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: picker.rows.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: picker.readable ? qsTr("Nothing to see here...") : qsTr("Can't open this folder")
                    font.pixelSize: 12
                    color: AppTheme.muted
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: -8
            Layout.rightMargin: -8
            Layout.preferredHeight: 1
            color: AppTheme.border
        }

        // Footer: save-mode name field, Cancel + primary.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: nameField

                Layout.fillWidth: true
                visible: picker.saveMode
                placeholderText: qsTr("File name")
                text: picker.fileName
                font.pixelSize: 12
                color: AppTheme.foreground
                selectionColor: AppTheme.selection
                selectedTextColor: "#ffffff"
                selectByMouse: true
                leftPadding: 8
                rightPadding: 8
                topPadding: 7
                bottomPadding: 7

                background: Rectangle {
                    radius: AppTheme.radiusSmall
                    color: AppTheme.background
                    border.width: 1
                    border.color: nameField.activeFocus ? AppTheme.selection : AppTheme.fieldBorder
                }

                onAccepted: picker.acceptSave()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.preferredWidth: 110
                    Layout.preferredHeight: 32
                    radius: AppTheme.radiusSmall
                    border.width: 1
                    border.color: AppTheme.fieldBorder
                    color: cancelMouse.containsMouse || cancelMouse.pressed ? AppTheme.hover : AppTheme.surface

                    Behavior on color {
                        ColorAnimation {
                            duration: 100
                            easing.type: Easing.OutCubic
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Cancel")
                        font.pixelSize: 12
                        color: cancelMouse.containsMouse || cancelMouse.pressed ? AppTheme.foreground : AppTheme.muted
                    }

                    MouseArea {
                        id: cancelMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.close()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 110
                    Layout.preferredHeight: 32
                    radius: AppTheme.radiusSmall
                    border.width: 1
                    border.color: AppTheme.foreground
                    color: picker.canAccept() ? AppTheme.foreground : AppTheme.surface
                    opacity: picker.canAccept() ? 1 : 0.4

                    Text {
                        anchors.centerIn: parent
                        text: picker.saveMode ? qsTr("Save") : qsTr("Open")
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: picker.canAccept() ? AppTheme.background : AppTheme.muted
                    }

                    MouseArea {
                        id: acceptMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: picker.canAccept() ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (picker.saveMode)
                                picker.acceptSave();
                            else
                                picker.acceptOpen();
                        }
                    }
                }
            }
        }
    }

    // Fresh state per open: land in the requested folder (or Home when
    // it is missing), clear the pick, seed the save-mode name field.
    function reset() {
        picker.resolved = false;
        picker.pickedUrl = "";
        var start = picker.currentFolder;
        if (!picker.validFolder(start)) {
            var places = FileBrowser.places();
            start = places.length > 0 ? places[0].url : "file:///";
        }
        picker.folder = start;
        nameField.text = picker.fileName;
        picker.refresh();
    }

    function go(url) {
        if (!url)
            return;
        picker.folder = url;
        picker.pickedUrl = "";
        picker.refresh();
    }

    function refresh() {
        picker.rows = FileBrowser.list(picker.folder, picker.suffixes);
        picker.crumbs = FileBrowser.breadcrumbs(picker.folder);
        picker.places = FileBrowser.places();
        picker.readable = FileBrowser.isReadable(picker.folder);
    }

    function validFolder(url) {
        return !!url && String(url) !== "" && FileBrowser.isReadable(url);
    }

    function canAccept() {
        if (picker.saveMode)
            return nameField.text.trim() !== "";
        return picker.pickedUrl.toString() !== "";
    }

    function acceptOpen() {
        if (picker.pickedUrl.toString() === "")
            return;
        picker.selectedFile = picker.pickedUrl;
        picker.finish();
    }

    function acceptSave() {
        var name = nameField.text.trim();
        if (name === "")
            return;
        // Suffix stays a backend concern (export/save append when
        // missing); the url below is the literal typed path.
        picker.selectedFile = picker.folder + "/" + name;
        picker.fileName = name;
        picker.finish();
    }

    function finish() {
        picker.resolved = true;
        picker.close();
        picker.accepted();
    }

    function placeKind(id) {
        if (id === "home")
            return "home";
        if (id === "desktop")
            return "desktop";
        if (id === "downloads")
            return "download";
        if (id === "documents")
            return "docs";
        if (id === "music")
            return "music";
        if (id === "pictures")
            return "image";
        if (id === "movies")
            return "film";
        return "folder";
    }

    function fileKind(isDir, suffix) {
        if (isDir)
            return "folder";
        if (picker.audioSuffixes.indexOf(suffix) >= 0)
            return "music";
        if (picker.imageSuffixes.indexOf(suffix) >= 0)
            return "image";
        return "file";
    }

    function detailOf(row) {
        return picker.sizeOf(row.size) + " · " + picker.dateOf(row.modified);
    }

    function sizeOf(bytes) {
        var n = Number(bytes) || 0;
        if (n < 1024)
            return qsTr("%1 B").arg(n);
        if (n < 1048576)
            return qsTr("%1 KB").arg((n / 1024).toFixed(1));
        if (n < 1073741824)
            return qsTr("%1 MB").arg((n / 1048576).toFixed(1));
        return qsTr("%1 GB").arg((n / 1073741824).toFixed(1));
    }

    function dateOf(iso) {
        var t = Date.parse(iso);
        if (isNaN(t))
            return "";
        return new Date(t).toLocaleDateString(Qt.locale(), "MMM d");
    }
}
