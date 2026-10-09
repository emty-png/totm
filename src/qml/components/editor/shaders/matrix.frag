#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
// Single uniform block (Qt Quick supports only one); must match
// matrix.vert member-for-member so the pair links on strict drivers.
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
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
void main() {
    // Fill replaces base rgb but keeps base alpha (coverage, strokes,
    // translucency), so output stays confined to the silhouette with
    // no extra mask. Matches ShaderEngine CPU fill.
    vec4 base = texture(source, vTexCoord);
    float t = uTime * uSpeed;
    vec2 uv = vTexCoord;
    float s = max(0.1, uScale);
    vec2 grid = vec2(48.0, 26.0) * s;
    float colId = floor(uv.x * grid.x);
    float cspd = 4.0 + 8.0 * hash12(vec2(colId, 3.7));
    vec2 g = vec2(uv.x * grid.x, uv.y * grid.y + t * cspd);
    vec2 cell = floor(g);
    vec2 f = fract(g);
    float head = hash12(vec2(colId, floor(t * 0.5) * 0.13));
    float trail = fract(head + uv.y + t * cspd / grid.y * 0.2);
    float glyph = step(0.35, hash12(vec2(cell.x, cell.y + floor(t * 8.0))));
    float glow = smoothstep(0.0, 0.25, trail) * (1.0 - smoothstep(0.55, 1.0, trail));
    float bar = step(abs(f.x - 0.5), 0.28) * step(abs(f.y - 0.5), 0.38);
    float flick = 0.55 + 0.45 * sin(t * 20.0 + hash12(cell) * 40.0);
    vec3 col = vec3(0.1, 1.0, 0.35) * bar * glyph * glow * flick;
    col += vec3(0.7, 1.0, 0.8) * bar * smoothstep(0.92, 1.0, trail);
    col += vec3(0.02, 0.06, 0.03);
    col *= uTint.rgb;
    col = clamp(col, vec3(0.0), vec3(1.0));
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
