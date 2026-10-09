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
    float v1 = sin(uv.x * 6.2831 * s + t * 1.7);
    float v2 = sin(uv.y * 6.2831 * s - t * 1.3);
    float v3 = sin((uv.x + uv.y) * 6.2831 * s + t * 0.9);
    float v4 = sin(length(uv) * 12.566 * s - t * 2.1);
    float v = (v1 + v2 + v3 + v4) * 0.25;
    float e = 0.5 + 0.5 * v;
    vec3 plasma = (0.5 + 0.5 * cos(e * 6.2831 + vec3(0.0, 2.094, 4.188))) * uTint.rgb;
    float k = clamp(uOpacity, 0.0, 1.0);
    // Screen blend over base rgb (premultiplied approx, matches CPU).
    vec3 brgb = base.rgb / max(0.001, base.a);
    vec3 scr = 1.0 - (1.0 - brgb) * (1.0 - plasma);
    vec3 outrgb = mix(brgb, scr, k) * base.a;
    fragColor = vec4(outrgb, base.a) * qt_Opacity;
}
