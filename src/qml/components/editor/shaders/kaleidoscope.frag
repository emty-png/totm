#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
// Single uniform block (Qt Quick supports only one); must match
// kaleidoscope.vert member-for-member so the pair links on strict drivers.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uSegments;
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
    vec2 p = vTexCoord - vec2(0.5);
    float r = length(p);
    float ang = r < 0.00001 ? 0.0 : atan(p.y, p.x);
    float segs = max(3.0, floor(uSegments + 0.5));
    float sector = 6.2831853 / segs;
    float a = mod(ang, sector) - sector * 0.5 + t * 0.6;
    float zm = max(0.1, uZoom);
    vec2 q = vec2(cos(a), sin(a)) * r * zm;
    float e = fract(q.x + q.y + t * 0.05);
    vec3 col = (0.5 + 0.5 * cos(e * 6.2831 + vec3(0.0, 2.094, 4.188))) * uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float al = base.a * pa;
    fragColor = vec4(col * al, al) * qt_Opacity;
}
