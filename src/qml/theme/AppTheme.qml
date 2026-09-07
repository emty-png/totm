pragma Singleton
import QtQuick

// App theme matching web reference (themes.css / themes.ts).
// dark is the default (defaultThemeId = "dark").
QtObject {
    id: theme

    property bool isDark: true
    property string name: isDark ? "dark" : "white"

    // Core palette
    property color background: isDark ? "#1e1e1e" : "#ffffff"
    property color foreground: isDark ? "#f6f6f6" : "#0f0f0f"
    property color surface: isDark ? "#2e2e2e" : "#fffde0"
    property color border: isDark ? "#3e3e46" : "#000000"
    property color muted: isDark ? "#9a9a9a" : "#000000"

    // Titlebar button states (web --hover / --active)
    property color hover: isDark ? "#3e3e46" : "#12000000"
    property color pressed: isDark ? "#2a2a2a" : "#1f000000"

    // Close stays red in both themes
    property color closeHover: "#e81123"
    property color closePressed: "#c50e1f"

    // Canvas is darker than the panels (web --canvas)
    property color canvas: isDark ? "#101010" : "#ececec"

    // Scene frame: subtle hairline in both themes (pure black in the
    // light theme reads as broken around the white scene).
    property color sceneFrame: isDark ? "#3e3e46" : "#33000000"

    // Input hairline (panel fields and filled panel buttons): full
    // border strength in dark, darker cream in light to sit warm on
    // the cream surface instead of a heavy black or a grey wash.
    property color fieldBorder: isDark ? border : "#c4b478"

    // Selection accents (marquee, outlines, layer highlight).
    property color selection: "#0d99ff"

    // Smart-snap guides (Figma-style alignment red, themed so it reads
    // on both dark and light canvas).
    property color snapGuide: isDark ? "#ff5a5a" : "#e81123"

    // Selected-row fill (layers list): deep blue in dark, soft ice blue
    // in light. Solid per theme so it never goes murky like a wash over
    // near-black does; bright blue stays reserved for 1px accents.
    property color layerSelected: isDark ? "#0e3a5d" : "#c7e0f4"

    function toggle() {
        isDark = !isDark;
    }
}
