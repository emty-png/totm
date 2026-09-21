import QtQuick
import QtQuick.Shapes
import Totm

// OfficialBadge: X/Instagram-style verified seal — a scalloped badge in
// the app accent with a check. Icon-only; callers add their own labels.
// The check stays fixed white for contrast on the seal (like the close
// button stays red in both themes).
Item {
    id: badge

    property int badgeSize: 14

    width: badgeSize
    height: badgeSize

    Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        transform: Scale {
            xScale: badge.width / 256
            yScale: badge.height / 256
            origin.x: 0
            origin.y: 0
        }

        ShapePath {
            fillColor: AppTheme.selection
            strokeColor: "transparent"
            PathSvg {
                path: "M 237.0 128.0 L 234.1 135.0 L 227.1 141.1 L 219.8 146.3 L 215.9 151.6 L 216.7 158.1 L 220.4 166.3 L 223.4 175.0 L 222.4 182.5 L 216.4 187.1 L 207.3 188.9 L 198.4 189.7 L 192.3 192.3 L 189.7 198.4 L 188.9 207.3 L 187.1 216.4 L 182.5 222.4 L 175.0 223.4 L 166.3 220.4 L 158.1 216.7 L 151.6 215.9 L 146.3 219.8 L 141.1 227.1 L 135.0 234.1 L 128.0 237.0 L 121.0 234.1 L 114.9 227.1 L 109.7 219.8 L 104.4 215.9 L 97.9 216.7 L 89.7 220.4 L 81.0 223.4 L 73.5 222.4 L 68.9 216.4 L 67.1 207.3 L 66.3 198.4 L 63.7 192.3 L 57.6 189.7 L 48.7 188.9 L 39.6 187.1 L 33.6 182.5 L 32.6 175.0 L 35.6 166.3 L 39.3 158.1 L 40.1 151.6 L 36.2 146.3 L 28.9 141.1 L 21.9 135.0 L 19.0 128.0 L 21.9 121.0 L 28.9 114.9 L 36.2 109.7 L 40.1 104.4 L 39.3 97.9 L 35.6 89.7 L 32.6 81.0 L 33.6 73.5 L 39.6 68.9 L 48.7 67.1 L 57.6 66.3 L 63.7 63.7 L 66.3 57.6 L 67.1 48.7 L 68.9 39.6 L 73.5 33.6 L 81.0 32.6 L 89.7 35.6 L 97.9 39.3 L 104.4 40.1 L 109.7 36.2 L 114.9 28.9 L 121.0 21.9 L 128.0 19.0 L 135.0 21.9 L 141.1 28.9 L 146.3 36.2 L 151.6 40.1 L 158.1 39.3 L 166.3 35.6 L 175.0 32.6 L 182.5 33.6 L 187.1 39.6 L 188.9 48.7 L 189.7 57.6 L 192.3 63.7 L 198.4 66.3 L 207.3 67.1 L 216.4 68.9 L 222.4 73.5 L 223.4 81.0 L 220.4 89.7 L 216.7 97.9 L 215.9 104.4 L 219.8 109.7 L 227.1 114.9 L 234.1 121.0 Z"
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: "#ffffff"
            strokeWidth: 26
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathMove {
                x: 100
                y: 132
            }
            PathLine {
                x: 122
                y: 158
            }
            PathLine {
                x: 168
                y: 100
            }
        }
    }
}
