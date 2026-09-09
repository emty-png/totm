import QtQuick
import QtQuick.Shapes
import Totm

// Live pen preview: committed parts dimmed, active part bright, rubber
// solid to a snapped ghost dot like Figma, anchors as squares (smooth
// as circles) with handle arms. Content-space container so paths land
// 1:1; dot sizes divide by zoom to stay constant on screen like
// SelectionHandles.
Item {
    id: overlay

    anchors.fill: parent

    required property var tool
    required property real zoom
    required property real offsetX
    required property real offsetY
    required property bool penActive

    visible: overlay.penActive && overlay.tool !== null

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
                strokeColor: AppTheme.muted
                strokeWidth: 1.5 / overlay.cz
                PathSvg {
                    path: overlay.tool ? overlay.tool.svgFor(overlay.tool.session, false) : ""
                }
            }
        }

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
                            closed: false,
                            pts: overlay.tool.active
                        }
                    ], false) : ""
                }
            }
        }

        // Rubber: snapped next-segment preview, solid like Figma so the
        // in-progress path reads as one line; the ghost dot marks what
        // the next click places. Over the first anchor it draws the
        // closing segment instead (see tool.closePreview).
        Shape {
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            visible: overlay.tool ? (overlay.tool.previewActive || overlay.tool.closePreview) : false

            ShapePath {
                fillColor: "transparent"
                strokeColor: AppTheme.selection
                strokeWidth: 1.5 / overlay.cz
                PathSvg {
                    path: overlay.tool ? overlay.tool.svgFor([], true) : ""
                }
            }
        }

        // Ghost dot at the snapped endpoint: what the next click places.
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

        // Handle arms for smooth active points.
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

        // Active anchors: first point swells when close-hovered.
        Repeater {
            model: overlay.tool ? overlay.tool.active : []

            delegate: Rectangle {
                required property var modelData
                required property int index

                readonly property bool isFirst: index === 0
                readonly property bool closeHot: isFirst && overlay.tool.hoverClose

                x: modelData.x - width / 2
                y: modelData.y - height / 2
                width: closeHot ? 11 / overlay.cz : overlay.dot
                height: closeHot ? 11 / overlay.cz : overlay.dot
                radius: modelData.smooth === true ? width / 2 : 1 / overlay.cz
                color: closeHot ? AppTheme.selection : "#ffffff"
                border.width: 1.5 / overlay.cz
                border.color: AppTheme.selection
            }
        }

        // Committed part anchors dimmed so the active part reads first.
        Repeater {
            model: overlay.tool ? overlay.tool.session : []

            delegate: Repeater {
                required property var modelData

                model: modelData.pts || []

                delegate: Rectangle {
                    required property var modelData

                    x: modelData.x - overlay.small / 2
                    y: modelData.y - overlay.small / 2
                    width: overlay.small
                    height: overlay.small
                    radius: modelData.smooth === true ? width / 2 : 1 / overlay.cz
                    color: "#ffffff"
                    opacity: 0.75
                    border.width: 1 / overlay.cz
                    border.color: AppTheme.muted
                }
            }
        }
    }
}
