#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
// Single uniform block (Qt Quick supports only one); must match
// fire.vert member-for-member so the pair links on strict drivers.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uScale;
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
    float s = max(0.1, uScale);
    float wob = sin(uv.x * 18.0 * s + t * 3.0) * 0.5 + sin(uv.x * 31.0 * s - t * 4.2) * 0.3;
    float rise = fract(uv.y + wob * 0.08 * uv.y - t * 0.15);
    float body = 1.0 - smoothstep(0.0, 1.0, rise);
    float n = sin(uv.x * 24.0 * s + t * 5.0 + sin(uv.y * 16.0 * s - t * 3.0) * 2.0);
    float flame = clamp(body * (0.65 + 0.35 * n) - uv.y * 0.25, 0.0, 1.0);
    vec3 col = mix(vec3(0.45, 0.03, 0.0), vec3(1.0, 0.32, 0.02), smoothstep(0.05, 0.55, flame));
    col = mix(col, vec3(1.0, 0.9, 0.35), smoothstep(0.55, 0.95, flame)) * uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
