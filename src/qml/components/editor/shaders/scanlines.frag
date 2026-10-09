#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
// Single uniform block (Qt Quick supports only one); must match
// scanlines.vert member-for-member so the pair links on strict drivers.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uFrequency;
    float uIntensity;
    float uVignette;
    float uSpeed;
    float uOpacity;
    vec4 uTint;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    // Fill replaces base rgb but keeps base alpha (coverage, strokes,
    // translucency), so output stays confined to the silhouette with
    // no extra mask. Matches ShaderEngine CPU fill.
    vec4 base = texture(source, vTexCoord);
    float t = uTime * uSpeed;
    vec2 uv = vTexCoord;
    float freq = clamp(uFrequency, 20.0, 300.0);
    float li = 0.5 + 0.5 * sin(uv.y * freq * 6.2831 + t * 2.0);
    float inten = clamp(uIntensity, 0.0, 1.0);
    float lines = 1.0 - inten * (1.0 - li);
    float d = distance(uv, vec2(0.5));
    float vig = 1.0 - clamp(uVignette, 0.0, 1.0) * smoothstep(0.3, 0.75, d);
    vec3 col = vec3(lines * vig) * uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
