pragma Singleton
import QtQuick
import Totm

// Central shortcut registry. Sequences are the single source of truth:
// editor/home Shortcut items bind here, the Shortcut tab lists from
// shortcutGroups(). Editable: writes go through SettingsStore (native
// QSettings, group "shortcuts/") so they persist across restarts.
// QML properties bind to shortcutOverrides so resets flow back live.
QtObject {
    id: shortcutState

    // While true, editor/home Shortcuts disable so a capture press
    // reaches the settings capture item instead of triggering work.
    property bool capturing: false
    property string capturingId: ""

    // Home.
    property string homeNew: SettingsStore.shortcutOverrides["homeNew"] || "Ctrl+N"
    // Main Return key ("Return" in portable text; the keypad key is the
    // separate "Enter" and stays a fixed alias at the call site).
    property string homeOpen: SettingsStore.shortcutOverrides["homeOpen"] || "Return"
    property string homeRename: SettingsStore.shortcutOverrides["homeRename"] || "F2"
    property string homeDelete: SettingsStore.shortcutOverrides["homeDelete"] || "Delete"
    property string homeDuplicate: SettingsStore.shortcutOverrides["homeDuplicate"] || "Ctrl+D"
    property string homeStar: SettingsStore.shortcutOverrides["homeStar"] || "S"

    // Canvas tools (single letters, editor only so S never hits home star).
    property string toolSelect: SettingsStore.shortcutOverrides["toolSelect"] || "V"
    property string toolRect: SettingsStore.shortcutOverrides["toolRect"] || "R"
    property string toolEllipse: SettingsStore.shortcutOverrides["toolEllipse"] || "E"
    property string toolTriangle: SettingsStore.shortcutOverrides["toolTriangle"] || "T"
    property string toolStar: SettingsStore.shortcutOverrides["toolStar"] || "S"
    property string toolPen: SettingsStore.shortcutOverrides["toolPen"] || "P"
    property string toolText: SettingsStore.shortcutOverrides["toolText"] || "X"
    property string toolImage: SettingsStore.shortcutOverrides["toolImage"] || "I"

    // Canvas edits.
    property string editUndo: SettingsStore.shortcutOverrides["editUndo"] || "Ctrl+Z"
    property string editRedo: SettingsStore.shortcutOverrides["editRedo"] || "Ctrl+Y"
    property string editCopy: SettingsStore.shortcutOverrides["editCopy"] || "Ctrl+C"
    property string editPaste: SettingsStore.shortcutOverrides["editPaste"] || "Ctrl+V"
    property string editDuplicate: SettingsStore.shortcutOverrides["editDuplicate"] || "Ctrl+D"
    property string editDelete: SettingsStore.shortcutOverrides["editDelete"] || "Delete"
    property string editGroup: SettingsStore.shortcutOverrides["editGroup"] || "Ctrl+G"
    property string editUngroup: SettingsStore.shortcutOverrides["editUngroup"] || "Ctrl+Shift+G"
    property string arrangeFront: SettingsStore.shortcutOverrides["arrangeFront"] || "Ctrl+]"
    property string arrangeBack: SettingsStore.shortcutOverrides["arrangeBack"] || "Ctrl+["
    property string arrangeForward: SettingsStore.shortcutOverrides["arrangeForward"] || "]"
    property string arrangeBackward: SettingsStore.shortcutOverrides["arrangeBackward"] || "["
    property string layersRename: SettingsStore.shortcutOverrides["layersRename"] || "F2"

    // Canvas nudge plus explicit 10x variants (separately remappable).
    property string nudgeLeft: SettingsStore.shortcutOverrides["nudgeLeft"] || "Left"
    property string nudgeRight: SettingsStore.shortcutOverrides["nudgeRight"] || "Right"
    property string nudgeUp: SettingsStore.shortcutOverrides["nudgeUp"] || "Up"
    property string nudgeDown: SettingsStore.shortcutOverrides["nudgeDown"] || "Down"
    property string nudgeLeftBig: SettingsStore.shortcutOverrides["nudgeLeftBig"] || "Shift+Left"
    property string nudgeRightBig: SettingsStore.shortcutOverrides["nudgeRightBig"] || "Shift+Right"
    property string nudgeUpBig: SettingsStore.shortcutOverrides["nudgeUpBig"] || "Shift+Up"
    property string nudgeDownBig: SettingsStore.shortcutOverrides["nudgeDownBig"] || "Shift+Down"

    // Design / Animate.
    property string modeToggle: SettingsStore.shortcutOverrides["modeToggle"] || "Tab"
    property string modeDesign: SettingsStore.shortcutOverrides["modeDesign"] || "Ctrl+1"
    property string modeAnimate: SettingsStore.shortcutOverrides["modeAnimate"] || "Ctrl+2"

    // Timeline transport.
    property string transportPlay: SettingsStore.shortcutOverrides["transportPlay"] || "Space"
    property string transportStepBack: SettingsStore.shortcutOverrides["transportStepBack"] || "Ctrl+Left"
    property string transportStepFwd: SettingsStore.shortcutOverrides["transportStepFwd"] || "Ctrl+Right"
    property string transportStart: SettingsStore.shortcutOverrides["transportStart"] || "Home"
    property string transportEnd: SettingsStore.shortcutOverrides["transportEnd"] || "End"

    // All editable ids in stable order (matches groups below).
    readonly property var allIds: ["homeNew", "homeOpen", "homeRename", "homeDelete", "homeDuplicate", "homeStar", "toolSelect", "toolRect", "toolEllipse", "toolTriangle", "toolStar", "toolPen", "toolText", "toolImage", "editUndo", "editRedo", "editCopy", "editPaste", "editDuplicate", "editDelete", "editGroup", "editUngroup", "arrangeFront", "arrangeBack", "arrangeForward", "arrangeBackward", "layersRename", "nudgeLeft", "nudgeRight", "nudgeUp", "nudgeDown", "nudgeLeftBig", "nudgeRightBig", "nudgeUpBig", "nudgeDownBig", "modeToggle", "modeDesign", "modeAnimate", "transportPlay", "transportStepBack", "transportStepFwd", "transportStart", "transportEnd"]

    function defaultFor(id) {
        switch (id) {
        case "homeNew":
            return "Ctrl+N";
        case "homeOpen":
            return "Return";
        case "homeRename":
            return "F2";
        case "homeDelete":
            return "Delete";
        case "homeDuplicate":
            return "Ctrl+D";
        case "homeStar":
            return "S";
        case "toolSelect":
            return "V";
        case "toolRect":
            return "R";
        case "toolEllipse":
            return "E";
        case "toolTriangle":
            return "T";
        case "toolStar":
            return "S";
        case "toolPen":
            return "P";
        case "toolText":
            return "X";
        case "toolImage":
            return "I";
        case "editUndo":
            return "Ctrl+Z";
        case "editRedo":
            return "Ctrl+Y";
        case "editCopy":
            return "Ctrl+C";
        case "editPaste":
            return "Ctrl+V";
        case "editDuplicate":
            return "Ctrl+D";
        case "editDelete":
            return "Delete";
        case "editGroup":
            return "Ctrl+G";
        case "editUngroup":
            return "Ctrl+Shift+G";
        case "arrangeFront":
            return "Ctrl+]";
        case "arrangeBack":
            return "Ctrl+[";
        case "arrangeForward":
            return "]";
        case "arrangeBackward":
            return "[";
        case "layersRename":
            return "F2";
        case "nudgeLeft":
            return "Left";
        case "nudgeRight":
            return "Right";
        case "nudgeUp":
            return "Up";
        case "nudgeDown":
            return "Down";
        case "nudgeLeftBig":
            return "Shift+Left";
        case "nudgeRightBig":
            return "Shift+Right";
        case "nudgeUpBig":
            return "Shift+Up";
        case "nudgeDownBig":
            return "Shift+Down";
        case "modeToggle":
            return "Tab";
        case "modeDesign":
            return "Ctrl+1";
        case "modeAnimate":
            return "Ctrl+2";
        case "transportPlay":
            return "Space";
        case "transportStepBack":
            return "Ctrl+Left";
        case "transportStepFwd":
            return "Ctrl+Right";
        case "transportStart":
            return "Home";
        case "transportEnd":
            return "End";
        default:
            return "";
        }
    }

    function labelFor(id) {
        switch (id) {
        case "homeNew":
            return qsTr("New design");
        case "homeOpen":
            return qsTr("Open selected");
        case "homeRename":
            return qsTr("Rename selected");
        case "homeDelete":
            return qsTr("Delete selected");
        case "homeDuplicate":
            return qsTr("Duplicate selected");
        case "homeStar":
            return qsTr("Star / unstar selected");
        case "toolSelect":
            return qsTr("Select");
        case "toolRect":
            return qsTr("Rectangle");
        case "toolEllipse":
            return qsTr("Ellipse");
        case "toolTriangle":
            return qsTr("Triangle");
        case "toolStar":
            return qsTr("Star");
        case "toolPen":
            return qsTr("Pen");
        case "toolText":
            return qsTr("Text");
        case "toolImage":
            return qsTr("Image");
        case "editUndo":
            return qsTr("Undo");
        case "editRedo":
            return qsTr("Redo");
        case "editCopy":
            return qsTr("Copy");
        case "editPaste":
            return qsTr("Paste");
        case "editDuplicate":
            return qsTr("Duplicate");
        case "editDelete":
            return qsTr("Delete");
        case "editGroup":
            return qsTr("Group");
        case "editUngroup":
            return qsTr("Ungroup");
        case "arrangeFront":
            return qsTr("Bring to front");
        case "arrangeBack":
            return qsTr("Send to back");
        case "arrangeForward":
            return qsTr("Move forward");
        case "arrangeBackward":
            return qsTr("Move backward");
        case "layersRename":
            return qsTr("Rename layer");
        case "nudgeLeft":
            return qsTr("Nudge left 1px");
        case "nudgeRight":
            return qsTr("Nudge right 1px");
        case "nudgeUp":
            return qsTr("Nudge up 1px");
        case "nudgeDown":
            return qsTr("Nudge down 1px");
        case "nudgeLeftBig":
            return qsTr("Nudge left 10px");
        case "nudgeRightBig":
            return qsTr("Nudge right 10px");
        case "nudgeUpBig":
            return qsTr("Nudge up 10px");
        case "nudgeDownBig":
            return qsTr("Nudge down 10px");
        case "modeToggle":
            return qsTr("Toggle Design / Animate");
        case "modeDesign":
            return qsTr("Design mode");
        case "modeAnimate":
            return qsTr("Animate mode");
        case "transportPlay":
            return qsTr("Play / pause");
        case "transportStepBack":
            return qsTr("Step back");
        case "transportStepFwd":
            return qsTr("Step forward");
        case "transportStart":
            return qsTr("Jump to start");
        case "transportEnd":
            return qsTr("Jump to end");
        default:
            return id;
        }
    }

    function sequenceFor(id) {
        switch (id) {
        case "homeNew":
            return shortcutState.homeNew;
        case "homeOpen":
            return shortcutState.homeOpen;
        case "homeRename":
            return shortcutState.homeRename;
        case "homeDelete":
            return shortcutState.homeDelete;
        case "homeDuplicate":
            return shortcutState.homeDuplicate;
        case "homeStar":
            return shortcutState.homeStar;
        case "toolSelect":
            return shortcutState.toolSelect;
        case "toolRect":
            return shortcutState.toolRect;
        case "toolEllipse":
            return shortcutState.toolEllipse;
        case "toolTriangle":
            return shortcutState.toolTriangle;
        case "toolStar":
            return shortcutState.toolStar;
        case "toolPen":
            return shortcutState.toolPen;
        case "toolText":
            return shortcutState.toolText;
        case "toolImage":
            return shortcutState.toolImage;
        case "editUndo":
            return shortcutState.editUndo;
        case "editRedo":
            return shortcutState.editRedo;
        case "editCopy":
            return shortcutState.editCopy;
        case "editPaste":
            return shortcutState.editPaste;
        case "editDuplicate":
            return shortcutState.editDuplicate;
        case "editDelete":
            return shortcutState.editDelete;
        case "editGroup":
            return shortcutState.editGroup;
        case "editUngroup":
            return shortcutState.editUngroup;
        case "arrangeFront":
            return shortcutState.arrangeFront;
        case "arrangeBack":
            return shortcutState.arrangeBack;
        case "arrangeForward":
            return shortcutState.arrangeForward;
        case "arrangeBackward":
            return shortcutState.arrangeBackward;
        case "layersRename":
            return shortcutState.layersRename;
        case "nudgeLeft":
            return shortcutState.nudgeLeft;
        case "nudgeRight":
            return shortcutState.nudgeRight;
        case "nudgeUp":
            return shortcutState.nudgeUp;
        case "nudgeDown":
            return shortcutState.nudgeDown;
        case "nudgeLeftBig":
            return shortcutState.nudgeLeftBig;
        case "nudgeRightBig":
            return shortcutState.nudgeRightBig;
        case "nudgeUpBig":
            return shortcutState.nudgeUpBig;
        case "nudgeDownBig":
            return shortcutState.nudgeDownBig;
        case "modeToggle":
            return shortcutState.modeToggle;
        case "modeDesign":
            return shortcutState.modeDesign;
        case "modeAnimate":
            return shortcutState.modeAnimate;
        case "transportPlay":
            return shortcutState.transportPlay;
        case "transportStepBack":
            return shortcutState.transportStepBack;
        case "transportStepFwd":
            return shortcutState.transportStepFwd;
        case "transportStart":
            return shortcutState.transportStart;
        case "transportEnd":
            return shortcutState.transportEnd;
        default:
            return "";
        }
    }

    function isCustom(id) {
        return SettingsStore.shortcutOverrides[id] !== undefined;
    }

    function normalize(seq) {
        return (seq || "").toUpperCase().replace(/\s+/g, "");
    }

    // Fixed aliases outside the registry that still fire (Backspace deletes,
    // keypad Enter opens, StandardKey.Redo covers mac Cmd+Shift+Z). Treat
    // them as conflicts so a remap never silently double-fires.
    function aliasOwnerId(seq) {
        var n = shortcutState.normalize(seq);
        if (n === "BACKSPACE")
            return "editDelete";
        if (n === "ENTER")
            return "homeOpen";
        if (n === "CTRL+SHIFT+Z")
            return "editRedo";
        return "";
    }

    // Id of the other action already using seq, or "" when free. Compares
    // normalized so "ctrl+n" and "Ctrl+N" collide.
    function findConflict(seq, exceptId) {
        var n = shortcutState.normalize(seq);
        if (n === "")
            return "";
        var aliasId = shortcutState.aliasOwnerId(seq);
        if (aliasId !== "" && aliasId !== exceptId)
            return aliasId;
        var ids = shortcutState.allIds;
        for (var i = 0; i < ids.length; i++) {
            if (ids[i] === exceptId)
                continue;
            if (shortcutState.normalize(shortcutState.sequenceFor(ids[i])) === n)
                return ids[i];
        }
        return "";
    }

    // Saves when free; returns "" on success, otherwise the conflicting
    // action id (or "invalid" when empty/unparseable).
    function trySetSequence(id, seq) {
        var trimmed = (seq || "").trim();
        if (trimmed === "")
            return "invalid";
        var conflict = shortcutState.findConflict(trimmed, id);
        if (conflict !== "")
            return conflict;
        SettingsStore.setShortcut(id, trimmed);
        return "";
    }

    function resetOne(id) {
        SettingsStore.resetShortcut(id);
    }

    function resetAll() {
        shortcutState.capturing = false;
        shortcutState.capturingId = "";
        SettingsStore.resetAllShortcuts();
    }

    // Grouped listing for the Shortcut tab. Reads live properties so the
    // view updates on every remap/reset with no call-site changes.
    function shortcutGroups() {
        return [
            {
                title: qsTr("Home"),
                items: [
                    {
                        id: "homeNew",
                        label: shortcutState.labelFor("homeNew"),
                        sequence: shortcutState.homeNew
                    },
                    {
                        id: "homeOpen",
                        label: shortcutState.labelFor("homeOpen"),
                        sequence: shortcutState.homeOpen
                    },
                    {
                        id: "homeRename",
                        label: shortcutState.labelFor("homeRename"),
                        sequence: shortcutState.homeRename
                    },
                    {
                        id: "homeDelete",
                        label: shortcutState.labelFor("homeDelete"),
                        sequence: shortcutState.homeDelete
                    },
                    {
                        id: "homeDuplicate",
                        label: shortcutState.labelFor("homeDuplicate"),
                        sequence: shortcutState.homeDuplicate
                    },
                    {
                        id: "homeStar",
                        label: shortcutState.labelFor("homeStar"),
                        sequence: shortcutState.homeStar
                    }
                ]
            },
            {
                title: qsTr("Tools"),
                items: [
                    {
                        id: "toolSelect",
                        label: shortcutState.labelFor("toolSelect"),
                        sequence: shortcutState.toolSelect
                    },
                    {
                        id: "toolRect",
                        label: shortcutState.labelFor("toolRect"),
                        sequence: shortcutState.toolRect
                    },
                    {
                        id: "toolEllipse",
                        label: shortcutState.labelFor("toolEllipse"),
                        sequence: shortcutState.toolEllipse
                    },
                    {
                        id: "toolTriangle",
                        label: shortcutState.labelFor("toolTriangle"),
                        sequence: shortcutState.toolTriangle
                    },
                    {
                        id: "toolStar",
                        label: shortcutState.labelFor("toolStar"),
                        sequence: shortcutState.toolStar
                    },
                    {
                        id: "toolPen",
                        label: shortcutState.labelFor("toolPen"),
                        sequence: shortcutState.toolPen
                    },
                    {
                        id: "toolText",
                        label: shortcutState.labelFor("toolText"),
                        sequence: shortcutState.toolText
                    },
                    {
                        id: "toolImage",
                        label: shortcutState.labelFor("toolImage"),
                        sequence: shortcutState.toolImage
                    }
                ]
            },
            {
                title: qsTr("Edit"),
                items: [
                    {
                        id: "editUndo",
                        label: shortcutState.labelFor("editUndo"),
                        sequence: shortcutState.editUndo
                    },
                    {
                        id: "editRedo",
                        label: shortcutState.labelFor("editRedo"),
                        sequence: shortcutState.editRedo
                    },
                    {
                        id: "editCopy",
                        label: shortcutState.labelFor("editCopy"),
                        sequence: shortcutState.editCopy
                    },
                    {
                        id: "editPaste",
                        label: shortcutState.labelFor("editPaste"),
                        sequence: shortcutState.editPaste
                    },
                    {
                        id: "editDuplicate",
                        label: shortcutState.labelFor("editDuplicate"),
                        sequence: shortcutState.editDuplicate
                    },
                    {
                        id: "editDelete",
                        label: shortcutState.labelFor("editDelete"),
                        sequence: shortcutState.editDelete
                    },
                    {
                        id: "editGroup",
                        label: shortcutState.labelFor("editGroup"),
                        sequence: shortcutState.editGroup
                    },
                    {
                        id: "editUngroup",
                        label: shortcutState.labelFor("editUngroup"),
                        sequence: shortcutState.editUngroup
                    },
                    {
                        id: "arrangeFront",
                        label: shortcutState.labelFor("arrangeFront"),
                        sequence: shortcutState.arrangeFront
                    },
                    {
                        id: "arrangeBack",
                        label: shortcutState.labelFor("arrangeBack"),
                        sequence: shortcutState.arrangeBack
                    },
                    {
                        id: "arrangeForward",
                        label: shortcutState.labelFor("arrangeForward"),
                        sequence: shortcutState.arrangeForward
                    },
                    {
                        id: "arrangeBackward",
                        label: shortcutState.labelFor("arrangeBackward"),
                        sequence: shortcutState.arrangeBackward
                    },
                    {
                        id: "layersRename",
                        label: shortcutState.labelFor("layersRename"),
                        sequence: shortcutState.layersRename
                    }
                ]
            },
            {
                title: qsTr("Canvas"),
                items: [
                    {
                        id: "nudgeLeft",
                        label: shortcutState.labelFor("nudgeLeft"),
                        sequence: shortcutState.nudgeLeft
                    },
                    {
                        id: "nudgeRight",
                        label: shortcutState.labelFor("nudgeRight"),
                        sequence: shortcutState.nudgeRight
                    },
                    {
                        id: "nudgeUp",
                        label: shortcutState.labelFor("nudgeUp"),
                        sequence: shortcutState.nudgeUp
                    },
                    {
                        id: "nudgeDown",
                        label: shortcutState.labelFor("nudgeDown"),
                        sequence: shortcutState.nudgeDown
                    },
                    {
                        id: "nudgeLeftBig",
                        label: shortcutState.labelFor("nudgeLeftBig"),
                        sequence: shortcutState.nudgeLeftBig
                    },
                    {
                        id: "nudgeRightBig",
                        label: shortcutState.labelFor("nudgeRightBig"),
                        sequence: shortcutState.nudgeRightBig
                    },
                    {
                        id: "nudgeUpBig",
                        label: shortcutState.labelFor("nudgeUpBig"),
                        sequence: shortcutState.nudgeUpBig
                    },
                    {
                        id: "nudgeDownBig",
                        label: shortcutState.labelFor("nudgeDownBig"),
                        sequence: shortcutState.nudgeDownBig
                    },
                    {
                        id: "modeToggle",
                        label: shortcutState.labelFor("modeToggle"),
                        sequence: shortcutState.modeToggle
                    },
                    {
                        id: "modeDesign",
                        label: shortcutState.labelFor("modeDesign"),
                        sequence: shortcutState.modeDesign
                    },
                    {
                        id: "modeAnimate",
                        label: shortcutState.labelFor("modeAnimate"),
                        sequence: shortcutState.modeAnimate
                    }
                ]
            },
            {
                title: qsTr("Timeline"),
                items: [
                    {
                        id: "transportPlay",
                        label: shortcutState.labelFor("transportPlay"),
                        sequence: shortcutState.transportPlay
                    },
                    {
                        id: "transportStepBack",
                        label: shortcutState.labelFor("transportStepBack"),
                        sequence: shortcutState.transportStepBack
                    },
                    {
                        id: "transportStepFwd",
                        label: shortcutState.labelFor("transportStepFwd"),
                        sequence: shortcutState.transportStepFwd
                    },
                    {
                        id: "transportStart",
                        label: shortcutState.labelFor("transportStart"),
                        sequence: shortcutState.transportStart
                    },
                    {
                        id: "transportEnd",
                        label: shortcutState.labelFor("transportEnd"),
                        sequence: shortcutState.transportEnd
                    }
                ]
            }
        ];
    }
}
