#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
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
    vec4 base = texture(source, vTexCoord);
    if (base.a <= 0.001) {
        fragColor = base * qt_Opacity;
        return;
    }
    float t = uTime * uSpeed;
    vec2 uv = vTexCoord;
    float s = max(0.1, uScale);
    float wob = sin(uv.x * 18.0 * s + t * 3.0) * 0.5 + sin(uv.x * 31.0 * s - t * 4.2) * 0.3;
    float rise = fract(uv.y + wob * 0.08 * uv.y - t * 0.15);
    float body = 1.0 - smoothstep(0.0, 1.0, rise);
    float n = sin(uv.x * 24.0 * s + t * 5.0 + sin(uv.y * 16.0 * s - t * 3.0) * 2.0);
    float flame = clamp(body * (0.65 + 0.35 * n) - uv.y * 0.25, 0.0, 1.0);
    vec3 fire = mix(vec3(0.45, 0.03, 0.0), vec3(1.0, 0.32, 0.02), smoothstep(0.05, 0.55, flame));
    fire = mix(fire, vec3(1.0, 0.9, 0.35), smoothstep(0.55, 0.95, flame)) * uTint.rgb;
    float k = clamp(uOpacity, 0.0, 1.0);
    // Screen blend over base rgb (premultiplied approx, matches CPU).
    vec3 brgb = base.rgb / max(0.001, base.a);
    vec3 scr = 1.0 - (1.0 - brgb) * (1.0 - fire);
    vec3 outrgb = mix(brgb, scr, k) * base.a;
    fragColor = vec4(outrgb, base.a) * qt_Opacity;
}
