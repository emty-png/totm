pragma Singleton
import QtQuick

// Active canvas tool. "select" click-selects and marquees; "shapes" draws
// and falls back to "select" after each creation; "path" draws a motion
// path for custom Path clips (entered from the Custom gallery, Enter
// commits, Esc cancels).
QtObject {
    id: toolState

    property string activeTool: "select"
    property string activeShapeType: "rectangle"

    // Motion-path draw session: target top uid plus redrawn clip id
    // (-1 for a new clip, else the commit replaces that clip's points).
    property int pathTargetUid: -1
    property int pathClipId: -1

    readonly property bool pathDrawing: toolState.activeTool === "path"

    function setActiveTool(tool) {
        if (tool !== "path") {
            toolState.pathTargetUid = -1;
            toolState.pathClipId = -1;
        }
        toolState.activeTool = tool;
    }

    function setActiveShapeType(shapeType) {
        toolState.activeShapeType = shapeType;
        toolState.activeTool = "shapes";
    }

    function startPathDraw(targetUid, clipId) {
        toolState.pathTargetUid = targetUid;
        toolState.pathClipId = clipId !== undefined ? clipId : -1;
        toolState.activeTool = "path";
    }

    function cancelPathDraw() {
        toolState.pathTargetUid = -1;
        toolState.pathClipId = -1;
        if (toolState.activeTool === "path")
            toolState.activeTool = "select";
    }

    // Single source of truth for shape-type icons, shared by the toolbar
    // shapes button and layers rows.
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
        case "image":
            return "image";
        default:
            return "square";
        }
    }
}
