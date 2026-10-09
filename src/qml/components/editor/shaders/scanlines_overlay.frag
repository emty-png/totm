#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uFrequency;
    float uIntensity;
    float uVignette;
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
    float freq = clamp(uFrequency, 20.0, 300.0);
    float li = 0.5 + 0.5 * sin(uv.y * freq * 6.2831 + t * 2.0);
    float inten = clamp(uIntensity, 0.0, 1.0);
    float lines = 1.0 - inten * (1.0 - li);
    float d = distance(uv, vec2(0.5));
    float vig = 1.0 - clamp(uVignette, 0.0, 1.0) * smoothstep(0.3, 0.75, d);
    vec3 tinted = uTint.rgb * (lines * vig);
    float k = clamp(uOpacity, 0.0, 1.0);
    // Multiply over base rgb (premultiplied approx, matches CPU).
    vec3 brgb = base.rgb / max(0.001, base.a);
    vec3 outrgb = mix(brgb, brgb * tinted, k) * base.a;
    fragColor = vec4(outrgb, base.a) * qt_Opacity;
}
