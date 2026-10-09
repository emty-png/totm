#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
// Single uniform block (Qt Quick supports only one); must match
// vortex.vert member-for-member so the pair links on strict drivers.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uZoom;
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
    vec2 c = vTexCoord - vec2(0.5);
    float zm = max(0.1, uZoom);
    vec2 p = c * zm;
    float r = length(p);
    float ang = r < 0.00001 ? 0.0 : atan(p.y, p.x);
    ang += t * (1.2 - r * 1.6) + sin(r * 9.0 - t * 2.0) * 0.35;
    vec2 q = vec2(cos(ang), sin(ang)) * r;
    float v = sin(q.x * 14.0 + t * 2.0) + sin(q.y * 14.0 - t * 1.6);
    v += sin((q.x + q.y) * 10.0 + t) + sin(r * 22.0 - t * 2.4);
    float e = fract(v * 0.25 + t * 0.05);
    vec3 col = 0.5 + 0.5 * cos(e * 6.2831 + vec3(0.6, 2.294, 6.988));
    float rim = 1.0 - smoothstep(0.1, 0.7, length(c));
    col *= (0.35 + 0.65 * rim) * uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
