import QtQuick

// Unified source-sampled shader layer for vectors + pen + live booleans.
//
// Both modes sample the base paint through baseSrc, so every fragment
// shader declares a sampler (sampler-less shaders never leave Null on
// some drivers) and output alpha derives from base alpha. Fill hides
// the base (hideSource) and shows the procedural tile alone; overlay
// leaves the base visible and blends over it.
//
// Mode switches NEVER swap shader URLs at runtime (fragile pipeline
// rebuilds on some drivers): each preset keeps fixed fill/overlay URLs
// and only visibility flips. Preset formulas mirror ShaderEngine CPU
// bit-for-bit, so preview matches export. Nodes carry shaderId
// ("preset:<id>" or custom asset uuid) plus shaderMode
// ("fill"|"overlay") and shaderParams.
Item {
    id: overlay

    required property string presetId
    required property string mode
    property var params: ({})
    property double timeSec: 0
    // Source item carrying the base paint (vector base / sample swatch /
    // boolean combined paint). Required: alpha comes from here.
    property var sourceItem: null
    // Shape opacity rides inside the captured base alpha already.
    property real baseOpacity: 1
    // Retained for caller compatibility; confinement now comes from base
    // alpha, these are ignored.
    property string maskKind: "rect"
    property real maskRadius: 0
    property string maskPath: ""
    property real maskStroke: 0
    property real maskOX: 0
    property real maskOY: 0

    // Custom GLSL (from-scratch / imported): compiled .qsb URLs from
    // ShaderEngine.compileCustom plus the v1 contract uniforms. Empty
    // urls mean uncompiled/uncompilable: the branch stays hidden and
    // the base paint shows through (popup surfaces the error).
    property string customVertUrl: ""
    property string customFragUrl: ""
    property string customTint: "#ffffff"
    property real customOpacity: 1
    property real customSpeed: 1

    readonly property bool known: overlay.presetId === "plasma" || overlay.presetId === "aurora" || overlay.presetId === "clouds" || overlay.presetId === "kaleidoscope" || overlay.presetId === "scanlines" || overlay.presetId === "fire" || overlay.presetId === "nebula" || overlay.presetId === "vortex" || overlay.presetId === "matrix"
    readonly property bool customReady: overlay.presetId === "custom" && overlay.customVertUrl !== "" && overlay.customFragUrl !== ""
    readonly property bool active: (overlay.known || overlay.customReady) && overlay.sourceItem !== null
    readonly property bool isFill: overlay.mode !== "overlay"
    // Fill is hidden only once the visible fill branch is Ready: a
    // missing .qsb, driver reject, or custom link failure then falls
    // back to base paint instead of vanishing (overlay never hides).
    readonly property bool fillReady: {
        if (!overlay.active || !overlay.isFill)
            return false;
        if (overlay.presetId === "plasma")
            return plasmaFillFx.status === ShaderEffect.Ready;
        if (overlay.presetId === "aurora")
            return auroraFillFx.status === ShaderEffect.Ready;
        if (overlay.presetId === "clouds")
            return cloudsFillFx.status === ShaderEffect.Ready;
        if (overlay.presetId === "kaleidoscope")
            return kaleidoFillFx.status === ShaderEffect.Ready;
        if (overlay.presetId === "scanlines")
            return scanFillFx.status === ShaderEffect.Ready;
        if (overlay.presetId === "fire")
            return fireFillFx.status === ShaderEffect.Ready;
        if (overlay.presetId === "nebula")
            return nebulaFillFx.status === ShaderEffect.Ready;
        if (overlay.presetId === "vortex")
            return vortexFillFx.status === ShaderEffect.Ready;
        if (overlay.presetId === "matrix")
            return matrixFillFx.status === ShaderEffect.Ready;
        if (overlay.presetId === "custom")
            return customFx.status === ShaderEffect.Ready;
        return false;
    }

    // Base capture, sized to the overlay: an unsized source yields an
    // empty texture. Captures only while a shader is assigned; in fill
    // mode the base is hidden on screen but still rendered to texture,
    // so the effect keeps its silhouette alpha.
    ShaderEffectSource {
        id: baseSrc

        anchors.fill: parent
        sourceItem: overlay.sourceItem
        hideSource: overlay.active && overlay.isFill && overlay.fillReady
        live: overlay.active
        textureSize: Qt.size(Math.max(1, Math.round(width)), Math.max(1, Math.round(height)))
    }

    // Plasma fill branch: fixed URLs, visibility flips on preset/mode change.
    ShaderEffect {
        id: plasmaFillFx

        anchors.fill: parent
        visible: overlay.active && overlay.isFill && overlay.presetId === "plasma"
        vertexShader: "plasma.vert.qsb"
        fragmentShader: "plasma.frag.qsb"
        property variant source: baseSrc
        // Plasma uniforms.
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Plasma overlay branch: fixed URLs, visibility flips on preset/mode change.
    // Base already carries shapeOpacity via baseSrc; the tile preserves
    // base alpha, so no extra opacity (would double-apply).
    ShaderEffect {
        id: plasmaOverFx

        anchors.fill: parent
        visible: overlay.active && !overlay.isFill && overlay.presetId === "plasma"
        vertexShader: "plasma.vert.qsb"
        fragmentShader: "plasma_overlay.frag.qsb"
        property variant source: baseSrc
        // Plasma uniforms.
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Aurora fill branch.
    ShaderEffect {
        id: auroraFillFx
        anchors.fill: parent
        visible: overlay.active && overlay.isFill && overlay.presetId === "aurora"
        vertexShader: "aurora.vert.qsb"
        fragmentShader: "aurora.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property real uIntensity: Number((overlay.params ?? {}).intensity ?? 1.0)
        property color uColorA: String((overlay.params ?? {}).colorA ?? "#00e5ff")
        property color uColorB: String((overlay.params ?? {}).colorB ?? "#b537f2")
    }

    // Aurora overlay branch.
    ShaderEffect {
        anchors.fill: parent
        visible: overlay.active && !overlay.isFill && overlay.presetId === "aurora"
        vertexShader: "aurora.vert.qsb"
        fragmentShader: "aurora_overlay.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property real uIntensity: Number((overlay.params ?? {}).intensity ?? 1.0)
        property color uColorA: String((overlay.params ?? {}).colorA ?? "#00e5ff")
        property color uColorB: String((overlay.params ?? {}).colorB ?? "#b537f2")
    }

    // Clouds fill branch.
    ShaderEffect {
        id: cloudsFillFx
        anchors.fill: parent
        visible: overlay.active && overlay.isFill && overlay.presetId === "clouds"
        vertexShader: "clouds.vert.qsb"
        fragmentShader: "clouds.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 0.6)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property real uDensity: Number((overlay.params ?? {}).density ?? 0.5)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Clouds overlay branch.
    ShaderEffect {
        anchors.fill: parent
        visible: overlay.active && !overlay.isFill && overlay.presetId === "clouds"
        vertexShader: "clouds.vert.qsb"
        fragmentShader: "clouds_overlay.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 0.6)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property real uDensity: Number((overlay.params ?? {}).density ?? 0.5)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Kaleidoscope fill branch.
    ShaderEffect {
        id: kaleidoFillFx
        anchors.fill: parent
        visible: overlay.active && overlay.isFill && overlay.presetId === "kaleidoscope"
        vertexShader: "kaleidoscope.vert.qsb"
        fragmentShader: "kaleidoscope.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uSegments: Number((overlay.params ?? {}).segments ?? 6.0)
        property real uZoom: Number((overlay.params ?? {}).zoom ?? 1.2)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Kaleidoscope overlay branch.
    ShaderEffect {
        anchors.fill: parent
        visible: overlay.active && !overlay.isFill && overlay.presetId === "kaleidoscope"
        vertexShader: "kaleidoscope.vert.qsb"
        fragmentShader: "kaleidoscope_overlay.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uSegments: Number((overlay.params ?? {}).segments ?? 6.0)
        property real uZoom: Number((overlay.params ?? {}).zoom ?? 1.2)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Custom fill/overlay branch: one compiled pair serves both modes
    // (fill hides the base item and shows the shader output masked by
    // base alpha; overlay leaves the base visible underneath). Empty
    // urls keep the branch hidden with the base paint showing through.
    ShaderEffect {
        id: customFx
        anchors.fill: parent
        visible: overlay.active && overlay.presetId === "custom"
        vertexShader: overlay.customVertUrl
        fragmentShader: overlay.customFragUrl
        property variant source: baseSrc
        property double uTime: overlay.timeSec * overlay.customSpeed
        property real uOpacity: overlay.customOpacity
        property color uTint: overlay.customTint
    }

    // Scanlines fill branch.
    ShaderEffect {
        id: scanFillFx
        anchors.fill: parent
        visible: overlay.active && overlay.isFill && overlay.presetId === "scanlines"
        vertexShader: "scanlines.vert.qsb"
        fragmentShader: "scanlines.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uFrequency: Number((overlay.params ?? {}).frequency ?? 120.0)
        property real uIntensity: Number((overlay.params ?? {}).intensity ?? 0.5)
        property real uVignette: Number((overlay.params ?? {}).vignette ?? 0.4)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Scanlines overlay branch.
    ShaderEffect {
        anchors.fill: parent
        visible: overlay.active && !overlay.isFill && overlay.presetId === "scanlines"
        vertexShader: "scanlines.vert.qsb"
        fragmentShader: "scanlines_overlay.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uFrequency: Number((overlay.params ?? {}).frequency ?? 120.0)
        property real uIntensity: Number((overlay.params ?? {}).intensity ?? 0.5)
        property real uVignette: Number((overlay.params ?? {}).vignette ?? 0.4)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Fire fill branch.
    ShaderEffect {
        id: fireFillFx
        anchors.fill: parent
        visible: overlay.active && overlay.isFill && overlay.presetId === "fire"
        vertexShader: "fire.vert.qsb"
        fragmentShader: "fire.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Fire overlay branch.
    ShaderEffect {
        anchors.fill: parent
        visible: overlay.active && !overlay.isFill && overlay.presetId === "fire"
        vertexShader: "fire.vert.qsb"
        fragmentShader: "fire_overlay.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Nebula fill branch.
    ShaderEffect {
        id: nebulaFillFx
        anchors.fill: parent
        visible: overlay.active && overlay.isFill && overlay.presetId === "nebula"
        vertexShader: "nebula.vert.qsb"
        fragmentShader: "nebula.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property real uIntensity: Number((overlay.params ?? {}).intensity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Nebula overlay branch.
    ShaderEffect {
        anchors.fill: parent
        visible: overlay.active && !overlay.isFill && overlay.presetId === "nebula"
        vertexShader: "nebula.vert.qsb"
        fragmentShader: "nebula_overlay.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property real uIntensity: Number((overlay.params ?? {}).intensity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Vortex fill branch.
    ShaderEffect {
        id: vortexFillFx
        anchors.fill: parent
        visible: overlay.active && overlay.isFill && overlay.presetId === "vortex"
        vertexShader: "vortex.vert.qsb"
        fragmentShader: "vortex.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uZoom: Number((overlay.params ?? {}).zoom ?? 1.2)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Vortex overlay branch.
    ShaderEffect {
        anchors.fill: parent
        visible: overlay.active && !overlay.isFill && overlay.presetId === "vortex"
        vertexShader: "vortex.vert.qsb"
        fragmentShader: "vortex_overlay.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uZoom: Number((overlay.params ?? {}).zoom ?? 1.2)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Matrix fill branch.
    ShaderEffect {
        id: matrixFillFx
        anchors.fill: parent
        visible: overlay.active && overlay.isFill && overlay.presetId === "matrix"
        vertexShader: "matrix.vert.qsb"
        fragmentShader: "matrix.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }

    // Matrix overlay branch.
    ShaderEffect {
        anchors.fill: parent
        visible: overlay.active && !overlay.isFill && overlay.presetId === "matrix"
        vertexShader: "matrix.vert.qsb"
        fragmentShader: "matrix_overlay.frag.qsb"
        property variant source: baseSrc
        property double uTime: overlay.timeSec
        property real uScale: Number((overlay.params ?? {}).scale ?? 1.0)
        property real uSpeed: Number((overlay.params ?? {}).speed ?? 1.0)
        property real uOpacity: Number((overlay.params ?? {}).opacity ?? 1.0)
        property color uTint: String((overlay.params ?? {}).tint ?? "#ffffff")
    }
}
