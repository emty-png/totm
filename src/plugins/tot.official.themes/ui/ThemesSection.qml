import QtQuick
import QtQuick.Layouts
import Totm

// Theme gallery for the Appearance tab (official pack): one-click presets
// that fill the light + dark colors. The host stays on Light/Dark mode,
// so picked themes remain fully tweakable in the Colors card below.
// The Default card restores the built-in totm look.
Rectangle {
    id: gallery

    property string pluginId: ""
    property string lastApplied: ""

    readonly property var colorKeys: ["background", "foreground", "surface", "border", "muted", "hover", "pressed", "closeHover", "closePressed", "canvas", "sceneFrame", "fieldBorder", "selection", "snapGuide", "layerSelected"]
    readonly property bool canApply: PluginStore.hasPermission(gallery.pluginId, "appearance.write")

    // Each entry carries full light + dark maps so one click themes both
    // modes at once. Bases follow the upstream palettes; derived fills
    // stay harmonious within each theme.
    readonly property var themes: [
        {
            "id": "default",
            "name": qsTr("Default"),
            "light": {
                "background": "#ffffff",
                "foreground": "#0f0f0f",
                "surface": "#fffde0",
                "border": "#000000",
                "muted": "#000000",
                "hover": "#12000000",
                "pressed": "#1f000000",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#ececec",
                "sceneFrame": "#33000000",
                "fieldBorder": "#c4b478",
                "selection": "#0d99ff",
                "snapGuide": "#e81123",
                "layerSelected": "#c7e0f4"
            },
            "dark": {
                "background": "#1e1e1e",
                "foreground": "#f6f6f6",
                "surface": "#2e2e2e",
                "border": "#3e3e46",
                "muted": "#9a9a9a",
                "hover": "#3e3e46",
                "pressed": "#2a2a2a",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#101010",
                "sceneFrame": "#3e3e46",
                "fieldBorder": "#3e3e46",
                "selection": "#0d99ff",
                "snapGuide": "#ff5a5a",
                "layerSelected": "#0e3a5d"
            }
        },
        {
            "id": "tokyo-night",
            "name": qsTr("Tokyo Night"),
            "light": {
                "background": "#e1e2e7",
                "foreground": "#343b58",
                "surface": "#d5d6db",
                "border": "#b4b5bf",
                "muted": "#5f6796",
                "hover": "#c9cad2",
                "pressed": "#b8b9c1",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#c6c7ce",
                "sceneFrame": "#a8a9b3",
                "fieldBorder": "#9699a3",
                "selection": "#2e7de9",
                "snapGuide": "#e5484d",
                "layerSelected": "#bcd3f5"
            },
            "dark": {
                "background": "#1a1b26",
                "foreground": "#c0caf5",
                "surface": "#24283b",
                "border": "#414868",
                "muted": "#565f89",
                "hover": "#292e42",
                "pressed": "#1f2335",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#101014",
                "sceneFrame": "#3b4261",
                "fieldBorder": "#414868",
                "selection": "#7aa2f7",
                "snapGuide": "#f7768e",
                "layerSelected": "#2a3b5e"
            }
        },
        {
            "id": "catppuccin",
            "name": qsTr("Catppuccin"),
            "light": {
                "background": "#eff1f5",
                "foreground": "#4c4f69",
                "surface": "#e6e9ef",
                "border": "#bcc0cc",
                "muted": "#6c6f85",
                "hover": "#dfe3ea",
                "pressed": "#ccd1da",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#dcdfea",
                "sceneFrame": "#acb0be",
                "fieldBorder": "#9ca0b0",
                "selection": "#1e66f5",
                "snapGuide": "#d20f39",
                "layerSelected": "#b9cdf7"
            },
            "dark": {
                "background": "#1e1e2e",
                "foreground": "#cdd6f4",
                "surface": "#313244",
                "border": "#45475a",
                "muted": "#7f849c",
                "hover": "#313244",
                "pressed": "#252636",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#11111b",
                "sceneFrame": "#45475a",
                "fieldBorder": "#585b70",
                "selection": "#89b4fa",
                "snapGuide": "#f38ba8",
                "layerSelected": "#2e405c"
            }
        },
        {
            "id": "dracula",
            "name": qsTr("Dracula"),
            "light": {
                "background": "#f8f8f2",
                "foreground": "#282a36",
                "surface": "#e9e9e2",
                "border": "#c4c4b8",
                "muted": "#6272a4",
                "hover": "#e2e2d5",
                "pressed": "#d3d3c4",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e4e4da",
                "sceneFrame": "#b8b8aa",
                "fieldBorder": "#99998a",
                "selection": "#8b5cf6",
                "snapGuide": "#e45555",
                "layerSelected": "#d9c8fa"
            },
            "dark": {
                "background": "#282a36",
                "foreground": "#f8f8f2",
                "surface": "#343746",
                "border": "#44475a",
                "muted": "#6272a4",
                "hover": "#343746",
                "pressed": "#21222c",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#191a21",
                "sceneFrame": "#44475a",
                "fieldBorder": "#6272a4",
                "selection": "#bd93f9",
                "snapGuide": "#ff5555",
                "layerSelected": "#3a3358"
            }
        },
        {
            "id": "nord",
            "name": qsTr("Nord"),
            "light": {
                "background": "#eceff4",
                "foreground": "#2e3440",
                "surface": "#e5e9f0",
                "border": "#d8dee9",
                "muted": "#4c566a",
                "hover": "#dfe4ec",
                "pressed": "#cfd6e2",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#d5dbe4",
                "sceneFrame": "#c2c9d6",
                "fieldBorder": "#a8b2c4",
                "selection": "#5e81ac",
                "snapGuide": "#bf616a",
                "layerSelected": "#b8c9de"
            },
            "dark": {
                "background": "#2e3440",
                "foreground": "#eceff4",
                "surface": "#3b4252",
                "border": "#4c566a",
                "muted": "#616e88",
                "hover": "#434c5e",
                "pressed": "#353c4a",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#242933",
                "sceneFrame": "#4c566a",
                "fieldBorder": "#4c566a",
                "selection": "#88c0d0",
                "snapGuide": "#bf616a",
                "layerSelected": "#33475c"
            }
        },
        {
            "id": "github",
            "name": qsTr("GitHub"),
            "light": {
                "background": "#ffffff",
                "foreground": "#1f2328",
                "surface": "#f6f8fa",
                "border": "#d0d7de",
                "muted": "#59636e",
                "hover": "#eaeef2",
                "pressed": "#d8dee4",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e9edf1",
                "sceneFrame": "#c4ccd4",
                "fieldBorder": "#8c959f",
                "selection": "#0969da",
                "snapGuide": "#d1242f",
                "layerSelected": "#c6e0f7"
            },
            "dark": {
                "background": "#0d1117",
                "foreground": "#e6edf3",
                "surface": "#161b22",
                "border": "#30363d",
                "muted": "#7d8590",
                "hover": "#1c2128",
                "pressed": "#21262d",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#010409",
                "sceneFrame": "#30363d",
                "fieldBorder": "#3d444d",
                "selection": "#1f6feb",
                "snapGuide": "#f85149",
                "layerSelected": "#132c4a"
            }
        },
        {
            "id": "gruvbox",
            "name": qsTr("Gruvbox"),
            "light": {
                "background": "#fbf1c7",
                "foreground": "#3c3836",
                "surface": "#f2e5bc",
                "border": "#d5c4a1",
                "muted": "#7c6f64",
                "hover": "#eee0b7",
                "pressed": "#e0d0a8",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e8d9b0",
                "sceneFrame": "#c9b896",
                "fieldBorder": "#a89984",
                "selection": "#d65d0e",
                "snapGuide": "#cc241d",
                "layerSelected": "#f0d3ae"
            },
            "dark": {
                "background": "#282828",
                "foreground": "#ebdbb2",
                "surface": "#3c3836",
                "border": "#504945",
                "muted": "#928374",
                "hover": "#3c3836",
                "pressed": "#2b2725",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#1d2021",
                "sceneFrame": "#504945",
                "fieldBorder": "#665c54",
                "selection": "#fe8019",
                "snapGuide": "#fb4934",
                "layerSelected": "#4d3a22"
            }
        },
        {
            "id": "one-dark",
            "name": qsTr("One Dark"),
            "light": {
                "background": "#fafafa",
                "foreground": "#383a42",
                "surface": "#f0f0f0",
                "border": "#d0d0d0",
                "muted": "#696c77",
                "hover": "#e8e8e8",
                "pressed": "#d8d8d8",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e2e2e2",
                "sceneFrame": "#c0c0c0",
                "fieldBorder": "#a0a0a0",
                "selection": "#4078f2",
                "snapGuide": "#e45649",
                "layerSelected": "#c2d4f7"
            },
            "dark": {
                "background": "#282c34",
                "foreground": "#abb2bf",
                "surface": "#333841",
                "border": "#3e4451",
                "muted": "#5c6370",
                "hover": "#333841",
                "pressed": "#21252b",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#1b1e23",
                "sceneFrame": "#3e4451",
                "fieldBorder": "#4b5263",
                "selection": "#61afef",
                "snapGuide": "#e06c75",
                "layerSelected": "#2c3e55"
            }
        },
        {
            "id": "solarized",
            "name": qsTr("Solarized"),
            "light": {
                "background": "#fdf6e3",
                "foreground": "#657b83",
                "surface": "#eee8d5",
                "border": "#d5c9a6",
                "muted": "#93a1a1",
                "hover": "#e8e0c8",
                "pressed": "#d9cfb2",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e3dcc3",
                "sceneFrame": "#c2b48f",
                "fieldBorder": "#ab9f7e",
                "selection": "#268bd2",
                "snapGuide": "#dc322f",
                "layerSelected": "#c9dfec"
            },
            "dark": {
                "background": "#002b36",
                "foreground": "#93a1a1",
                "surface": "#073642",
                "border": "#586e75",
                "muted": "#586e75",
                "hover": "#0b3a46",
                "pressed": "#062128",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#001e26",
                "sceneFrame": "#2f4b53",
                "fieldBorder": "#586e75",
                "selection": "#268bd2",
                "snapGuide": "#dc322f",
                "layerSelected": "#123d52"
            }
        },
        {
            "id": "rose-pine",
            "name": qsTr("Rosé Pine"),
            "light": {
                "background": "#faf4ed",
                "foreground": "#575279",
                "surface": "#f2e9e1",
                "border": "#ddd3c7",
                "muted": "#9893a5",
                "hover": "#e9ded3",
                "pressed": "#d9cabd",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e6d9cb",
                "sceneFrame": "#c8bba8",
                "fieldBorder": "#ab9f91",
                "selection": "#907aa9",
                "snapGuide": "#b4637a",
                "layerSelected": "#ded0ee"
            },
            "dark": {
                "background": "#191724",
                "foreground": "#e0def4",
                "surface": "#1f1d2e",
                "border": "#26233a",
                "muted": "#6e6a86",
                "hover": "#26233a",
                "pressed": "#12111c",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#0f0e17",
                "sceneFrame": "#393552",
                "fieldBorder": "#524f67",
                "selection": "#c4a7e7",
                "snapGuide": "#eb6f92",
                "layerSelected": "#33294f"
            }
        },
        {
            "id": "everforest",
            "name": qsTr("Everforest"),
            "light": {
                "background": "#fdf6e3",
                "foreground": "#5c6a72",
                "surface": "#f4f0d9",
                "border": "#d9d4b8",
                "muted": "#939f91",
                "hover": "#ece7cd",
                "pressed": "#dbd5b8",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e8e2c6",
                "sceneFrame": "#c5bfa5",
                "fieldBorder": "#a3ad9e",
                "selection": "#8da101",
                "snapGuide": "#f85552",
                "layerSelected": "#d7e0bd"
            },
            "dark": {
                "background": "#2d353b",
                "foreground": "#d3c6aa",
                "surface": "#343f44",
                "border": "#475258",
                "muted": "#7a8478",
                "hover": "#3a454b",
                "pressed": "#252d31",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#22282c",
                "sceneFrame": "#475258",
                "fieldBorder": "#56635f",
                "selection": "#7fbbb3",
                "snapGuide": "#e67e80",
                "layerSelected": "#31444c"
            }
        },
        {
            "id": "monokai",
            "name": qsTr("Monokai"),
            "light": {
                "background": "#f8f8f2",
                "foreground": "#272822",
                "surface": "#e8e8e0",
                "border": "#cfcfc2",
                "muted": "#75715e",
                "hover": "#e2e2d5",
                "pressed": "#d4d4c6",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e3e3d8",
                "sceneFrame": "#c0c0b2",
                "fieldBorder": "#a8a897",
                "selection": "#0097ad",
                "snapGuide": "#f92672",
                "layerSelected": "#bfe6ee"
            },
            "dark": {
                "background": "#272822",
                "foreground": "#f8f8f2",
                "surface": "#3e3d32",
                "border": "#49483e",
                "muted": "#75715e",
                "hover": "#3e3d32",
                "pressed": "#22231e",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#1a1b18",
                "sceneFrame": "#49483e",
                "fieldBorder": "#75715e",
                "selection": "#66d9ef",
                "snapGuide": "#f92672",
                "layerSelected": "#2e4a53"
            }
        },
        {
            "id": "night-owl",
            "name": qsTr("Night Owl"),
            "light": {
                "background": "#fbfbfb",
                "foreground": "#403f53",
                "surface": "#f0ede6",
                "border": "#e2dcd3",
                "muted": "#989fb1",
                "hover": "#ece8dd",
                "pressed": "#ddd7c8",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e7e2d5",
                "sceneFrame": "#d0c9b8",
                "fieldBorder": "#b3ab99",
                "selection": "#4876d6",
                "snapGuide": "#d3423e",
                "layerSelected": "#c9d8f5"
            },
            "dark": {
                "background": "#011627",
                "foreground": "#d6deeb",
                "surface": "#0b2942",
                "border": "#1d3b53",
                "muted": "#637777",
                "hover": "#0f2f4f",
                "pressed": "#071e33",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#000d1d",
                "sceneFrame": "#1d3b53",
                "fieldBorder": "#1d3b53",
                "selection": "#82aaff",
                "snapGuide": "#ef5350",
                "layerSelected": "#1b3d63"
            }
        },
        {
            "id": "kanagawa",
            "name": qsTr("Kanagawa"),
            "light": {
                "background": "#f2ecbc",
                "foreground": "#545464",
                "surface": "#e9e2c0",
                "border": "#d4c9a3",
                "muted": "#8a8980",
                "hover": "#e7dfba",
                "pressed": "#d8cfa9",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e2d9b4",
                "sceneFrame": "#c9bd93",
                "fieldBorder": "#a09a7e",
                "selection": "#2574ca",
                "snapGuide": "#c84053",
                "layerSelected": "#c3d2ea"
            },
            "dark": {
                "background": "#1f1f28",
                "foreground": "#dcd7ba",
                "surface": "#2a2a37",
                "border": "#363646",
                "muted": "#727169",
                "hover": "#2a2a37",
                "pressed": "#16161d",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#14141b",
                "sceneFrame": "#363646",
                "fieldBorder": "#54546d",
                "selection": "#7e9cd8",
                "snapGuide": "#e46876",
                "layerSelected": "#2c3d59"
            }
        },
        {
            "id": "ayu",
            "name": qsTr("Ayu"),
            "light": {
                "background": "#fafafa",
                "foreground": "#5c6773",
                "surface": "#f0f0f0",
                "border": "#d9d9d9",
                "muted": "#8a919c",
                "hover": "#ececec",
                "pressed": "#dedede",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e2e2e2",
                "sceneFrame": "#c4c4c4",
                "fieldBorder": "#a3a3a3",
                "selection": "#d99a2b",
                "snapGuide": "#d64545",
                "layerSelected": "#f0ddb8"
            },
            "dark": {
                "background": "#0b0e14",
                "foreground": "#b3b1ad",
                "surface": "#11151c",
                "border": "#1f2733",
                "muted": "#626a73",
                "hover": "#141a22",
                "pressed": "#0e1218",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#05070b",
                "sceneFrame": "#1f2733",
                "fieldBorder": "#39424c",
                "selection": "#ff8f40",
                "snapGuide": "#f07178",
                "layerSelected": "#40301c"
            }
        },
        {
            "id": "synthwave-84",
            "name": qsTr("SynthWave '84"),
            "light": {
                "background": "#f5f0fa",
                "foreground": "#34294f",
                "surface": "#e9e0f4",
                "border": "#cfc0e3",
                "muted": "#7d7396",
                "hover": "#e0d3f1",
                "pressed": "#cfbde4",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#ddd0ec",
                "sceneFrame": "#bda9d6",
                "fieldBorder": "#9a86b8",
                "selection": "#b30f82",
                "snapGuide": "#d63a5c",
                "layerSelected": "#eec4e4"
            },
            "dark": {
                "background": "#262335",
                "foreground": "#f2f2f2",
                "surface": "#2e2a3e",
                "border": "#495162",
                "muted": "#848bbd",
                "hover": "#342f4a",
                "pressed": "#201c2e",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#17141f",
                "sceneFrame": "#4a4660",
                "fieldBorder": "#6a6585",
                "selection": "#f92aad",
                "snapGuide": "#ff5370",
                "layerSelected": "#4d2145"
            }
        },
        {
            "id": "palenight",
            "name": qsTr("Palenight"),
            "light": {
                "background": "#fafafa",
                "foreground": "#546e7a",
                "surface": "#f0f0f0",
                "border": "#d3e1e8",
                "muted": "#90a4ae",
                "hover": "#e8e8e8",
                "pressed": "#dadada",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#e3e7ea",
                "sceneFrame": "#c2cdd3",
                "fieldBorder": "#9fb0ba",
                "selection": "#6182b8",
                "snapGuide": "#e53935",
                "layerSelected": "#c8d8ea"
            },
            "dark": {
                "background": "#292d3e",
                "foreground": "#a6accd",
                "surface": "#343a4f",
                "border": "#444267",
                "muted": "#676e95",
                "hover": "#353b54",
                "pressed": "#202331",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#1c1f2e",
                "sceneFrame": "#444267",
                "fieldBorder": "#585a83",
                "selection": "#82aaff",
                "snapGuide": "#ff5370",
                "layerSelected": "#2d3c60"
            }
        },
        {
            "id": "cobalt2",
            "name": qsTr("Cobalt2"),
            "light": {
                "background": "#f2f7fb",
                "foreground": "#193549",
                "surface": "#e4edf4",
                "border": "#c3d5e2",
                "muted": "#5d7a93",
                "hover": "#d9e6f0",
                "pressed": "#c6d8e6",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#d3dfe9",
                "sceneFrame": "#b2c6d5",
                "fieldBorder": "#8ba7bc",
                "selection": "#0075c9",
                "snapGuide": "#d63a3a",
                "layerSelected": "#bcd8f2"
            },
            "dark": {
                "background": "#193549",
                "foreground": "#ffffff",
                "surface": "#1f425e",
                "border": "#2c5d87",
                "muted": "#7587a6",
                "hover": "#224a68",
                "pressed": "#122a3f",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#0e2233",
                "sceneFrame": "#2c5d87",
                "fieldBorder": "#3a7ca5",
                "selection": "#ffc600",
                "snapGuide": "#ff5f5f",
                "layerSelected": "#4d4218"
            }
        },
        {
            "id": "horizon",
            "name": qsTr("Horizon"),
            "light": {
                "background": "#fdf0ed",
                "foreground": "#33353f",
                "surface": "#f4e2dc",
                "border": "#e3c9c0",
                "muted": "#8a7f7a",
                "hover": "#efd9d2",
                "pressed": "#e2c6bc",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#ecd5cc",
                "sceneFrame": "#d3b4a8",
                "fieldBorder": "#b08d81",
                "selection": "#b81e4e",
                "snapGuide": "#cf3a55",
                "layerSelected": "#f2c6d2"
            },
            "dark": {
                "background": "#1c1e26",
                "foreground": "#cdd3da",
                "surface": "#232530",
                "border": "#2e303e",
                "muted": "#6f7072",
                "hover": "#2a2d3a",
                "pressed": "#14151c",
                "closeHover": "#e81123",
                "closePressed": "#c50e1f",
                "canvas": "#101117",
                "sceneFrame": "#3b3d4d",
                "fieldBorder": "#4d4f61",
                "selection": "#e95678",
                "snapGuide": "#ee4b62",
                "layerSelected": "#52253f"
            }
        }
    ]

    Layout.fillWidth: true
    implicitHeight: galleryBody.implicitHeight + 24
    radius: AppTheme.radiusLarge
    border.width: 1
    border.color: AppTheme.border
    color: AppTheme.surface

    function refreshLast() {
        if (PluginStore.hasPermission(gallery.pluginId, "plugin.storage"))
            gallery.lastApplied = String(PluginStore.getValue(gallery.pluginId, "appliedTheme", ""));
    }

    function applyTheme(theme) {
        if (!gallery.canApply || !theme)
            return;
        var ok = PluginStore.applyAppearanceTheme(gallery.pluginId, theme.light, theme.dark);
        if (ok && PluginStore.hasPermission(gallery.pluginId, "plugin.storage")) {
            PluginStore.setValue(gallery.pluginId, "appliedTheme", theme.id);
            gallery.lastApplied = theme.id;
        }
    }

    Component.onCompleted: gallery.refreshLast()

    ColumnLayout {
        id: galleryBody

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: qsTr("Themes")
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: AppTheme.foreground
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: officialLabel.implicitWidth + 26
                implicitHeight: 20
                radius: 10
                border.width: 1
                border.color: AppTheme.selection
                color: "transparent"

                Row {
                    id: officialPill

                    anchors.centerIn: parent
                    spacing: 4

                    OfficialBadge {
                        anchors.verticalCenter: parent.verticalCenter
                        badgeSize: 12
                    }

                    Text {
                        id: officialLabel

                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Official")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: AppTheme.selection
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("One click fills both Light and Dark colors. Tweak below in Colors.")
            font.pixelSize: 11
            color: AppTheme.muted
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8

            Repeater {
                model: gallery.themes

                delegate: Rectangle {
                    id: themeCard

                    required property var modelData
                    readonly property var theme: themeCard.modelData
                    readonly property bool applied: gallery.lastApplied === themeCard.theme.id

                    Layout.fillWidth: true
                    Layout.preferredHeight: 108
                    radius: AppTheme.radiusSmall
                    border.width: 1
                    border.color: themeCard.applied ? AppTheme.selection : AppTheme.fieldBorder
                    color: AppTheme.background

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: themeCard.theme.name
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                color: AppTheme.foreground
                            }

                            Text {
                                visible: themeCard.applied
                                text: "✓"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: AppTheme.selection
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            spacing: 4

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 4
                                border.width: 1
                                border.color: AppTheme.fieldBorder
                                color: themeCard.theme.light.background

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 4
                                    spacing: 3

                                    Rectangle {
                                        width: 14
                                        height: 14
                                        radius: 3
                                        border.width: 1
                                        border.color: AppTheme.fieldBorder
                                        color: themeCard.theme.light.surface
                                    }

                                    Rectangle {
                                        width: 14
                                        height: 14
                                        radius: 7
                                        color: themeCard.theme.light.selection
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 4
                                border.width: 1
                                border.color: AppTheme.fieldBorder
                                color: themeCard.theme.dark.background

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 4
                                    spacing: 3

                                    Rectangle {
                                        width: 14
                                        height: 14
                                        radius: 3
                                        border.width: 1
                                        border.color: AppTheme.fieldBorder
                                        color: themeCard.theme.dark.surface
                                    }

                                    Rectangle {
                                        width: 14
                                        height: 14
                                        radius: 7
                                        color: themeCard.theme.dark.selection
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: AppTheme.radiusSmall
                            border.width: 1
                            border.color: themeCard.applied ? AppTheme.selection : gallery.canApply ? AppTheme.fieldBorder : AppTheme.border
                            color: themeCard.applied ? AppTheme.selection : applyMouse.containsMouse || applyMouse.pressed ? AppTheme.hover : AppTheme.surface

                            Text {
                                anchors.centerIn: parent
                                text: themeCard.applied ? qsTr("Applied") : qsTr("Apply")
                                font.pixelSize: 12
                                font.weight: themeCard.applied ? Font.DemiBold : Font.Normal
                                color: themeCard.applied ? AppTheme.background : gallery.canApply ? AppTheme.foreground : AppTheme.muted
                            }

                            MouseArea {
                                id: applyMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: gallery.canApply ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: gallery.applyTheme(themeCard.theme)
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !gallery.canApply
            text: qsTr("Allow the appearance permission from Review to apply themes.")
            font.pixelSize: 11
            color: AppTheme.muted
            wrapMode: Text.WordWrap
        }
    }
}
