#version 440
// Plasma fill vertex shader: uniform block byte-identical to
// plasma.frag so strict drivers never see two different `buf`
// definitions at link time (generic shader.vert only declares the
// Qt prefix, which some drivers reject when extended in fragment).
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vTexCoord;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uScale;
    float uSpeed;
    float uOpacity;
    vec4 uTint;
};
void main() {
    vTexCoord = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
