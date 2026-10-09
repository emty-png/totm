#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
// Single uniform block (Qt Quick supports only one); must match
// plasma.vert member-for-member so the pair links on strict drivers.
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
    float v1 = sin(uv.x * 6.2831 * s + t * 1.7);
    float v2 = sin(uv.y * 6.2831 * s - t * 1.3);
    float v3 = sin((uv.x + uv.y) * 6.2831 * s + t * 0.9);
    float v4 = sin(length(uv) * 12.566 * s - t * 2.1);
    float v = (v1 + v2 + v3 + v4) * 0.25;
    float e = 0.5 + 0.5 * v;
    vec3 col = (0.5 + 0.5 * cos(e * 6.2831 + vec3(0.0, 2.094, 4.188))) * uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
