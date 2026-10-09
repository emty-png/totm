#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
// Single uniform block (Qt Quick supports only one); must match
// aurora.vert member-for-member so the pair links on strict drivers.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uScale;
    float uSpeed;
    float uOpacity;
    float uIntensity;
    vec4 uColorA;
    vec4 uColorB;
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
    float w = sin(uv.y * 6.2831 * s + t * 1.2) * 0.35;
    float ph = (uv.x * s * 2.0 + uv.y * s * 1.2 + w) * 6.2831 + t * 0.8;
    float a = 0.5 + 0.5 * sin(ph);
    float inten = clamp(uIntensity, 0.0, 1.5);
    vec3 col = clamp(mix(uColorA.rgb, uColorB.rgb, a) * inten, 0.0, 1.0);
    float pa = clamp(uOpacity, 0.0, 1.0);
    float al = base.a * pa;
    fragColor = vec4(col * al, al) * qt_Opacity;
}
