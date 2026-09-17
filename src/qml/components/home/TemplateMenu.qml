import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Template picker: centered modal listing every starter template.
// Opens from the header Template button; picking builds a new design
// through usePolicy (HomeView.homeNewFromTemplate) and closes.
Popup {
    id: menu

    property var templateLib: null
    property var usePolicy: null

    anchors.centerIn: parent
    implicitWidth: 300
    padding: 12
    modal: true
    dim: true
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
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: qsTr("Start from a template")
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        Repeater {
            model: menu.templateLib ? menu.templateLib.templates() : []

            TemplateCard {
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                templateId: modelData.id
                templateName: modelData.name
                blurb: modelData.blurb
                usePolicy: id => {
                    menu.close();
                    if (menu.usePolicy)
                        menu.usePolicy(id);
                }
            }
        }
    }
}
