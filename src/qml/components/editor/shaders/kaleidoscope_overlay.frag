#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
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
    vec4 base = texture(source, vTexCoord);
    if (base.a <= 0.001) {
        fragColor = base * qt_Opacity;
        return;
    }
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
    vec3 kaleido = (0.5 + 0.5 * cos(e * 6.2831 + vec3(0.0, 2.094, 4.188))) * uTint.rgb;
    float k = clamp(uOpacity, 0.0, 1.0);
    // Screen blend over base rgb (premultiplied approx, matches CPU).
    vec3 brgb = base.rgb / max(0.001, base.a);
    vec3 scr = 1.0 - (1.0 - brgb) * (1.0 - kaleido);
    vec3 outrgb = mix(brgb, scr, k) * base.a;
    fragColor = vec4(outrgb, base.a) * qt_Opacity;
}
