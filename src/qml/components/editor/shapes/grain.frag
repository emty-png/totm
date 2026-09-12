#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    uint seed;
    float amount;
    float cellSize;
};
// Integer hash shared bit-for-bit with Effects::grainHash (C++ uses the
// same 32-bit wrap), so preview matches video exactly. 65535 is odd so
// pick never lands exactly on 0.5 on either side.
uint grainHash(uvec2 c, uint s) {
    uint h = c.x * 374761393u + c.y * 668265263u + s;
    h = (h ^ (h >> 13u)) * 1274126177u;
    h ^= (h >> 16u);
    return h;
}
void main() {
    vec2 px = vTexCoord * itemSize;
    uvec2 cell = uvec2(uint(floor(px.x / cellSize)), uint(floor(px.y / cellSize)));
                uint h1 = grainHash(cell, seed);
                uint h2 = grainHash(cell, seed ^ 974634211u);
    float pick = float(h1 & 0xffffu) / 65535.0;
    float bright = float(h2 & 0xffffu) / 65535.0;
    vec3 col = pick >= 0.5 ? vec3(1.0) : vec3(0.0);
    float a = amount * (0.25 + 0.75 * bright);
    fragColor = vec4(col * a, a);
}
