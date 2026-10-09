#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
// Single uniform block (Qt Quick supports only one); must match
// clouds.vert member-for-member so the pair links on strict drivers.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uScale;
    float uSpeed;
    float uOpacity;
    float uDensity;
    vec4 uTint;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    // Fill replaces base rgb but keeps base alpha (coverage, strokes,
    // translucency), so output stays confined to the silhouette with
    // no extra mask. Sine-stack "clouds" (no hash noise) so the CPU
    // raster matches the GPU bit-for-bit. Matches ShaderEngine CPU fill.
    vec4 base = texture(source, vTexCoord);
    float t = uTime * uSpeed;
    vec2 uv = vTexCoord;
    float s = max(0.1, uScale);
    float k = 6.2831 * s;
    float n1 = sin(uv.x * k + t * 1.0);
    float n2 = sin(uv.y * k * 1.3 - t * 0.8);
    float n3 = sin((uv.x + uv.y) * k * 0.7 + t * 0.5);
    float n4 = sin(length(uv - vec2(0.5)) * k * 2.0 - t * 0.9);
    float n = (n1 + n2 + n3 + n4) * 0.25;
    float e = 0.5 + 0.5 * n;
    float e0 = clamp(1.0 - clamp(uDensity, 0.0, 1.0), 0.0, 1.0);
    float cov = smoothstep(e0, e0 + 0.4, e);
    vec3 col = uTint.rgb * cov;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
