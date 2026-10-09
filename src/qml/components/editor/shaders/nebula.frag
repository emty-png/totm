#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
// Single uniform block (Qt Quick supports only one); must match
// nebula.vert member-for-member so the pair links on strict drivers.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uScale;
    float uSpeed;
    float uOpacity;
    float uIntensity;
    vec4 uTint;
};
layout(binding = 1) uniform sampler2D source;
float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}
void main() {
    // Fill replaces base rgb but keeps base alpha (coverage, strokes,
    // translucency), so output stays confined to the silhouette with
    // no extra mask. Matches ShaderEngine CPU fill.
    vec4 base = texture(source, vTexCoord);
    float t = uTime * uSpeed;
    vec2 uv = vTexCoord;
    float s = max(0.1, uScale);
    vec2 p = (uv - 0.5) * 2.0;
    float n = sin(p.x * 3.0 * s + t) + sin(p.y * 4.0 * s - t * 1.3);
    n += 0.5 * sin((p.x + p.y) * 6.0 * s + t * 0.7);
    n += 0.25 * sin(length(p) * 12.0 * s - t * 1.7);
    float gas = smoothstep(-0.6, 1.4, n * 0.5);
    vec3 col = mix(vec3(0.05, 0.02, 0.12), vec3(0.35, 0.08, 0.55), smoothstep(0.0, 0.75, gas));
    col = mix(col, vec3(0.95, 0.35, 0.65), smoothstep(0.65, 1.0, gas));
    col *= clamp(uIntensity, 0.0, 1.5);
    vec2 sp = uv * vec2(90.0, 65.0) * s;
    vec2 cell = floor(sp);
    vec2 pos = fract(sp) - 0.5;
    float h = hash21(cell);
    float star = step(0.965, h) * (1.0 - smoothstep(0.0, 0.18, length(pos)));
    star *= 0.6 + 0.4 * sin(t * 3.0 + hash21(cell + 7.0) * 6.2831);
    col += vec3(1.0, 0.98, 0.95) * star;
    col *= uTint.rgb;
    col = clamp(col, vec3(0.0), vec3(1.0));
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
