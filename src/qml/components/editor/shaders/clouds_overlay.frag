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
    float uDensity;
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
    float k = 6.2831 * s;
    float n1 = sin(uv.x * k + t * 1.0);
    float n2 = sin(uv.y * k * 1.3 - t * 0.8);
    float n3 = sin((uv.x + uv.y) * k * 0.7 + t * 0.5);
    float n4 = sin(length(uv - vec2(0.5)) * k * 2.0 - t * 0.9);
    float n = (n1 + n2 + n3 + n4) * 0.25;
    float e = 0.5 + 0.5 * n;
    float e0 = clamp(1.0 - clamp(uDensity, 0.0, 1.0), 0.0, 1.0);
    float cov = smoothstep(e0, e0 + 0.4, e);
    vec3 clouds = uTint.rgb * cov;
    float kk = clamp(uOpacity, 0.0, 1.0);
    // Screen blend over base rgb (premultiplied approx, matches CPU).
    vec3 brgb = base.rgb / max(0.001, base.a);
    vec3 scr = 1.0 - (1.0 - brgb) * (1.0 - clouds);
    vec3 outrgb = mix(brgb, scr, kk) * base.a;
    fragColor = vec4(outrgb, base.a) * qt_Opacity;
}
