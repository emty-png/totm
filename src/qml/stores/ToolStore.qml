pragma Singleton
import QtQuick

// Active canvas tool state (mirrors web useEditor activeTool +
// shapeStore activeShapeType). "select" click-selects and marquees;
// "shapes" draws, defaulting back to "select" after each creation.
QtObject {
    id: toolStore

    property string activeTool: "select"
    property string activeShapeType: "rectangle"

    function setActiveTool(tool) {
        toolStore.activeTool = tool;
    }

    function setActiveShapeType(shapeType) {
        toolStore.activeShapeType = shapeType;
        toolStore.activeTool = "shapes";
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
