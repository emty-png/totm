import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Plugin permission approval: clean centered modal shown when a plugin
// is first discovered. Lists every requested permission with the maker's
// reason; the user can untick anything, with a may-break warning.
Popup {
    id: permissionPopup

    property var pending: PluginStore.pendingPlugin
    property var toggles: ({})

    signal allow(var granted)
    signal deny

    function refreshToggles() {
        var next = {};
        var rows = permissionPopup.pending && permissionPopup.pending.requested ? permissionPopup.pending.requested : [];
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            next[row.id] = row.granted !== false;
        }
        permissionPopup.toggles = next;
    }

    function grantedList() {
        var out = [];
        var rows = permissionPopup.pending && permissionPopup.pending.requested ? permissionPopup.pending.requested : [];
        for (var i = 0; i < rows.length; i++) {
            if (permissionPopup.toggles[rows[i].id] !== false)
                out.push(rows[i].id);
        }
        return out;
    }

    function togglePermission(permissionId) {
        var next = Object.assign({}, permissionPopup.toggles);
        next[permissionId] = next[permissionId] === false;
        permissionPopup.toggles = next;
    }

    anchors.centerIn: parent
    implicitWidth: 440
    padding: 12
    modal: true
    dim: true
    closePolicy: Popup.NoAutoClose
    visible: permissionPopup.pending && permissionPopup.pending.id !== undefined && permissionPopup.pending.id !== ""

    onPendingChanged: permissionPopup.refreshToggles()
    Component.onCompleted: permissionPopup.refreshToggles()

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

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: qsTr("Allow \"%1\"?").arg(permissionPopup.pending ? (permissionPopup.pending.name || "") : "")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: AppTheme.foreground
                elide: Text.ElideRight
            }

            OfficialBadge {
                Layout.alignment: Qt.AlignVCenter
                visible: !!(permissionPopup.pending && permissionPopup.pending.official)
                badgeSize: 16

                ToolTip.visible: sealMouse.containsMouse
                ToolTip.text: qsTr("Official plugin — shipped with totm.")

                MouseArea {
                    id: sealMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: AppTheme.border
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            visible: !!(permissionPopup.pending && permissionPopup.pending.requested && permissionPopup.pending.requested.length > 0)

            Repeater {
                id: permissionRows

                model: permissionPopup.pending && permissionPopup.pending.requested ? permissionPopup.pending.requested : []

                onItemAdded: (index, item) => {
                    // Delegate-safe: policies assigned where outer scope
                    // is visible, like LayersView/TimelineView.
                    item.togglePolicy = permissionId => permissionPopup.togglePermission(permissionId);
                }

                delegate: PluginPermissionRow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    entry: modelData
                    checked: permissionPopup.toggles[modelData.id] !== false
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: permissionPopup.pending && permissionPopup.pending.tier === "advanced"
            text: qsTr("Advanced plugin: can draw over the whole editor. Only allow plugins you trust.")
            font.pixelSize: 11
            color: AppTheme.muted
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.fieldBorder
                color: denyMouse.containsMouse || denyMouse.pressed ? AppTheme.hover : AppTheme.surface

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Deny")
                    font.pixelSize: 12
                    color: denyMouse.containsMouse || denyMouse.pressed ? AppTheme.foreground : AppTheme.muted
                }

                MouseArea {
                    id: denyMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: permissionPopup.deny()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: AppTheme.radiusSmall
                border.width: 1
                border.color: AppTheme.foreground
                color: AppTheme.foreground

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Allow")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: AppTheme.background
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: permissionPopup.allow(permissionPopup.grantedList())
                }
            }
        }
    }
}
