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
    float uIntensity;
    vec4 uColorA;
    vec4 uColorB;
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
    float w = sin(uv.y * 6.2831 * s + t * 1.2) * 0.35;
    float ph = (uv.x * s * 2.0 + uv.y * s * 1.2 + w) * 6.2831 + t * 0.8;
    float a = 0.5 + 0.5 * sin(ph);
    float inten = clamp(uIntensity, 0.0, 1.5);
    vec3 aurora = clamp(mix(uColorA.rgb, uColorB.rgb, a) * inten, 0.0, 1.0);
    float k = clamp(uOpacity, 0.0, 1.0);
    // Screen blend over base rgb (premultiplied approx, matches CPU).
    vec3 brgb = base.rgb / max(0.001, base.a);
    vec3 scr = 1.0 - (1.0 - brgb) * (1.0 - aurora);
    vec3 outrgb = mix(brgb, scr, k) * base.a;
    fragColor = vec4(outrgb, base.a) * qt_Opacity;
}
