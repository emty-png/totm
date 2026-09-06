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
}
