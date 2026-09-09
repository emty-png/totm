import QtQuick
import QtQuick.Shapes
import Totm

// Live motion-path preview: active path bright, rubber solid to a snapped
// ghost dot like Figma, anchors as squares (smooth as circles). A
// selected Path clip's trajectory also draws (dimmed, line only) so the
// motion reads without entering draw mode.
// Content-space container so paths land 1:1; dot sizes divide by zoom.
Item {
    id: overlay

    anchors.fill: parent

    required property var tool
    required property real zoom
    required property real offsetX
    required property real offsetY
    required property bool pathActive

    // Absolute content points of the selected clip's trajectory plus its
    // closed flag. Shown only outside draw mode (draw mode shows the
    // seeded session instead, never double-drawn).
    property var selectedPts: []
    property bool selectedClosed: false
    property bool showSelected: false

    visible: (overlay.pathActive && overlay.tool !== null) || overlay.showSelected

    readonly property real cz: overlay.zoom > 0 ? overlay.zoom : 1
    readonly property real dot: 8 / overlay.cz
    readonly property real small: 6 / overlay.cz

    Item {
        x: overlay.offsetX
        y: overlay.offsetY
        scale: overlay.cz
        transformOrigin: Item.TopLeft

        Shape {
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: AppTheme.selection
                strokeWidth: 1.5 / overlay.cz
                PathSvg {
                    path: overlay.tool ? overlay.tool.svgFor([
                        {
                            closed: overlay.tool.showClosed,
                            pts: overlay.tool.active
                        }
                    ], false) : ""
                }
            }
        }

        // Selected clip's trajectory (outside draw mode only).
        Shape {
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            visible: overlay.showSelected && !overlay.pathActive
            opacity: 0.65

            ShapePath {
                fillColor: "transparent"
                strokeColor: AppTheme.selection
                strokeWidth: 1.5 / overlay.cz
                PathSvg {
                    path: overlay.tool ? overlay.tool.svgFor([
                        {
                            closed: overlay.selectedClosed,
                            pts: overlay.selectedPts
                        }
                    ], false) : ""
                }
            }
        }

        Shape {
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            visible: overlay.tool ? overlay.tool.previewActive : false

            ShapePath {
                fillColor: "transparent"
                strokeColor: AppTheme.selection
                strokeWidth: 1.5 / overlay.cz
                PathSvg {
                    path: overlay.tool ? overlay.tool.svgFor([], true) : ""
                }
            }
        }

        Rectangle {
            visible: overlay.tool ? overlay.tool.previewActive : false
            x: (overlay.tool ? overlay.tool.snCX : 0) - width / 2
            y: (overlay.tool ? overlay.tool.snCY : 0) - height / 2
            width: overlay.dot
            height: overlay.dot
            radius: width / 2
            color: "#ffffff"
            border.width: 1.5 / overlay.cz
            border.color: AppTheme.selection
        }

        Repeater {
            model: overlay.tool ? overlay.tool.active : []

            delegate: Item {
                required property var modelData
                required property int index

                visible: modelData.smooth === true

                Shape {
                    antialiasing: true

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: AppTheme.selection
                        strokeWidth: 1 / overlay.cz
                        PathSvg {
                            path: "M " + modelData.inX + "," + modelData.inY + " L " + modelData.x + "," + modelData.y + " L " + modelData.outX + "," + modelData.outY
                        }
                    }
                }

                Rectangle {
                    x: modelData.inX - overlay.small / 2
                    y: modelData.inY - overlay.small / 2
                    width: overlay.small
                    height: overlay.small
                    radius: overlay.small / 2
                    color: "#ffffff"
                    border.width: 1 / overlay.cz
                    border.color: AppTheme.selection
                }

                Rectangle {
                    x: modelData.outX - overlay.small / 2
                    y: modelData.outY - overlay.small / 2
                    width: overlay.small
                    height: overlay.small
                    radius: overlay.small / 2
                    color: "#ffffff"
                    border.width: 1 / overlay.cz
                    border.color: AppTheme.selection
                }
            }
        }

        Repeater {
            model: overlay.tool ? overlay.tool.active : []

            delegate: Rectangle {
                required property var modelData
                required property int index

                readonly property bool picked: overlay.tool ? overlay.tool.sel.indexOf(index) >= 0 : false

                x: modelData.x - width / 2
                y: modelData.y - height / 2
                width: overlay.dot
                height: overlay.dot
                radius: modelData.smooth === true ? width / 2 : 1 / overlay.cz
                color: picked ? AppTheme.selection : "#ffffff"
                border.width: 1.5 / overlay.cz
                border.color: AppTheme.selection
            }
        }
    }
}
