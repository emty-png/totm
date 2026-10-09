#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
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
    vec4 base = texture(source, vTexCoord);
    if (base.a <= 0.001) {
        fragColor = base * qt_Opacity;
        return;
    }
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
    vec3 vor = 0.5 + 0.5 * cos(e * 6.2831 + vec3(0.6, 2.294, 6.988));
    float rim = 1.0 - smoothstep(0.1, 0.7, length(c));
    vec3 col = vor * (0.35 + 0.65 * rim) * uTint.rgb;
    float k = clamp(uOpacity, 0.0, 1.0);
    // Screen blend over base rgb (premultiplied approx, matches CPU).
    vec3 brgb = base.rgb / max(0.001, base.a);
    vec3 scr = 1.0 - (1.0 - brgb) * (1.0 - col);
    vec3 outrgb = mix(brgb, scr, k) * base.a;
    fragColor = vec4(outrgb, base.a) * qt_Opacity;
}
