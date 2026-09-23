import QtQuick
import QtQuick.Layouts
import Totm

// Alpha color well for one shadow/glow clip side: swatch plus hex
// field. Hex speaks opaque rgb; the stored alpha rides through
// withAlpha on every commit (typed or picked), so edits never drop
// opacity. Borrow withAlpha for the shared picker popup path.
RowLayout {
    id: well

    required property var colorValue
    required property string defaultColor
    required property var doc
    required property int clipId
    required property string optionRole

    signal swatchClicked(string role, string rgb, var anchor, real ax, real ay)

    spacing: 8

    Rectangle {
        id: swatch

        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        Layout.alignment: Qt.AlignVCenter
        radius: AppTheme.radiusSmall
        color: String(well.colorValue || well.defaultColor)
        border.width: 1
        border.color: AppTheme.border

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => well.swatchClicked(well.optionRole, well.hexOf(well.colorValue), swatch, mouse.x, mouse.y)
        }
    }

    HexField {
        Layout.fillWidth: true
        value: well.hexOf(well.colorValue)
        onCommitted: c => well.commit(c)
    }

    function hexOf(c) {
        var t = String(c || well.defaultColor).toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (t.length === 8)
            return "#" + t.slice(2);
        return "#" + t;
    }

    function withAlpha(hex, keep) {
        var t = String(hex).toLowerCase();
        if (t.charAt(0) === "#")
            t = t.slice(1);
        if (t.length === 3)
            t = t.charAt(0) + t.charAt(0) + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2);
        if (!/^[0-9a-f]{6}$/.test(t))
            t = "000000";
        var k = String(keep || "").toLowerCase();
        if (k.charAt(0) === "#")
            k = k.slice(1);
        if (k.length === 8)
            return "#" + k.slice(0, 2) + t;
        return "#" + t;
    }

    function commit(c) {
        if (!well.doc)
            return;
        var patch = {};
        patch[well.optionRole] = well.withAlpha(c, well.colorValue);
        well.doc.setClipOptions(well.clipId, patch);
    }
}
