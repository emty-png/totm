import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

ApplicationWindow {
    id: root
    visible: true
    width: 900
    height: 640
    minimumWidth: 480
    minimumHeight: 360
    title: qsTr("totm")

    flags: Qt.Window | Qt.FramelessWindowHint
    color: AppTheme.background

    onClosing: {
        root.saveWindowNow();
        TabState.saveAllOpen();
    }

    Component.onCompleted: {
        root.restoreWindow();
        PluginStore.scan();
        // File association: import .totm bundles passed on the command
        // line (double-click / Open With) into the default workspace and
        // open each in its own tab. Failures surface in the error bar.
        if (typeof totmOpenFiles !== "undefined")
            root.openTotmFiles(totmOpenFiles);
    }

    // Shared by launch args and the single-instance signal below.
    function openTotmFiles(urls) {
        var list = urls || [];
        if (list.length === 0)
            return;
        var ws = LibraryStore.defaultWorkspaceId;
        for (var i = 0; i < list.length; i++) {
            var id = LibraryStore.importDesign(ws, list[i]);
            if (id)
                TabState.openDesign(id);
        }
    }

    // Single-instance forwards: later .totm opens land in this window
    // (imported like launch args) and raise it. Empty means raise-only.
    Connections {
        target: totmSingleInstance
        function onFilesRequested(urls) {
            root.openTotmFiles(urls || []);
            root.raise();
            root.requestActivate();
        }
    }

    // Effective tab position: with the top bar hidden, Top tabs fall
    // back to the bottom rail so tab switching stays reachable.
    readonly property string effectiveTabPosition: (!SettingsStore.showTopBar && SettingsStore.tabPosition === "top") ? "bottom" : SettingsStore.tabPosition

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TitleBar {
            visible: SettingsStore.showTopBar
            Layout.fillWidth: true
            Layout.preferredHeight: 45
            window: root
            showTabs: root.effectiveTabPosition === "top"
        }

        // Library/persistence errors. Hidden when clear; dismiss calls
        // back into the store so the next error can surface again.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            visible: LibraryStore.lastError !== ""
            color: AppTheme.surface

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: 1
                color: AppTheme.border
            }

            Text {
                anchors {
                    left: parent.left
                    right: dismissButton.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 8
                }
                text: LibraryStore.lastError
                font.pixelSize: 12
                color: AppTheme.foreground
                elide: Text.ElideRight
            }

            Item {
                id: dismissButton

                anchors {
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                width: 32

                AppIcon {
                    anchors.centerIn: parent
                    kind: "close"
                    width: 12
                    height: 12
                    iconColor: dismissMouse.containsMouse ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: dismissMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LibraryStore.clearError()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Left vertical tab rail.
            Rectangle {
                visible: root.effectiveTabPosition === "left"
                Layout.preferredWidth: SettingsStore.tabRailCollapsed ? 52 : 192
                Layout.fillHeight: true
                color: AppTheme.surface

                Rectangle {
                    anchors {
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: 1
                    color: AppTheme.border
                }

                VerticalTabBar {
                    anchors.fill: parent
                    collapsed: SettingsStore.tabRailCollapsed
                    side: "left"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Home tab content
                HomeView {
                    visible: TabState.isHomeSelected
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                // Document tab content
                EditorView {
                    id: editorView

                    visible: !TabState.isHomeSelected
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    externalDrop: dropIntake
                }
            }

            // Right vertical tab rail.
            Rectangle {
                visible: root.effectiveTabPosition === "right"
                Layout.preferredWidth: SettingsStore.tabRailCollapsed ? 52 : 192
                Layout.fillHeight: true
                color: AppTheme.surface

                Rectangle {
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: 1
                    color: AppTheme.border
                }

                VerticalTabBar {
                    anchors.fill: parent
                    collapsed: SettingsStore.tabRailCollapsed
                    side: "right"
                }
            }
        }

        // Bottom horizontal tab bar. Reuses the top tab cluster with a
        // top-border blend cover under the active tab.
        Item {
            visible: root.effectiveTabPosition === "bottom"
            Layout.fillWidth: true
            Layout.preferredHeight: 45

            Column {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: 1
                    color: AppTheme.border
                }

                Rectangle {
                    width: parent.width
                    height: 44
                    color: AppTheme.surface

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0

                        TitleBarTabBar {
                            id: bottomTabBar
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                        }
                    }
                }
            }

            Rectangle {
                x: bottomTabBar.x + bottomTabBar.activeX
                y: 0
                width: bottomTabBar.activeWidth
                height: 1
                color: AppTheme.background
            }
        }
    }

    // OS-level image intake over the whole editor window (drops map
    // onto the canvas; paste is wired through EditorShortcuts). Lives
    // outside the layouts: anchored items inside one are undefined
    // behavior.
    ExternalDropArea {
        id: dropIntake

        anchors.fill: parent
        windowActive: !TabState.isHomeSelected
        canvas: editorView.canvas
        doc: TabState.documentFor(TabState.currentIndex)
    }

    WindowResizeHandles {
        window: root
    }

    // Advanced-tier plugin overlays: full-window layer above both views.
    // Standard slots live in the toolbar and design panel; only plugins
    // with ui.fullOverlay granted appear here.
    Item {
        id: pluginOverlayHost

        anchors.fill: parent
        z: 10

        Repeater {
            model: PluginStore.fullOverlays()

            delegate: Loader {
                property var entry: modelData

                anchors.fill: parent
                active: true
                asynchronous: true
                source: entry.url

                onLoaded: {
                    if (item && "pluginId" in item)
                        item.pluginId = entry.pluginId;
                }
            }
        }
    }

    PluginPermissionPopup {
        onAllow: function (granted) {
            PluginStore.grantPending(granted);
        }
        onDeny: PluginStore.dismissPending()
    }

    // Trusted host picker: opens system dialogs for plugin media
    // requests and imports through LibraryStore. Invisible.
    PluginFilePicker {}

    // Window state: geometry + maximized persist via SettingsStore
    // (native QSettings). Restores once on launch; saves debounced on
    // move/resize/visibility so drags write once, plus synchronously
    // on close. Maximized saves only the flag — the normal rect is
    // kept so unmaximize restores the real size (C++ enforces this).
    function restoreWindow() {
        var g = SettingsStore.windowGeometry();
        if (!g.hasGeometry)
            return;
        root.x = g.x;
        root.y = g.y;
        root.width = g.width;
        root.height = g.height;
        if (g.maximized)
            root.showMaximized();
    }

    function saveWindowNow() {
        SettingsStore.saveWindowGeometry(root.x, root.y, root.width, root.height, root.visibility === Window.Maximized);
    }

    onXChanged: saveWindowTimer.restart()
    onYChanged: saveWindowTimer.restart()
    onWidthChanged: saveWindowTimer.restart()
    onHeightChanged: saveWindowTimer.restart()
    onVisibilityChanged: saveWindowTimer.restart()

    Timer {
        id: saveWindowTimer

        interval: 500
        onTriggered: root.saveWindowNow()
    }
}
