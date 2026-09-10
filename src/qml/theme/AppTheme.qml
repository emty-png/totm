pragma Singleton
import QtQuick
import Totm

// App theme. The only place hex colors live; components bind AppTheme.*
// instead of hardcoding. The effective value persists via SettingsStore
// (native QSettings, separate from library.json): first run follows the
// OS scheme, the first explicit toggle pins an override.
QtObject {
    id: theme

    property bool isDark: SettingsStore.isDark
    property string name: isDark ? "dark" : "white"

    // Core palette
    property color background: isDark ? "#1e1e1e" : "#ffffff"
    property color foreground: isDark ? "#f6f6f6" : "#0f0f0f"
    property color surface: isDark ? "#2e2e2e" : "#fffde0"
    property color border: isDark ? "#3e3e46" : "#000000"
    property color muted: isDark ? "#9a9a9a" : "#000000"

    // Titlebar button states.
    property color hover: isDark ? "#3e3e46" : "#12000000"
    property color pressed: isDark ? "#2a2a2a" : "#1f000000"

    // Close stays red in both themes.
    property color closeHover: "#e81123"
    property color closePressed: "#c50e1f"

    // Canvas fill, darker than the panels.
    property color canvas: isDark ? "#101010" : "#ececec"

    // Scene frame hairline. Translucent in light so it stays subtle
    // around the white scene.
    property color sceneFrame: isDark ? "#3e3e46" : "#33000000"

    // Input hairline. Full border strength in dark; warm cream in light
    // to sit on the cream surface.
    property color fieldBorder: isDark ? border : "#c4b478"

    // Selection accents (marquee, outlines, layer highlight).
    property color selection: "#0d99ff"

    // Snap-guide red, themed to read on both canvas fills.
    property color snapGuide: isDark ? "#ff5a5a" : "#e81123"

    // Selected-row fill (layers list). Solid per theme; bright blue stays
    // reserved for 1px accents.
    property color layerSelected: isDark ? "#0e3a5d" : "#c7e0f4"

    function toggle() {
        SettingsStore.toggle();
    }
}
