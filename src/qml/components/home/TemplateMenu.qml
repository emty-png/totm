import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Totm

// Template picker: centered modal with a rendered scene preview per
// starter template. Opens from the header Template button; picking
// builds a new design through usePolicy (HomeView.homeNewFromTemplate)
// and closes. Previews build once on first open from the same
// one-undo-entry builders, so tiles match what a new design opens with.
Popup {
    id: menu

    property var templateLib: null
    property var usePolicy: null

    // Preview scenes by template id. Reassigned wholesale so card
    // bindings update; temp documents are destroyed after snapshotting.
    property var scenes: ({})

    readonly property Component documentFactory: Component {
        Document {}
    }

    anchors.centerIn: parent
    implicitWidth: 380
    padding: 12
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Previews build lazily here (not onOpened) so the first paint
    // already carries them and the popup never jumps size after opening.
    function openPicker() {
        menu.ensurePreviews();
        menu.open();
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

        Text {
            Layout.fillWidth: true
            text: qsTr("Start from a template")
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: AppTheme.foreground
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: menu.templateLib ? menu.templateLib.templates() : []

                TemplateCard {
                    templateId: modelData.id
                    templateName: modelData.name
                    blurb: modelData.blurb
                    scene: menu.scenes[modelData.id] ?? null
                    usePolicy: id => {
                        menu.close();
                        if (menu.usePolicy)
                            menu.usePolicy(id);
                    }
                }
            }
        }
    }

    // Builds each missing preview in a throwaway document (never in a
    // tab, never saved): build, snapshot the base scene, destroy. A
    // failed build keeps its text-only tile instead of blocking the rest.
    function ensurePreviews() {
        if (!menu.templateLib)
            return;
        var all = menu.templateLib.templates();
        var next = Object.assign({}, menu.scenes);
        var added = false;
        for (var i = 0; i < all.length; i++) {
            var id = all[i].id;
            if (next[id] !== undefined)
                continue;
            var doc = menu.documentFactory.createObject(menu);
            if (!doc)
                continue;
            if (menu.templateLib.build(doc, id))
                next[id] = doc.snapshotScene();
            doc.destroy();
            if (next[id] !== undefined)
                added = true;
        }
        if (added)
            menu.scenes = next;
    }
}
