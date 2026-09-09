pragma Singleton
import QtQuick

// Active canvas tool state (mirrors web useEditor activeTool +
// shapeStore activeShapeType). "select" click-selects and marquees;
// "shapes" draws, defaulting back to "select" after each creation.
// "path" draws a motion path for custom Path clips (entered from the
// Custom gallery, committed with Enter, cancelled with Esc).
QtObject {
    id: toolStore

    property string activeTool: "select"
    property string activeShapeType: "rectangle"

    // Motion-path draw session: target top uid plus redraw clip id
    // (-1 for a new clip, else replace that clip's points on commit).
    property int pathTargetUid: -1
    property int pathClipId: -1

    readonly property bool pathDrawing: toolStore.activeTool === "path"

    function setActiveTool(tool) {
        if (tool !== "path") {
            toolStore.pathTargetUid = -1;
            toolStore.pathClipId = -1;
        }
        toolStore.activeTool = tool;
    }

    function setActiveShapeType(shapeType) {
        toolStore.activeShapeType = shapeType;
        toolStore.activeTool = "shapes";
    }

    function startPathDraw(targetUid, clipId) {
        toolStore.pathTargetUid = targetUid;
        toolStore.pathClipId = clipId !== undefined ? clipId : -1;
        toolStore.activeTool = "path";
    }

    function cancelPathDraw() {
        toolStore.pathTargetUid = -1;
        toolStore.pathClipId = -1;
        if (toolStore.activeTool === "path")
            toolStore.activeTool = "select";
    }

    // Single source of truth for shape-type icons. The toolbar shapes
    // button and the layers rows both call this, so a new shape type
    // can never update one and forget the other again.
    function shapeIconFor(type) {
        switch (type) {
        case "ellipse":
            return "circle";
        case "triangle":
            return "triangle";
        case "star":
            return "star";
        case "text":
            return "text";
        case "pen":
            return "pen";
        default:
            return "square";
        }
    }
}
