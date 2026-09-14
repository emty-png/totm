pragma Singleton
import QtQuick
import Totm

// App theme. The only place hex colors live; components bind AppTheme.*
// instead of hardcoding. The effective value persists via SettingsStore
// (native QSettings, separate from library.json): first run follows the
// OS scheme, the first explicit toggle pins an override.
// Colors resolve per-theme from SettingsStore overrides (only
// non-defaults stored); missing keys fall back to the defaults below.
// Radius resolves from the preset (sharp 0, rounded 6/8/10/12,
// pill 14/18/22/28, custom uses stored per-size values 0..28).
QtObject {
    id: theme

    property bool isDark: SettingsStore.isDark
    property string name: isDark ? "dark" : "white"

    // Core palette (overridable per theme in Appearance settings).
    property color background: isDark ? (SettingsStore.darkColors["background"] || "#1e1e1e") : (SettingsStore.lightColors["background"] || "#ffffff")
    property color foreground: isDark ? (SettingsStore.darkColors["foreground"] || "#f6f6f6") : (SettingsStore.lightColors["foreground"] || "#0f0f0f")
    property color surface: isDark ? (SettingsStore.darkColors["surface"] || "#2e2e2e") : (SettingsStore.lightColors["surface"] || "#fffde0")
    property color border: isDark ? (SettingsStore.darkColors["border"] || "#3e3e46") : (SettingsStore.lightColors["border"] || "#000000")
    property color muted: isDark ? (SettingsStore.darkColors["muted"] || "#9a9a9a") : (SettingsStore.lightColors["muted"] || "#000000")

    // Titlebar button states.
    property color hover: isDark ? (SettingsStore.darkColors["hover"] || "#3e3e46") : (SettingsStore.lightColors["hover"] || "#12000000")
    property color pressed: isDark ? (SettingsStore.darkColors["pressed"] || "#2a2a2a") : (SettingsStore.lightColors["pressed"] || "#1f000000")

    // Close stays red in both themes.
    property color closeHover: isDark ? (SettingsStore.darkColors["closeHover"] || "#e81123") : (SettingsStore.lightColors["closeHover"] || "#e81123")
    property color closePressed: isDark ? (SettingsStore.darkColors["closePressed"] || "#c50e1f") : (SettingsStore.lightColors["closePressed"] || "#c50e1f")

    // Canvas fill, darker than the panels.
    property color canvas: isDark ? (SettingsStore.darkColors["canvas"] || "#101010") : (SettingsStore.lightColors["canvas"] || "#ececec")

    // Scene frame hairline. Translucent in light so it stays subtle
    // around the white scene.
    property color sceneFrame: isDark ? (SettingsStore.darkColors["sceneFrame"] || "#3e3e46") : (SettingsStore.lightColors["sceneFrame"] || "#33000000")

    // Input hairline. Full border strength in dark; warm cream in light
    // to sit on the cream surface.
    property color fieldBorder: isDark ? (SettingsStore.darkColors["fieldBorder"] || "#3e3e46") : (SettingsStore.lightColors["fieldBorder"] || "#c4b478")

    // Selection accents (marquee, outlines, layer highlight).
    property color selection: isDark ? (SettingsStore.darkColors["selection"] || "#0d99ff") : (SettingsStore.lightColors["selection"] || "#0d99ff")

    // Snap-guide red, themed to read on both canvas fills.
    property color snapGuide: isDark ? (SettingsStore.darkColors["snapGuide"] || "#ff5a5a") : (SettingsStore.lightColors["snapGuide"] || "#e81123")

    // Selected-row fill (layers list). Solid per theme; bright blue stays
    // reserved for 1px accents.
    property color layerSelected: isDark ? (SettingsStore.darkColors["layerSelected"] || "#0e3a5d") : (SettingsStore.lightColors["layerSelected"] || "#c7e0f4")

    // Corner radius scale. Presets keep the 6/8/10/12 rhythm; custom
    // uses the stored per-size values. Components migrate here over
    // time; new code must bind these instead of hardcoding radius.
    property string radiusPreset: SettingsStore.radiusPreset
    property int radiusSmall: theme.radiusPreset === "sharp" ? 0 : theme.radiusPreset === "pill" ? 14 : theme.radiusPreset === "custom" ? SettingsStore.customRadiusSmall : 6
    property int radiusMedium: theme.radiusPreset === "sharp" ? 0 : theme.radiusPreset === "pill" ? 18 : theme.radiusPreset === "custom" ? SettingsStore.customRadiusMedium : 8
    property int radiusLarge: theme.radiusPreset === "sharp" ? 0 : theme.radiusPreset === "pill" ? 22 : theme.radiusPreset === "custom" ? SettingsStore.customRadiusLarge : 10
    property int radiusXLarge: theme.radiusPreset === "sharp" ? 0 : theme.radiusPreset === "pill" ? 28 : theme.radiusPreset === "custom" ? SettingsStore.customRadiusXLarge : 12

    // UI font family. Empty means system default; custom .ttf/.otf files
    // imported in Appearance settings register app-wide via QFontDatabase.
    property string fontFamily: SettingsStore.fontFamily

    function toggle() {
        SettingsStore.toggle();
    }

    function defaultColor(key, dark) {
        switch (key) {
        case "background":
            return dark ? "#1e1e1e" : "#ffffff";
        case "foreground":
            return dark ? "#f6f6f6" : "#0f0f0f";
        case "surface":
            return dark ? "#2e2e2e" : "#fffde0";
        case "border":
            return dark ? "#3e3e46" : "#000000";
        case "muted":
            return dark ? "#9a9a9a" : "#000000";
        case "hover":
            return dark ? "#3e3e46" : "#12000000";
        case "pressed":
            return dark ? "#2a2a2a" : "#1f000000";
        case "closeHover":
            return "#e81123";
        case "closePressed":
            return "#c50e1f";
        case "canvas":
            return dark ? "#101010" : "#ececec";
        case "sceneFrame":
            return dark ? "#3e3e46" : "#33000000";
        case "fieldBorder":
            return dark ? "#3e3e46" : "#c4b478";
        case "selection":
            return "#0d99ff";
        case "snapGuide":
            return dark ? "#ff5a5a" : "#e81123";
        case "layerSelected":
            return dark ? "#0e3a5d" : "#c7e0f4";
        default:
            return dark ? "#000000" : "#ffffff";
        }
    }
}
