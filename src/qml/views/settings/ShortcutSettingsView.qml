import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Shortcut settings panel: centered card list of editable shortcuts.
// Click a badge to capture (Esc cancels, duplicates blocked with a
// notice), per-row undo resets one, header resets all. Bindings read
// ShortcutState live so remaps apply instantly to editor/home.
ColumnLayout {
    id: shortcutPanel

    spacing: 0

    property string filter: ""
    property string notice: ""
    property var groups: ShortcutState.shortcutGroups()
    property int customCount: Object.keys(SettingsStore.shortcutOverrides).length
    // Header/notice share the cards' centered 640px rhythm: wide windows
    // grow the side margins, narrow ones clamp at 16px.
    property real centerMargin: Math.max(16, (shortcutPanel.width - 640) / 2)

    function filteredGroups() {
        var f = shortcutPanel.filter.trim().toLowerCase();
        var src = shortcutPanel.groups;
        if (f === "")
            return src;
        var out = [];
        for (var gi = 0; gi < src.length; gi++) {
            var items = [];
            var groupItems = src[gi].items;
            for (var ii = 0; ii < groupItems.length; ii++) {
                var it = groupItems[ii];
                if (it.label.toLowerCase().indexOf(f) >= 0 || it.sequence.toLowerCase().indexOf(f) >= 0)
                    items.push(it);
            }
            if (items.length > 0)
                out.push({
                    title: src[gi].title,
                    items: items
                });
        }
        return out;
    }

    function startCapture(id) {
        if (ShortcutState.capturing && ShortcutState.capturingId === id) {
            shortcutPanel.cancelCapture();
            return;
        }
        shortcutPanel.notice = "";
        searchField.focus = false;
        ShortcutState.capturingId = id;
        ShortcutState.capturing = true;
        captureKeys.forceActiveFocus();
    }

    function cancelCapture() {
        ShortcutState.capturing = false;
        ShortcutState.capturingId = "";
    }

    function handleKey(event) {
        if (!ShortcutState.capturing)
            return;
        if (event.key === Qt.Key_Escape) {
            shortcutPanel.notice = "";
            shortcutPanel.cancelCapture();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta || event.key === Qt.Key_AltGr || event.key === Qt.Key_CapsLock || event.key === Qt.Key_NumLock || event.key === Qt.Key_ScrollLock)
            return;
        var name = shortcutPanel.keyNameFor(event);
        if (name === "")
            return;
        var mods = "";
        if (event.modifiers & Qt.ControlModifier)
            mods += "Ctrl+";
        if (event.modifiers & Qt.AltModifier)
            mods += "Alt+";
        if (event.modifiers & Qt.ShiftModifier)
            mods += "Shift+";
        if (event.modifiers & Qt.MetaModifier)
            mods += "Meta+";
        var seq = mods + name;
        var id = ShortcutState.capturingId;
        var conflict = ShortcutState.trySetSequence(id, seq);
        if (conflict === "") {
            shortcutPanel.notice = "";
            shortcutPanel.cancelCapture();
        } else if (conflict === "invalid") {
            shortcutPanel.notice = qsTr("Invalid shortcut — press Esc to cancel.");
        } else {
            shortcutPanel.notice = qsTr("Already used by “%1” — press Esc to cancel.").arg(ShortcutState.labelFor(conflict));
        }
        event.accepted = true;
    }

    function keyNameFor(event) {
        var k = event.key;
        if (k >= Qt.Key_A && k <= Qt.Key_Z)
            return String.fromCharCode(k);
        if (k >= Qt.Key_0 && k <= Qt.Key_9)
            return String.fromCharCode(k);
        if (k >= Qt.Key_F1 && k <= Qt.Key_F35)
            return "F" + (k - Qt.Key_F1 + 1);
        switch (k) {
        case Qt.Key_Left:
            return "Left";
        case Qt.Key_Right:
            return "Right";
        case Qt.Key_Up:
            return "Up";
        case Qt.Key_Down:
            return "Down";
        case Qt.Key_Space:
            return "Space";
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            return "Tab";
        case Qt.Key_Return:
            return "Return";
        case Qt.Key_Enter:
            return "Enter";
        case Qt.Key_Backspace:
            return "Backspace";
        case Qt.Key_Delete:
            return "Delete";
        case Qt.Key_Home:
            return "Home";
        case Qt.Key_End:
            return "End";
        case Qt.Key_PageUp:
            return "PageUp";
        case Qt.Key_PageDown:
            return "PageDown";
        case Qt.Key_Insert:
            return "Insert";
        case Qt.Key_BracketLeft:
            return "[";
        case Qt.Key_BracketRight:
            return "]";
        case Qt.Key_Slash:
            return "/";
        case Qt.Key_Minus:
            return "-";
        case Qt.Key_Equal:
            return "=";
        case Qt.Key_Comma:
            return ",";
        case Qt.Key_Period:
            return ".";
        case Qt.Key_Semicolon:
            return ";";
        case Qt.Key_Apostrophe:
            return "'";
        case Qt.Key_Backslash:
            return "\\";
        default:
            break;
        }
        var t = event.text;
        if (t && t.length === 1 && t.charCodeAt(0) >= 0x20)
            return t.toUpperCase();
        return "";
    }

    onVisibleChanged: {
        if (!shortcutPanel.visible)
            shortcutPanel.cancelCapture();
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: shortcutPanel.centerMargin
        Layout.rightMargin: shortcutPanel.centerMargin
        Layout.topMargin: 12
        Layout.bottomMargin: 8
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Shortcuts")
            font.pixelSize: 16
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        TextField {
            id: searchField

            Layout.preferredWidth: 200
            implicitHeight: 28
            placeholderText: qsTr("Search")
            placeholderTextColor: AppTheme.muted
            font.pixelSize: 12
            color: AppTheme.foreground
            selectByMouse: true
            text: shortcutPanel.filter
            onTextChanged: shortcutPanel.filter = text

            background: Rectangle {
                radius: AppTheme.radiusSmall
                color: AppTheme.surface
                border.width: 1
                border.color: searchField.activeFocus ? AppTheme.selection : AppTheme.fieldBorder
            }

            // Focusing search mid-capture aborts it; Esc also cancels.
            onActiveFocusChanged: {
                if (searchField.activeFocus && ShortcutState.capturing)
                    shortcutPanel.cancelCapture();
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape && ShortcutState.capturing) {
                    shortcutPanel.cancelCapture();
                    event.accepted = true;
                }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: resetText.implicitWidth + 20
            implicitHeight: 28
            radius: AppTheme.radiusSmall
            border.width: 1
            border.color: resetMouse.containsMouse ? AppTheme.foreground : AppTheme.fieldBorder
            color: resetMouse.pressed ? AppTheme.pressed : resetMouse.containsMouse ? AppTheme.hover : AppTheme.surface
            opacity: shortcutPanel.customCount > 0 ? 1 : 0.4

            Behavior on color {
                ColorAnimation {
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                id: resetText

                anchors.centerIn: parent
                text: qsTr("Reset all")
                font.pixelSize: 12
                color: AppTheme.foreground
            }

            MouseArea {
                id: resetMouse

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: shortcutPanel.customCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (shortcutPanel.customCount > 0)
                        ShortcutState.resetAll();
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: shortcutPanel.centerMargin
        Layout.rightMargin: shortcutPanel.centerMargin
        Layout.bottomMargin: 4
        visible: shortcutPanel.notice !== ""
        wrapMode: Text.WordWrap
        text: shortcutPanel.notice
        font.pixelSize: 12
        color: AppTheme.snapGuide
    }

    ScrollView {
        id: shortcutScroll

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: Math.min(640, shortcutScroll.availableWidth - 32)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Repeater {
                model: shortcutPanel.filteredGroups()

                delegate: Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: cardBody.implicitHeight + 24
                    radius: AppTheme.radiusLarge
                    border.width: 1
                    border.color: AppTheme.border
                    color: AppTheme.surface

                    // Named copy: inner delegates read rows via cardItems[index]
                    // (number model), never nested modelData.
                    property var cardItems: modelData.items

                    ColumnLayout {
                        id: cardBody

                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            text: modelData.title
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            color: AppTheme.foreground
                        }

                        Repeater {
                            model: cardItems.length

                            // Row data travels via onItemAdded: the index arrives
                            // as a plain argument, avoiding nested-Repeater
                            // index/modelData context (which does not reach
                            // custom-component delegates). Same policy-callback
                            // rule as LayersView/TitleBarTabBar/Plugin rows.
                            onItemAdded: (idx, r) => {
                                var d = cardItems[idx];
                                if (!d)
                                    return;
                                r.actionId = d.id;
                                r.capturePolicy = rid => shortcutPanel.startCapture(rid);
                                r.resetPolicy = rid => ShortcutState.resetOne(rid);
                            }

                            delegate: ShortcutRow {
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 16
                visible: shortcutPanel.filteredGroups().length === 0
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("No shortcuts match…")
                font.pixelSize: 13
                color: AppTheme.muted
            }
        }
    }

    // Invisible key sink. Takes focus only for the duration of a capture
    // (see startCapture), so merely opening the tab never steals focus
    // from home/editor. Hiding the panel cancels via onVisibleChanged.
    Item {
        id: captureKeys

        Keys.onPressed: event => shortcutPanel.handleKey(event)
    }
}
