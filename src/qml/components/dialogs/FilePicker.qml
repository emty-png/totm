import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// In-app file picker in the app modal language, with Blender's file
// browser structure: a navigation toolbar (history + path + search),
// a sectioned places sidebar, large grid tiles (default) or a dense
// sortable list, and a filename footer.
//
// All filesystem reads go through FileBrowser; QML only renders rows
// and owns picked urls. Modes mirror FileDialog: open picks an existing
// file (double-click accepts), save types a name (Save confirms), and
// folder mode confirms the current folder. Emits accepted with
// selectedFile set, or rejected on dismiss. Callers preset currentFolder
// (and fileName for save) before open(). Always centered in the app:
// parented to the window overlay, so the declaring panel or canvas never
// pulls it off-center.
Popup {
    id: picker

    parent: Overlay.overlay

    property bool saveMode: false
    // Folder mode: pick a directory (plugin import). The primary button
    // confirms the current folder; dir rows keep navigating.
    property bool folderMode: false
    property var suffixes: []
    property url currentFolder
    property string fileName: ""
    property url selectedFile

    signal accepted
    signal rejected

    // Live state, rebuilt wholesale per navigation so bindings update.
    property url folder
    property var rows: []
    property var viewRows: []
    property var places: []
    property var volumes: []
    property var recents: []
    property string searchText: ""
    property string pathText: ""
    property bool pathEditing: false
    property bool pathError: false
    property bool readable: true
    property bool writable: false
    property url pickedUrl
    property string pickedName: ""
    property bool resolved: false
    property string viewMode: "grid"
    property string sortKey: "name"
    property bool sortAscending: true
    property bool showHidden: false
    property var history: []
    property int historyIndex: -1
    property int focusIndex: -1
    property bool creatingFolder: false
    property string newFolderError: ""
    property bool nameError: false
    property url pendingPickUrl

    readonly property bool compact: width < 700
    readonly property bool canGoBack: historyIndex > 0
    readonly property bool canGoForward: historyIndex >= 0 && historyIndex < history.length - 1
    readonly property url parentFolder: folder.toString() !== "" ? FileBrowser.parentOf(folder) : ""
    readonly property bool atRoot: parentFolder.toString() === ""

    readonly property var imageSuffixes: ["png", "jpg", "jpeg", "webp", "gif", "svg", "bmp", "tif", "tiff"]
    readonly property var audioSuffixes: ["mp3", "wav", "ogg", "flac"]
    readonly property var videoSuffixes: ["mp4", "webm", "mov", "m4v", "mkv"]

    anchors.centerIn: parent
    implicitWidth: Math.min(820, parent ? Math.max(320, parent.width - 32) : 820)
    implicitHeight: Math.min(560, parent ? Math.max(260, parent.height - 32) : 560)
    padding: 8
    modal: true
    dim: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onOpened: picker.reset()
    onClosed: {
        optionsPopup.close();
        placesPopup.close();
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

        // Navigation toolbar: history, editable path, new folder,
        // search, view toggle, options. The places button appears only
        // in compact mode, where the sidebar gives way to a popup.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 6

            IconButton {
                id: placesButton

                visible: picker.compact
                iconKind: "folder"
                tooltip: qsTr("Places")
                onClicked: picker.openPlaces(placesButton)
            }

            IconButton {
                iconKind: "back"
                tooltip: qsTr("Back")
                interactive: picker.canGoBack
                onClicked: picker.goBack()
            }

            IconButton {
                iconKind: "forward"
                tooltip: qsTr("Forward")
                interactive: picker.canGoForward
                onClicked: picker.goForward()
            }

            IconButton {
                iconKind: "up"
                tooltip: qsTr("Up one folder")
                interactive: !picker.atRoot
                onClicked: picker.goUp()
            }

            IconButton {
                iconKind: "refresh"
                tooltip: qsTr("Refresh")
                onClicked: picker.refresh()
            }

            // Path bar: middle-elided display until clicked; Ctrl+L also
            // enters edit mode. Enter navigates, Esc restores.
            Item {
                Layout.fillWidth: true
                Layout.minimumWidth: 60
                Layout.preferredHeight: 28

                Rectangle {
                    anchors.fill: parent
                    radius: AppTheme.radiusSmall
                    color: AppTheme.background
                    border.width: 1
                    border.color: picker.pathError ? AppTheme.snapGuide : pathField.activeFocus ? AppTheme.selection : AppTheme.fieldBorder

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        visible: !picker.pathEditing
                        verticalAlignment: Text.AlignVCenter
                        text: picker.pathText
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                        color: AppTheme.foreground

                        MouseArea {
                            id: pathMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.IBeamCursor
                            onClicked: picker.beginPathEdit()
                        }
                    }

                    TextField {
                        id: pathField

                        anchors.fill: parent
                        visible: picker.pathEditing
                        leftPadding: 8
                        rightPadding: 8
                        topPadding: 5
                        bottomPadding: 5
                        font.pixelSize: 12
                        color: AppTheme.foreground
                        selectionColor: AppTheme.selection
                        selectedTextColor: "#ffffff"
                        selectByMouse: true
                        background: Item {}
                        onAccepted: picker.commitPath()
                        onTextChanged: picker.pathError = false
                        onActiveFocusChanged: {
                            if (!activeFocus && picker.pathEditing)
                                picker.cancelPathEdit();
                        }
                        Keys.onEscapePressed: event => {
                            picker.cancelPathEdit();
                            event.accepted = true;
                        }
                    }
                }

                ToolTip.visible: pathMouse.containsMouse && !picker.pathEditing
                ToolTip.text: picker.pathText
                ToolTip.delay: 700
            }

            IconButton {
                visible: !picker.compact
                iconKind: "folderPlus"
                tooltip: qsTr("New folder")
                interactive: picker.writable
                onClicked: picker.openFolderCreator()
            }

            PickerTextField {
                id: searchField

                Layout.preferredWidth: picker.compact ? 100 : 170
                Layout.minimumWidth: picker.compact ? 70 : 120
                Layout.preferredHeight: 28
                leftPadding: 28
                rightPadding: 26
                placeholderText: qsTr("Search")
                onTextChanged: picker.setSearch(text)
                onAccepted: picker.focusView()
                Keys.onEscapePressed: event => {
                    if (searchField.text !== "")
                        searchField.text = "";
                    else
                        picker.focusView();
                    event.accepted = true;
                }

                AppIcon {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 9
                    }
                    width: 13
                    height: 13
                    kind: "search"
                    iconColor: AppTheme.muted
                }

                AppIcon {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 9
                    }
                    width: 12
                    height: 12
                    visible: searchField.text !== ""
                    kind: "close"
                    iconColor: searchClearMouse.containsMouse ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: searchClearMouse

                    anchors {
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: 26
                    visible: searchField.text !== ""
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        searchField.text = "";
                        searchField.forceActiveFocus();
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 58
                Layout.preferredHeight: 28
                radius: AppTheme.radiusSmall
                color: "transparent"
                border.width: 1
                border.color: AppTheme.fieldBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 1
                    spacing: 0

                    IconButton {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 24
                        iconKind: "apps"
                        tooltip: qsTr("Grid view")
                        active: picker.viewMode === "grid"
                        onClicked: picker.setViewMode("grid")
                    }

                    IconButton {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 24
                        iconKind: "list"
                        tooltip: qsTr("List view")
                        active: picker.viewMode === "list"
                        onClicked: picker.setViewMode("list")
                    }
                }
            }

            IconButton {
                id: optionsButton

                iconKind: "funnel"
                tooltip: qsTr("View options")
                onClicked: picker.openOptions(optionsButton)
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
            id: bodyRow

            Layout.fillWidth: true
            Layout.fillHeight: true
            // Pulled into the surrounding gaps so the body touches both
            // hairlines; the sidebar gets its own inset panel.
            Layout.topMargin: -8
            Layout.bottomMargin: -8
            spacing: 8

            // Places sidebar: well-known dirs, mounts and recent folders.
            Rectangle {
                id: sidebarPanel

                visible: !picker.compact
                Layout.preferredWidth: 180
                Layout.fillHeight: true
                radius: AppTheme.radiusSmall
                color: AppTheme.background
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    contentWidth: width
                    contentHeight: navSections.implicitHeight
                    flickableDirection: Flickable.VerticalFlick

                    ScrollBar.vertical: ScrollBar {
                        policy: contentHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: 3
                            color: AppTheme.border
                        }
                        background: Item {
                            implicitWidth: 6
                        }
                    }

                    NavSections {
                        id: navSections

                        width: parent.width
                        placesModel: picker.places
                        volumesModel: picker.volumes
                        recentsModel: picker.recents
                        currentUrl: picker.folder.toString()
                        onNavigate: url => picker.go(url)
                    }
                }
            }

            Item {
                id: contentPane

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 6

                    // Inline creation bar, Blender-style: create and
                    // enter the folder without leaving the browser.
                    Rectangle {
                        visible: picker.creatingFolder
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? (picker.newFolderError !== "" ? 64 : 44) : 0
                        radius: AppTheme.radiusSmall
                        color: AppTheme.background
                        border.width: 1
                        border.color: AppTheme.fieldBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 7
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                PickerTextField {
                                    id: newFolderField

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    invalid: picker.newFolderError !== ""
                                    placeholderText: qsTr("Folder name")
                                    onTextChanged: picker.newFolderError = ""
                                    onAccepted: picker.commitNewFolder()
                                    Keys.onEscapePressed: event => {
                                        picker.cancelNewFolder();
                                        event.accepted = true;
                                    }
                                }

                                PickerButton {
                                    Layout.preferredHeight: 28
                                    label: qsTr("Create")
                                    onClicked: picker.commitNewFolder()
                                }

                                PickerButton {
                                    Layout.preferredHeight: 28
                                    label: qsTr("Cancel")
                                    onClicked: picker.cancelNewFolder()
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: picker.newFolderError !== ""
                                text: picker.newFolderError
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                color: AppTheme.snapGuide
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        // Grid view, the default: large folder/type glyphs
                        // or image thumbnails, name underneath.
                        GridView {
                            id: gridView

                            anchors.fill: parent
                            visible: picker.viewMode === "grid"
                            clip: true
                            model: picker.viewRows
                            cellWidth: Math.max(96, Math.floor(width / Math.max(1, Math.floor(width / 112))))
                            cellHeight: 112
                            boundsBehavior: Flickable.StopAtBounds
                            activeFocusOnTab: true
                            focus: visible
                            keyNavigationWraps: false
                            onCurrentIndexChanged: {
                                if (gridView.activeFocus && gridView.currentIndex >= 0)
                                    picker.focusRow(gridView.currentIndex);
                            }
                            Keys.onPressed: event => picker.handleViewKey(event)

                            ScrollBar.vertical: ScrollBar {
                                policy: contentHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                contentItem: Rectangle {
                                    implicitWidth: 6
                                    radius: 3
                                    color: AppTheme.border
                                }
                                background: Item {
                                    implicitWidth: 6
                                }
                            }

                            delegate: Item {
                                id: cell

                                required property var modelData
                                required property int index

                                width: gridView.cellWidth
                                height: gridView.cellHeight

                                readonly property bool hovered: cellMouse.containsMouse
                                readonly property bool selected: picker.isPicked(cell.modelData.url)
                                readonly property bool focused: gridView.activeFocus && gridView.currentIndex === cell.index
                                readonly property bool isDir: !!cell.modelData.isDir
                                readonly property bool isImage: !cell.isDir && picker.imageSuffixes.indexOf(String(cell.modelData.suffix || "").toLowerCase()) >= 0

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: AppTheme.radiusMedium
                                    color: cell.selected ? AppTheme.layerSelected : cell.hovered || cell.focused ? AppTheme.hover : "transparent"
                                    border.width: cell.selected || cell.focused ? 1 : 0
                                    border.color: cell.selected ? AppTheme.selection : AppTheme.fieldBorder

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 3

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true

                                            PickerIcons {
                                                anchors.centerIn: parent
                                                width: 42
                                                height: 42
                                                visible: !(cell.isImage && thumb.status === Image.Ready)
                                                kind: picker.fileKind(cell.isDir, String(cell.modelData.suffix || ""))
                                                iconColor: cell.selected || cell.focused || cell.hovered ? AppTheme.foreground : AppTheme.muted
                                            }

                                            Image {
                                                id: thumb

                                                anchors.fill: parent
                                                anchors.margins: 1
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                                cache: true
                                                sourceSize: Qt.size(180, 140)
                                                source: cell.isImage ? FileBrowser.thumbnailSource(cell.modelData.url, String(cell.modelData.modified || "")) : ""
                                                visible: cell.isImage && status === Image.Ready
                                                onStatusChanged: {
                                                    if (status === Image.Error)
                                                        source = "";
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 14
                                            text: String(cell.modelData.fileName || "")
                                            font.pixelSize: 11
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            color: AppTheme.foreground
                                        }
                                    }
                                }

                                MouseArea {
                                    id: cellMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: picker.clickRow(gridView, cell.index)
                                    onDoubleClicked: picker.activateIndex(cell.index)
                                }

                                ToolTip.visible: cellMouse.containsMouse
                                ToolTip.text: picker.tileTooltip(cell.modelData)
                                ToolTip.delay: 700
                            }
                        }

                        // Dense list view with sortable columns.
                        Item {
                            id: listPane

                            anchors.fill: parent
                            visible: picker.viewMode === "list"

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    color: "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Item {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true

                                            Text {
                                                anchors.fill: parent
                                                verticalAlignment: Text.AlignVCenter
                                                text: picker.sortHeaderLabel(qsTr("Name"), "name")
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                                color: AppTheme.muted
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: picker.setSortKey("name")
                                            }
                                        }

                                        Item {
                                            Layout.preferredWidth: 60
                                            Layout.fillHeight: true

                                            Text {
                                                anchors.fill: parent
                                                verticalAlignment: Text.AlignVCenter
                                                horizontalAlignment: Text.AlignRight
                                                text: picker.sortHeaderLabel(qsTr("Size"), "size")
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: AppTheme.muted
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: picker.setSortKey("size")
                                            }
                                        }

                                        Item {
                                            visible: !picker.compact
                                            Layout.preferredWidth: 84
                                            Layout.fillHeight: true

                                            Text {
                                                anchors.fill: parent
                                                verticalAlignment: Text.AlignVCenter
                                                text: picker.sortHeaderLabel(qsTr("Modified"), "modified")
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: AppTheme.muted
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: picker.setSortKey("modified")
                                            }
                                        }

                                        Item {
                                            visible: !picker.compact
                                            Layout.preferredWidth: 54
                                            Layout.fillHeight: true

                                            Text {
                                                anchors.fill: parent
                                                verticalAlignment: Text.AlignVCenter
                                                text: picker.sortHeaderLabel(qsTr("Type"), "type")
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                                color: AppTheme.muted
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: picker.setSortKey("type")
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: AppTheme.border
                                }

                                ListView {
                                    id: listView

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: picker.viewRows
                                    boundsBehavior: Flickable.StopAtBounds
                                    activeFocusOnTab: true
                                    focus: listPane.visible
                                    keyNavigationWraps: false
                                    onCurrentIndexChanged: {
                                        if (listView.activeFocus && listView.currentIndex >= 0)
                                            picker.focusRow(listView.currentIndex);
                                    }
                                    Keys.onPressed: event => picker.handleViewKey(event)

                                    ScrollBar.vertical: ScrollBar {
                                        policy: contentHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
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
                                        id: listRow

                                        required property var modelData
                                        required property int index

                                        width: listView.width
                                        height: 34
                                        radius: AppTheme.radiusSmall
                                        color: picker.isPicked(listRow.modelData.url) ? AppTheme.layerSelected : listMouse.containsMouse || (listView.activeFocus && listView.currentIndex === listRow.index) ? AppTheme.hover : "transparent"

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 100
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 8

                                            Item {
                                                Layout.preferredWidth: 16
                                                Layout.preferredHeight: 16

                                                PickerIcons {
                                                    anchors.centerIn: parent
                                                    kind: picker.fileKind(!!listRow.modelData.isDir, String(listRow.modelData.suffix || ""))
                                                    iconColor: AppTheme.muted
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: String(listRow.modelData.fileName || "")
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                                color: AppTheme.foreground
                                            }

                                            Text {
                                                Layout.preferredWidth: 60
                                                horizontalAlignment: Text.AlignRight
                                                text: listRow.modelData.isDir ? "" : picker.sizeOf(listRow.modelData.size)
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                                color: AppTheme.muted
                                            }

                                            Text {
                                                visible: !picker.compact
                                                Layout.preferredWidth: 84
                                                text: picker.dateOf(listRow.modelData.modified)
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                                color: AppTheme.muted
                                            }

                                            Text {
                                                visible: !picker.compact
                                                Layout.preferredWidth: 54
                                                text: picker.typeLabel(listRow.modelData)
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                                color: AppTheme.muted
                                            }
                                        }

                                        MouseArea {
                                            id: listMouse

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: picker.clickRow(listView, listRow.index)
                                            onDoubleClicked: picker.activateIndex(listRow.index)
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.max(80, Math.min(parent.width - 40, 320))
                            visible: picker.viewRows.length === 0
                            spacing: 8
                            AppIcon {
                                Layout.alignment: Qt.AlignHCenter
                                width: 28
                                height: 28
                                kind: picker.readable ? "folder" : "lock"
                                iconColor: AppTheme.muted
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: picker.emptyText()
                                font.pixelSize: 12
                                color: AppTheme.muted
                            }

                            PickerButton {
                                Layout.alignment: Qt.AlignHCenter
                                visible: picker.searchText.trim() !== ""
                                label: qsTr("Clear search")
                                onClicked: picker.clearSearch()
                            }

                            PickerButton {
                                Layout.alignment: Qt.AlignHCenter
                                visible: !picker.readable && !picker.atRoot
                                label: qsTr("Go up")
                                onClicked: picker.goUp()
                            }
                        }
                    }
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

        // Footer: selected-file summary or save filename field, then
        // Cancel + primary. The summary field reads like Blender's
        // filename strip without pretending to be editable in open mode.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 46
            Layout.minimumHeight: 46
            Layout.maximumHeight: 46
            spacing: 8

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 60

                ColumnLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 2

                    PickerTextField {
                        id: nameField

                        visible: picker.saveMode
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        invalid: picker.nameError || (picker.saveMode && !picker.writable)
                        placeholderText: qsTr("File name")
                        onTextChanged: picker.nameError = false
                        onAccepted: picker.acceptSave()
                    }

                    Rectangle {
                        visible: !picker.saveMode
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: AppTheme.radiusSmall
                        color: AppTheme.background
                        border.width: 1
                        border.color: AppTheme.fieldBorder

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            text: picker.footerSummary()
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                            color: picker.pickedUrl.toString() !== "" || picker.folderMode ? AppTheme.foreground : AppTheme.muted
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: picker.footerNotice() !== ""
                        text: picker.footerNotice()
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        color: AppTheme.snapGuide
                    }
                }
            }

            PickerButton {
                Layout.alignment: Qt.AlignVCenter
                label: qsTr("Cancel")
                onClicked: picker.close()
            }

            PickerButton {
                Layout.alignment: Qt.AlignVCenter
                label: picker.primaryLabel()
                primary: true
                interactive: picker.canAccept()
                onClicked: picker.activatePrimary()
            }
        }
    }

    // Compact-mode places popup: same sections as the sidebar, in a
    // scrollable card anchored under the toolbar button.
    Popup {
        id: placesPopup

        parent: picker.contentItem
        padding: 8
        implicitWidth: 240
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: AppTheme.radiusLarge
            color: AppTheme.surface
            border.width: 1
            border.color: AppTheme.fieldBorder
        }

        contentItem: Flickable {
            id: placesFlick

            implicitWidth: 224
            implicitHeight: Math.min(360, popupNav.implicitHeight)
            contentWidth: width
            contentHeight: popupNav.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick

            ScrollBar.vertical: ScrollBar {
                policy: contentHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: AppTheme.border
                }
                background: Item {
                    implicitWidth: 6
                }
            }

            NavSections {
                id: popupNav

                width: placesFlick.width
                placesModel: picker.places
                volumesModel: picker.volumes
                recentsModel: picker.recents
                currentUrl: picker.folder.toString()
                onNavigate: url => {
                    placesPopup.close();
                    picker.go(url);
                }
            }
        }
    }

    // View options: sorting, direction, hidden files, and the active
    // suffix set (the compact stand-in for Blender's filter column).
    Popup {
        id: optionsPopup

        parent: picker.contentItem
        padding: 10
        implicitWidth: 240
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: AppTheme.radiusLarge
            color: AppTheme.surface
            border.width: 1
            border.color: AppTheme.fieldBorder
        }

        contentItem: ColumnLayout {
            spacing: 2

            Text {
                Layout.leftMargin: 8
                Layout.topMargin: 2
                text: qsTr("Sort by")
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: AppTheme.muted
            }

            MenuItem {
                label: qsTr("Name")
                checked: picker.sortKey === "name"
                onClicked: picker.setSortMode("name")
            }

            MenuItem {
                label: qsTr("Size")
                checked: picker.sortKey === "size"
                onClicked: picker.setSortMode("size")
            }

            MenuItem {
                label: qsTr("Modified")
                checked: picker.sortKey === "modified"
                onClicked: picker.setSortMode("modified")
            }

            MenuItem {
                label: qsTr("Type")
                checked: picker.sortKey === "type"
                onClicked: picker.setSortMode("type")
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                Layout.preferredHeight: 1
                color: AppTheme.border
            }

            MenuItem {
                label: qsTr("Ascending")
                checked: picker.sortAscending
                onClicked: picker.setSortDirection(true)
            }

            MenuItem {
                label: qsTr("Descending")
                checked: !picker.sortAscending
                onClicked: picker.setSortDirection(false)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                Layout.preferredHeight: 1
                color: AppTheme.border
            }

            MenuItem {
                label: qsTr("Show hidden files")
                checked: picker.showHidden
                onClicked: picker.setShowHidden(!picker.showHidden)
            }

            MenuItem {
                visible: picker.compact
                enabled: picker.writable
                label: qsTr("New folder")
                onClicked: {
                    optionsPopup.close();
                    picker.openFolderCreator();
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.topMargin: 4
                visible: picker.suffixes.length > 0
                text: qsTr("Showing %1").arg(picker.suffixLabel())
                font.pixelSize: 10
                color: AppTheme.muted
                wrapMode: Text.WordWrap
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+L"
        enabled: picker.opened
        onActivated: picker.beginPathEdit()
    }

    Shortcut {
        sequence: "Ctrl+F"
        enabled: picker.opened
        onActivated: {
            picker.pathEditing = false;
            picker.pathError = false;
            searchField.forceActiveFocus();
            searchField.selectAll();
        }
    }

    Shortcut {
        sequence: "F5"
        enabled: picker.opened
        onActivated: picker.refresh()
    }

    // --- state -------------------------------------------------------

    // Fresh state per open: land in the requested folder (or Home when
    // it is missing), restore view preferences, clear the pick, seed the
    // save-mode name field.
    function reset() {
        picker.resolved = false;
        picker.pickedUrl = "";
        picker.pickedName = "";
        picker.pendingPickUrl = "";
        picker.searchText = "";
        searchField.text = "";
        picker.pathEditing = false;
        picker.pathError = false;
        picker.creatingFolder = false;
        picker.newFolderError = "";
        picker.nameError = false;
        picker.focusIndex = -1;
        picker.rows = [];
        picker.viewRows = [];
        optionsPopup.close();
        placesPopup.close();

        var prefs = SettingsStore.fileBrowserPrefs || {};
        picker.viewMode = prefs.view === "list" ? "list" : "grid";
        picker.sortKey = picker.validSortKey(prefs.sortKey);
        picker.sortAscending = prefs.ascending === undefined ? true : !!prefs.ascending;
        picker.showHidden = !!prefs.showHidden;

        var start = picker.currentFolder;
        if (!picker.validFolder(start)) {
            var seedPlaces = FileBrowser.places();
            start = seedPlaces.length > 0 ? seedPlaces[0].url : "file:///";
        }
        picker.folder = start;
        picker.history = [String(start)];
        picker.historyIndex = 0;
        nameField.text = picker.fileName;
        SettingsStore.recordRecentFolder(String(start));
        picker.refresh();

        Qt.callLater(function () {
            if (picker.saveMode) {
                nameField.forceActiveFocus();
                picker.selectBaseName();
            } else {
                picker.focusView();
            }
        });
    }

    function refresh() {
        var keep = picker.pickedUrl.toString();
        picker.rows = FileBrowser.list(picker.folder, picker.suffixes, picker.showHidden, picker.sortKey, picker.sortAscending);
        picker.places = FileBrowser.places();
        picker.volumes = FileBrowser.volumes();
        picker.recents = picker.loadRecents();
        picker.readable = FileBrowser.isReadable(picker.folder);
        picker.writable = FileBrowser.isWritable(picker.folder);
        picker.pathText = FileBrowser.displayPath(picker.folder);
        picker.rebuildRows();

        if (picker.pendingPickUrl.toString() !== "") {
            var pending = picker.pendingPickUrl;
            picker.pendingPickUrl = "";
            picker.selectByUrl(pending, picker.saveMode);
        } else if (keep !== "") {
            picker.selectByUrl(keep, false);
        } else {
            picker.clearFocusIndex();
        }
    }

    function rebuildRows() {
        var query = picker.searchText.trim().toLowerCase();
        var out = [];
        for (var i = 0; i < picker.rows.length; i++) {
            var row = picker.rows[i];
            if (query !== "" && String(row.fileName || "").toLowerCase().indexOf(query) < 0)
                continue;
            out.push(row);
        }
        picker.viewRows = out;
        if (picker.pickedUrl.toString() !== "") {
            var pickedIndex = picker.indexOfUrl(picker.pickedUrl);
            if (pickedIndex < 0) {
                picker.pickedUrl = "";
                picker.pickedName = "";
                picker.focusIndex = -1;
            } else {
                picker.focusIndex = pickedIndex;
            }
        } else {
            picker.focusIndex = -1;
        }
        if (gridView.currentIndex !== picker.focusIndex)
            gridView.currentIndex = picker.focusIndex;
        if (listView.currentIndex !== picker.focusIndex)
            listView.currentIndex = picker.focusIndex;
    }

    function go(target, addHistory) {
        var url = String(target);
        if (url === "")
            return;
        if (!FileBrowser.isReadable(url)) {
            picker.pathError = true;
            return;
        }
        var changed = url !== String(picker.folder);
        picker.folder = url;
        if (addHistory !== false && changed) {
            if (picker.historyIndex < picker.history.length - 1)
                picker.history = picker.history.slice(0, picker.historyIndex + 1);
            picker.history.push(url);
            picker.historyIndex = picker.history.length - 1;
        }
        if (picker.searchText !== "" || searchField.text !== "") {
            picker.searchText = "";
            searchField.text = "";
        }
        picker.pickedUrl = "";
        picker.pickedName = "";
        picker.focusIndex = -1;
        picker.pathEditing = false;
        picker.pathError = false;
        picker.creatingFolder = false;
        picker.newFolderError = "";
        SettingsStore.recordRecentFolder(url);
        picker.refresh();
        picker.focusView();
    }

    function goBack() {
        if (picker.canGoBack)
            picker.goHistory(picker.historyIndex - 1);
    }

    function goForward() {
        if (picker.canGoForward)
            picker.goHistory(picker.historyIndex + 1);
    }

    function goHistory(index) {
        if (index < 0 || index >= picker.history.length || index === picker.historyIndex)
            return;
        picker.historyIndex = index;
        picker.go(picker.history[index], false);
    }

    function goUp() {
        if (picker.atRoot)
            return;
        picker.go(picker.parentFolder);
    }

    function validFolder(url) {
        return !!url && String(url) !== "" && FileBrowser.isReadable(url);
    }

    function canAccept() {
        if (picker.folderMode)
            return picker.readable;
        if (picker.saveMode)
            return picker.writable && nameField.text.trim() !== "" && !picker.nameError;
        return picker.pickedUrl.toString() !== "";
    }

    function activatePrimary() {
        if (!picker.canAccept())
            return;
        if (picker.folderMode)
            picker.acceptFolder();
        else if (picker.saveMode)
            picker.acceptSave();
        else
            picker.acceptOpen();
    }

    function acceptOpen() {
        if (picker.pickedUrl.toString() === "")
            return;
        picker.selectedFile = picker.pickedUrl;
        picker.finish();
    }

    function acceptFolder() {
        if (!picker.readable)
            return;
        picker.selectedFile = picker.folder;
        picker.finish();
    }

    function acceptSave() {
        var name = nameField.text.trim();
        if (name === "" || name === "." || name === ".." || name.indexOf("/") >= 0 || name.indexOf("\\") >= 0) {
            picker.nameError = true;
            return;
        }
        if (!picker.writable) {
            picker.nameError = true;
            return;
        }
        picker.nameError = false;
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

    function setSearch(value) {
        if (picker.searchText === value)
            return;
        picker.searchText = value;
        picker.rebuildRows();
    }

    function clearSearch() {
        searchField.text = "";
        picker.setSearch("");
        picker.focusView();
    }

    function beginPathEdit() {
        optionsPopup.close();
        placesPopup.close();
        picker.pathEditing = true;
        picker.pathError = false;
        pathField.text = picker.pathText;
        Qt.callLater(function () {
            pathField.forceActiveFocus();
            pathField.selectAll();
        });
    }

    function commitPath() {
        var target = FileBrowser.resolveTarget(pathField.text);
        if (!target.ok) {
            picker.pathError = true;
            return;
        }
        picker.pathEditing = false;
        picker.pathError = false;
        var fileUrl = target.file ? String(target.file) : "";
        if (fileUrl !== "")
            picker.pendingPickUrl = fileUrl;
        picker.go(target.folder);
        picker.focusView();
    }

    function cancelPathEdit() {
        if (!picker.pathEditing)
            return;
        picker.pathEditing = false;
        picker.pathError = false;
        picker.focusView();
    }

    function setViewMode(mode) {
        if (mode !== "grid" && mode !== "list")
            return;
        if (picker.viewMode === mode)
            return;
        picker.viewMode = mode;
        picker.savePrefs();
        picker.focusView();
    }

    function setSortMode(key) {
        if (key !== "name" && key !== "size" && key !== "modified" && key !== "type")
            return;
        if (picker.sortKey === key)
            return;
        picker.sortKey = key;
        picker.sortAscending = true;
        picker.savePrefs();
        picker.refresh();
    }

    function setSortKey(key) {
        if (key !== "name" && key !== "size" && key !== "modified" && key !== "type")
            return;
        if (picker.sortKey === key)
            picker.sortAscending = !picker.sortAscending;
        else {
            picker.sortKey = key;
            picker.sortAscending = true;
        }
        picker.savePrefs();
        picker.refresh();
    }

    function setSortDirection(ascending) {
        if (picker.sortAscending === ascending)
            return;
        picker.sortAscending = ascending;
        picker.savePrefs();
        picker.refresh();
    }

    function setShowHidden(show) {
        if (picker.showHidden === show)
            return;
        picker.showHidden = show;
        picker.savePrefs();
        picker.refresh();
    }

    function savePrefs() {
        SettingsStore.saveFileBrowserPrefs({
            "view": picker.viewMode,
            "sortKey": picker.sortKey,
            "ascending": picker.sortAscending,
            "showHidden": picker.showHidden
        });
    }

    function validSortKey(key) {
        return key === "size" || key === "modified" || key === "type" ? key : "name";
    }

    function focusRow(index) {
        if (index < 0 || index >= picker.viewRows.length)
            return;
        picker.focusIndex = index;
        var row = picker.viewRows[index];
        if (row.isDir) {
            picker.pickedUrl = "";
            picker.pickedName = "";
        } else {
            picker.pickedUrl = row.url;
            picker.pickedName = String(row.fileName);
        }
    }

    function clickRow(view, index) {
        if (index < 0 || index >= picker.viewRows.length)
            return;
        view.currentIndex = index;
        view.forceActiveFocus();
        picker.focusRow(index);
        var row = picker.viewRows[index];
        if (picker.saveMode && !row.isDir) {
            nameField.text = String(row.fileName);
            picker.nameError = false;
        }
    }

    function activateIndex(index) {
        if (index < 0 || index >= picker.viewRows.length)
            return;
        var row = picker.viewRows[index];
        if (row.isDir) {
            picker.go(row.url);
            return;
        }
        if (picker.folderMode)
            return;
        if (picker.saveMode) {
            picker.pickedUrl = row.url;
            picker.pickedName = String(row.fileName);
            nameField.text = String(row.fileName);
            picker.nameError = false;
            nameField.forceActiveFocus();
            picker.selectBaseName();
            return;
        }
        picker.pickedUrl = row.url;
        picker.selectedFile = row.url;
        picker.finish();
    }

    function focusView() {
        Qt.callLater(function () {
            if (picker.viewMode === "grid") {
                if (gridView.currentIndex !== picker.focusIndex)
                    gridView.currentIndex = picker.focusIndex;
                gridView.forceActiveFocus();
            } else {
                if (listView.currentIndex !== picker.focusIndex)
                    listView.currentIndex = picker.focusIndex;
                listView.forceActiveFocus();
            }
        });
    }

    function clearFocusIndex() {
        picker.focusIndex = -1;
        gridView.currentIndex = -1;
        listView.currentIndex = -1;
    }

    function indexOfUrl(url) {
        for (var i = 0; i < picker.viewRows.length; i++) {
            if (String(picker.viewRows[i].url) === String(url))
                return i;
        }
        return -1;
    }

    function selectByUrl(url, seedName) {
        var index = picker.indexOfUrl(url);
        if (index < 0) {
            picker.clearFocusIndex();
            picker.pickedUrl = "";
            picker.pickedName = "";
            return;
        }
        var row = picker.viewRows[index];
        picker.focusIndex = index;
        picker.pickedUrl = row.url;
        picker.pickedName = String(row.fileName);
        gridView.currentIndex = index;
        listView.currentIndex = index;
        if (seedName && !row.isDir) {
            nameField.text = String(row.fileName);
            picker.nameError = false;
            picker.selectBaseName();
        }
    }

    function rowByUrl(url) {
        for (var i = 0; i < picker.viewRows.length; i++) {
            if (String(picker.viewRows[i].url) === String(url))
                return picker.viewRows[i];
        }
        return null;
    }

    function isPicked(url) {
        return picker.pickedUrl.toString() !== "" && String(url) === picker.pickedUrl.toString();
    }

    function selectBaseName() {
        var text = nameField.text;
        var dot = text.lastIndexOf(".");
        var count = dot > 0 ? dot : text.length;
        nameField.select(0, count);
    }

    function handleViewKey(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var view = picker.viewMode === "grid" ? gridView : listView;
            if (view.currentIndex < 0 && picker.viewRows.length > 0) {
                view.currentIndex = 0;
                picker.focusRow(0);
            }
            picker.activateIndex(view.currentIndex);
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            picker.goUp();
            event.accepted = true;
        } else if (event.key === Qt.Key_F5) {
            picker.refresh();
            event.accepted = true;
        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Left) {
            picker.goBack();
            event.accepted = true;
        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Right) {
            picker.goForward();
            event.accepted = true;
        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Up) {
            picker.goUp();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && picker.searchText !== "") {
            picker.clearSearch();
            event.accepted = true;
        }
    }

    function openOptions(anchor) {
        if (optionsPopup.opened) {
            optionsPopup.close();
            return;
        }
        picker.openMenu(optionsPopup, anchor, true);
    }

    function openPlaces(anchor) {
        if (placesPopup.opened) {
            placesPopup.close();
            return;
        }
        picker.openMenu(placesPopup, anchor, false);
    }

    function openMenu(popup, anchor, alignRight) {
        var content = picker.contentItem;
        if (!content || !anchor)
            return;
        var point = anchor.mapToItem(content, 0, anchor.height + 6);
        var width = popup.implicitWidth;
        var height = popup.implicitHeight;
        var x = alignRight ? point.x + anchor.width - width : point.x;
        popup.x = Math.max(8, Math.min(x, content.width - width - 8));
        popup.y = Math.max(8, Math.min(point.y, content.height - height - 8));
        popup.open();
    }

    function openFolderCreator() {
        if (!picker.writable)
            return;
        optionsPopup.close();
        placesPopup.close();
        picker.creatingFolder = true;
        picker.newFolderError = "";
        newFolderField.text = picker.uniqueFolderName();
        Qt.callLater(function () {
            newFolderField.forceActiveFocus();
            newFolderField.selectAll();
        });
    }

    function commitNewFolder() {
        var name = newFolderField.text.trim();
        var result = FileBrowser.createFolder(picker.folder, name);
        if (!result.ok) {
            picker.newFolderError = String(result.error || qsTr("Could not create the folder."));
            return;
        }
        picker.creatingFolder = false;
        picker.newFolderError = "";
        picker.go(result.url);
    }

    function cancelNewFolder() {
        picker.creatingFolder = false;
        picker.newFolderError = "";
        picker.focusView();
    }

    function uniqueFolderName() {
        var base = qsTr("New Folder");
        var name = base;
        var number = 2;
        while (picker.hasDirName(name)) {
            name = base + " " + number;
            number++;
        }
        return name;
    }

    function hasDirName(name) {
        for (var i = 0; i < picker.rows.length; i++) {
            if (picker.rows[i].isDir && String(picker.rows[i].fileName) === name)
                return true;
        }
        return false;
    }

    function loadRecents() {
        var out = [];
        var stored = SettingsStore.recentFolders;
        for (var i = 0; i < stored.length; i++) {
            var url = String(stored[i]);
            if (!FileBrowser.isReadable(url))
                continue;
            var crumbs = FileBrowser.breadcrumbs(url);
            var name = crumbs.length > 0 ? String(crumbs[crumbs.length - 1].name) : url;
            out.push({
                "url": url,
                "name": name,
                "detail": FileBrowser.displayPath(url)
            });
        }
        return out;
    }

    function footerSummary() {
        if (picker.folderMode)
            return qsTr("Current folder · %1 items").arg(picker.viewRows.length);
        if (picker.pickedUrl.toString() !== "") {
            var row = picker.rowByUrl(picker.pickedUrl);
            if (row)
                return String(row.fileName) + " · " + picker.sizeOf(row.size);
            if (picker.pickedName !== "")
                return picker.pickedName;
        }
        return qsTr("%1 items").arg(picker.viewRows.length);
    }

    function footerNotice() {
        if (!picker.saveMode)
            return "";
        if (!picker.writable)
            return qsTr("This folder is read-only.");
        if (picker.nameError)
            return qsTr("Enter a valid file name.");
        return "";
    }

    function primaryLabel() {
        if (picker.folderMode)
            return qsTr("Use this folder");
        if (picker.saveMode)
            return qsTr("Save");
        return qsTr("Open");
    }

    function emptyText() {
        if (!picker.readable)
            return qsTr("Can't open this folder");
        if (picker.searchText.trim() !== "")
            return qsTr("No files match “%1”.").arg(picker.searchText.trim());
        if (picker.suffixes.length > 0)
            return qsTr("No matching files here.");
        return qsTr("Nothing to see here...");
    }

    function suffixLabel() {
        var parts = [];
        for (var i = 0; i < picker.suffixes.length; i++)
            parts.push(String(picker.suffixes[i]).toUpperCase());
        return parts.join(" · ");
    }

    function sortHeaderLabel(label, key) {
        if (picker.sortKey !== key)
            return label;
        return label + (picker.sortAscending ? "  ↑" : "  ↓");
    }

    function tileTooltip(row) {
        if (!row)
            return "";
        if (row.isDir)
            return String(row.fileName) + "\n" + qsTr("Folder");
        return String(row.fileName) + "\n" + picker.sizeOf(row.size) + " · " + picker.dateOf(row.modified);
    }

    function fileKind(isDir, suffix) {
        if (isDir)
            return "folder";
        if (picker.audioSuffixes.indexOf(suffix) >= 0)
            return "music";
        if (picker.imageSuffixes.indexOf(suffix) >= 0)
            return "image";
        if (picker.videoSuffixes.indexOf(suffix) >= 0)
            return "film";
        return "file";
    }

    function typeLabel(row) {
        if (row.isDir)
            return qsTr("Folder");
        var suffix = String(row.suffix || "").toUpperCase();
        return suffix !== "" ? suffix : qsTr("File");
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

    // --- inline components -------------------------------------------

    component PickerTextField: TextField {
        id: field

        property bool invalid: false

        implicitHeight: 28
        font.pixelSize: 12
        color: AppTheme.foreground
        placeholderTextColor: AppTheme.muted
        selectionColor: AppTheme.selection
        selectedTextColor: "#ffffff"
        selectByMouse: true
        leftPadding: 8
        rightPadding: 8
        topPadding: 5
        bottomPadding: 5

        background: Rectangle {
            radius: AppTheme.radiusSmall
            color: AppTheme.background
            border.width: 1
            border.color: field.invalid ? AppTheme.snapGuide : field.activeFocus ? AppTheme.selection : AppTheme.fieldBorder
        }
    }

    component IconButton: Rectangle {
        id: button

        property string iconKind: "close"
        property string tooltip: ""
        property bool active: false
        property bool interactive: true

        signal clicked

        implicitWidth: 28
        implicitHeight: 28
        radius: AppTheme.radiusSmall
        color: button.active ? AppTheme.layerSelected : button.interactive && (buttonMouse.containsMouse || buttonMouse.pressed) ? AppTheme.hover : "transparent"
        opacity: button.interactive ? 1 : 0.35

        Behavior on color {
            ColorAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }

        AppIcon {
            anchors.centerIn: parent
            width: 14
            height: 14
            kind: button.iconKind
            iconColor: button.active || buttonMouse.containsMouse ? AppTheme.foreground : AppTheme.muted
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            enabled: button.interactive
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: button.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: button.clicked()
        }

        ToolTip.visible: button.interactive && button.tooltip !== "" && buttonMouse.containsMouse
        ToolTip.text: button.tooltip
        ToolTip.delay: 500
    }

    component PickerButton: Rectangle {
        id: button

        property string label: ""
        property bool primary: false
        property bool interactive: true

        signal clicked

        implicitWidth: Math.max(90, buttonText.implicitWidth + 28)
        implicitHeight: 32
        radius: AppTheme.radiusSmall
        border.width: 1
        border.color: button.primary ? (button.interactive ? AppTheme.foreground : AppTheme.fieldBorder) : AppTheme.fieldBorder
        color: button.primary ? (button.interactive ? AppTheme.foreground : AppTheme.surface) : buttonMouse.containsMouse || buttonMouse.pressed ? AppTheme.hover : AppTheme.surface
        opacity: button.interactive ? 1 : 0.4

        Behavior on color {
            ColorAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }

        Text {
            id: buttonText

            anchors.centerIn: parent
            text: button.label
            font.pixelSize: 12
            font.weight: button.primary ? Font.DemiBold : Font.Normal
            color: button.primary ? (button.interactive ? AppTheme.background : AppTheme.muted) : buttonMouse.containsMouse || buttonMouse.pressed ? AppTheme.foreground : AppTheme.muted
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            enabled: button.interactive
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: button.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: button.clicked()
        }
    }

    component NavRow: Rectangle {
        id: row

        property string label: ""
        property string iconKind: "folder"
        property string detail: ""
        property bool active: false

        signal clicked

        Layout.fillWidth: true
        Layout.preferredHeight: 30
        radius: AppTheme.radiusSmall
        color: row.active ? AppTheme.layerSelected : rowMouse.containsMouse || rowMouse.pressed ? AppTheme.hover : "transparent"

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

            AppIcon {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                kind: row.iconKind
                iconColor: row.active || rowMouse.containsMouse ? AppTheme.foreground : AppTheme.muted
            }

            Text {
                Layout.fillWidth: true
                text: row.label
                font.pixelSize: 11
                elide: Text.ElideRight
                color: AppTheme.foreground
            }
        }

        MouseArea {
            id: rowMouse

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }

        ToolTip.visible: rowMouse.containsMouse && row.detail !== ""
        ToolTip.text: row.detail
        ToolTip.delay: 600
    }

    component NavSections: ColumnLayout {
        id: sections

        property var placesModel: []
        property var volumesModel: []
        property var recentsModel: []
        property string currentUrl: ""

        signal navigate(string url)

        spacing: 1

        function sameFolder(url) {
            return sections.currentUrl !== "" && FileBrowser.displayPath(url) === FileBrowser.displayPath(sections.currentUrl);
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

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.topMargin: 8
            Layout.bottomMargin: 2
            text: qsTr("Places")
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
            color: AppTheme.muted
        }

        Repeater {
            model: sections.placesModel

            NavRow {
                label: String(modelData.name)
                iconKind: sections.placeKind(String(modelData.id))
                active: sections.sameFolder(modelData.url)
                onClicked: sections.navigate(String(modelData.url))
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.topMargin: 8
            Layout.bottomMargin: 2
            visible: sections.volumesModel.length > 0
            text: qsTr("Volumes")
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
            color: AppTheme.muted
        }

        Repeater {
            model: sections.volumesModel

            NavRow {
                label: String(modelData.name)
                iconKind: "drive"
                detail: String(modelData.detail || "")
                active: sections.sameFolder(modelData.url)
                onClicked: sections.navigate(String(modelData.url))
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.topMargin: 8
            Layout.bottomMargin: 2
            visible: sections.recentsModel.length > 0
            text: qsTr("Recent")
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
            color: AppTheme.muted
        }

        Repeater {
            model: sections.recentsModel

            NavRow {
                label: String(modelData.name)
                iconKind: "clock"
                detail: String(modelData.detail || "")
                active: sections.sameFolder(modelData.url)
                onClicked: sections.navigate(String(modelData.url))
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
        }
    }
}
