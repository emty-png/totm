#include "ShaderEngine.h"

#include <QColor>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#if __has_include(<QtShaderTools/QShaderBaker>)
#include <QtShaderTools/QShaderBaker>
#elif __has_include(<QShaderBaker>)
#include <QShaderBaker>
#elif __has_include(<rhi/qshaderbaker.h>)
// Distro-packaged Qt without forwarding headers (the versioned
// include dir is added in src/CMakeLists.txt).
#include <rhi/qshaderbaker.h>
#else
#error "QShaderBaker headers not found: install the QtShaderTools module (distro package qt6-shadertools or official Qt module 'qtshadertools')"
#endif
#include <QStandardPaths>
#include <QUrl>
#include <QtMath>

#include <vector>

namespace Shaders {
namespace {

double num(const QVariantMap &m, const char *key, double fallback) {
    bool ok = false;
    const double v = m.value(QLatin1String(key)).toDouble(&ok);
    return (ok && qIsFinite(v)) ? v : fallback;
}

QString str(const QVariantMap &m, const char *key, const QString &fallback) {
    const QString v = m.value(QLatin1String(key)).toString();
    return v.isEmpty() ? fallback : v;
}

QColor colorOf(const QVariant &v, const QColor &fallback) {
    const QString s = v.toString();
    if (s.isEmpty())
        return fallback;
    const QColor c(s);
    return c.isValid() ? c : fallback;
}

// Shared plasma palette: must match shaders/plasma.frag (cos ramp).
// LUT: 2048-entry cos ramp with linear interpolation. Exact to <0.1 LSB
// after int() truncation, so CPU matches the GPU cos path pixel-for-pixel
// while cutting 3 cos() calls per pixel (the remaining 4 sin() + sqrt
// dominate plasma cost and cannot LUT without blowing cache).
struct PlasmaLut {
    static constexpr int kSize = 2048;
    float r[kSize + 1];
    float g[kSize + 1];
    float b[kSize + 1];
    PlasmaLut() {
        for (int i = 0; i <= kSize; ++i) {
            const double e = double(i) / double(kSize); // 0..1
            r[i] = float(0.5 + 0.5 * qCos(e * 6.283185307179586));
            g[i] = float(0.5 + 0.5 * qCos(e * 6.283185307179586 + 2.0943951023931953));
            b[i] = float(0.5 + 0.5 * qCos(e * 6.283185307179586 + 4.188790204786391));
        }
    }
};
inline const PlasmaLut &plasmaLut() {
    static const PlasmaLut lut;
    return lut;
}
inline void plasmaLutRgb(double e01, int &r, int &g, int &b) {
    const PlasmaLut &lut = plasmaLut();
    const double e = qBound(0.0, e01, 1.0) * double(PlasmaLut::kSize - 1);
    const int i0 = int(e);
    const float f = float(e - double(i0));
    const int i1 = qMin(i0 + 1, PlasmaLut::kSize);
    const float rr = lut.r[i0] + (lut.r[i1] - lut.r[i0]) * f;
    const float gg = lut.g[i0] + (lut.g[i1] - lut.g[i0]) * f;
    const float bb = lut.b[i0] + (lut.b[i1] - lut.b[i0]) * f;
    r = qBound(0, int(255.0f * rr + 0.5f), 255);
    g = qBound(0, int(255.0f * gg + 0.5f), 255);
    b = qBound(0, int(255.0f * bb + 0.5f), 255);
}
// Tight bounds of pixels with alpha != 0. Returns false when fully
// transparent. One cheap byte-check pass that lets the expensive trig
// loops below run on the leaf bbox instead of the full frame (layers
// are full-frame transparent except for the leaf + halo).
// Fullscreen leaves skip the scan: bbox is the whole frame anyway.
inline bool coversFrame(double leafX, double leafY, double leafW, double leafH, int W, int H) {
    return leafW >= double(W) * 0.95 && leafH >= double(H) * 0.95;
}
inline bool alphaBounds(const QImage &img, int &x0, int &y0, int &x1, int &y1) {
    const int W = img.width(), H = img.height();
    int top = H, bottom = -1;
    for (int y = 0; y < H; ++y) {
        const QRgb *row = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        // Fast row reject: scan 4 at a time via 32-bit alpha bits.
        for (int x = 0; x < W; ++x) {
            if (row[x] & 0xFF000000u) {
                top = y;
                goto foundTop;
            }
        }
    }
foundTop:
    if (top == H)
        return false;
    for (int y = H - 1; y >= top; --y) {
        const QRgb *row = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < W; ++x) {
            if (row[x] & 0xFF000000u) {
                bottom = y;
                goto foundBottom;
            }
        }
    }
foundBottom:
    int left = W, right = -1;
    for (int y = top; y <= bottom; ++y) {
        const QRgb *row = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < W; ++x) {
            if (row[x] & 0xFF000000u) {
                if (x < left)
                    left = x;
                break;
            }
        }
        for (int x = W - 1; x >= left; --x) {
            if (row[x] & 0xFF000000u) {
                if (x > right)
                    right = x;
                break;
            }
        }
    }
    x0 = left;
    y0 = top;
    x1 = right + 1; // exclusive
    y1 = bottom + 1; // exclusive
    return x0 < x1 && y0 < y1;
}
void plasmaRgb(double x, double y, double t, double scale, int &r, int &g, int &b) {
    const double s = qMax(0.1, scale);
    const double v1 = qSin(x * 6.2831 * s + t * 1.7);
    const double v2 = qSin(y * 6.2831 * s - t * 1.3);
    const double v3 = qSin((x + y) * 6.2831 * s + t * 0.9);
    const double v4 = qSin(qSqrt(x * x + y * y) * 12.566 * s - t * 2.1);
    const double v = (v1 + v2 + v3 + v4) * 0.25; // -1..1
    const double e = 0.5 + 0.5 * v; // 0..1
    plasmaLutRgb(e, r, g, b);
}

// GLSL smoothstep replica: t*t*(3-2t) on the clamped edge ramp.
inline double smoothstepCpu(double e0, double e1, double x) {
    if (!(e1 > e0))
        return x < e0 ? 0.0 : 1.0;
    double t = (x - e0) / (e1 - e0);
    t = qBound(0.0, t, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// GLSL mod(x, y) replica: x - y*floor(x/y), always in [0, y) for y > 0.
// (C++ fmod keeps the sign of x, so it cannot be used for kaleidoscope
// sector folding.)
inline double glslMod(double x, double y) {
    return x - y * qFloor(x / y);
}

inline bool isKnownPreset(const QString &id) {
    return id == QLatin1String("plasma") || id == QLatin1String("aurora") || id == QLatin1String("clouds")
        || id == QLatin1String("kaleidoscope") || id == QLatin1String("scanlines") || id == QLatin1String("fire")
        || id == QLatin1String("nebula") || id == QLatin1String("vortex") || id == QLatin1String("matrix");
}

// Aurora bands: must match shaders/aurora.frag.
inline void auroraRgb(double u, double v, double t, double scale, double intensity, const QColor &cA,
    const QColor &cB, int &r, int &g, int &b) {
    const double s = qMax(0.1, scale);
    const double w = qSin(v * 6.2831 * s + t * 1.2) * 0.35;
    const double ph = (u * s * 2.0 + v * s * 1.2 + w) * 6.2831 + t * 0.8;
    const double a = 0.5 + 0.5 * qSin(ph);
    const double inten = qBound(0.0, intensity, 1.5);
    const double ar = cA.redF(), ag = cA.greenF(), ab = cA.blueF();
    const double br = cB.redF(), bg = cB.greenF(), bb = cB.blueF();
    r = qBound(0, int(qBound(0.0, (ar + (br - ar) * a) * inten, 1.0) * 255.0 + 0.5), 255);
    g = qBound(0, int(qBound(0.0, (ag + (bg - ag) * a) * inten, 1.0) * 255.0 + 0.5), 255);
    b = qBound(0, int(qBound(0.0, (ab + (bb - ab) * a) * inten, 1.0) * 255.0 + 0.5), 255);
}

// Clouds coverage 0..1 + tinted rgb: must match shaders/clouds.frag.
inline double cloudsCov(double u, double v, double t, double scale, double density) {
    const double s = qMax(0.1, scale);
    const double k = 6.2831 * s;
    const double n1 = qSin(u * k + t * 1.0);
    const double n2 = qSin(v * k * 1.3 - t * 0.8);
    const double n3 = qSin((u + v) * k * 0.7 + t * 0.5);
    const double dx = u - 0.5, dy = v - 0.5;
    const double n4 = qSin(qSqrt(dx * dx + dy * dy) * k * 2.0 - t * 0.9);
    const double e = 0.5 + 0.5 * (n1 + n2 + n3 + n4) * 0.25;
    const double e0 = qBound(0.0, 1.0 - qBound(0.0, density, 1.0), 1.0);
    return smoothstepCpu(e0, e0 + 0.4, e);
}

// Kaleidoscope palette: must match shaders/kaleidoscope.frag.
inline void kaleidoRgb(double u, double v, double t, double segments, double zoom, int &r, int &g, int &b) {
    const double px = u - 0.5, py = v - 0.5;
    const double rad = qSqrt(px * px + py * py);
    double ang = 0.0;
    if (rad >= 0.00001)
        ang = qAtan2(py, px);
    const double segs = qMax(3.0, double(qFloor(segments + 0.5)));
    const double sector = 6.2831853 / segs;
    const double a = glslMod(ang, sector) - sector * 0.5 + t * 0.6;
    const double zm = qMax(0.1, zoom);
    const double qx = qCos(a) * rad * zm, qy = qSin(a) * rad * zm;
    double e = qx + qy + t * 0.05;
    e = e - qFloor(e); // fract
    plasmaLutRgb(e, r, g, b);
}

// Scanlines pattern 0..1 (lines * vignette): must match shaders/scanlines.frag.
inline double scanPat(double u, double v, double t, double frequency, double intensity, double vignette) {
    Q_UNUSED(u);
    const double freq = qBound(20.0, frequency, 300.0);
    const double li = 0.5 + 0.5 * qSin(v * freq * 6.2831 + t * 2.0);
    const double lines = 1.0 - qBound(0.0, intensity, 1.0) * (1.0 - li);
    const double dx = u - 0.5, dy = v - 0.5;
    const double d = qSqrt(dx * dx + dy * dy);
    const double vig = 1.0 - qBound(0.0, vignette, 1.0) * smoothstepCpu(0.3, 0.75, d);
    return qBound(0.0, lines * vig, 1.0);
}

// GLSL hash replicas (double precision). A float-vs-double rounding
// difference can flip an isolated step() threshold (one star/glyph
// pixel); visually identical, never structural.
inline double hash21Cpu(double px, double py) {
    double qx = px * 234.34, qy = py * 435.345;
    qx -= qFloor(qx);
    qy -= qFloor(qy);
    const double d = qx * (qx + 34.23) + qy * (qy + 34.23);
    qx += d;
    qy += d;
    const double m = qx * qy;
    return m - qFloor(m);
}

inline double hash12Cpu(double px, double py) {
    double x = px * 0.1031, y = py * 0.1031, z = px * 0.1031;
    x -= qFloor(x);
    y -= qFloor(y);
    z -= qFloor(z);
    const double d = x * (y + 33.33) + y * (z + 33.33) + z * (x + 33.33);
    x += d;
    y += d;
    z += d;
    const double m = (x + y) * z;
    return m - qFloor(m);
}

// Fire flames 0..255: must match shaders/fire.frag.
inline void fireRgb(double u, double v, double t, double scale, int &r, int &g, int &b) {
    const double s = qMax(0.1, scale);
    const double wob = qSin(u * 18.0 * s + t * 3.0) * 0.5 + qSin(u * 31.0 * s - t * 4.2) * 0.3;
    double rise = v + wob * 0.08 * v - t * 0.15;
    rise -= qFloor(rise);
    const double body = 1.0 - smoothstepCpu(0.0, 1.0, rise);
    const double n = qSin(u * 24.0 * s + t * 5.0 + qSin(v * 16.0 * s - t * 3.0) * 2.0);
    const double flame = qBound(0.0, body * (0.65 + 0.35 * n) - v * 0.25, 1.0);
    const double m1 = smoothstepCpu(0.05, 0.55, flame);
    const double m2 = smoothstepCpu(0.55, 0.95, flame);
    double cr = 0.45 + (1.0 - 0.45) * m1;
    cr += (1.0 - cr) * m2;
    double cg = 0.03 + (0.32 - 0.03) * m1;
    cg += (0.9 - cg) * m2;
    double cb = 0.0 + (0.02 - 0.0) * m1;
    cb += (0.35 - cb) * m2;
    r = qBound(0, int(cr * 255.0 + 0.5), 255);
    g = qBound(0, int(cg * 255.0 + 0.5), 255);
    b = qBound(0, int(cb * 255.0 + 0.5), 255);
}

// Nebula gas + stars 0..255: must match shaders/nebula.frag.
inline void nebulaRgb(double u, double v, double t, double scale, double intensity, int &r, int &g, int &b) {
    const double s = qMax(0.1, scale);
    const double px = (u - 0.5) * 2.0, py = (v - 0.5) * 2.0;
    double n = qSin(px * 3.0 * s + t) + qSin(py * 4.0 * s - t * 1.3);
    n += 0.5 * qSin((px + py) * 6.0 * s + t * 0.7);
    n += 0.25 * qSin(qSqrt(px * px + py * py) * 12.0 * s - t * 1.7);
    const double gas = smoothstepCpu(-0.6, 1.4, n * 0.5);
    const double m1 = smoothstepCpu(0.0, 0.75, gas);
    const double m2 = smoothstepCpu(0.65, 1.0, gas);
    double cr = 0.05 + (0.35 - 0.05) * m1;
    cr += (0.95 - cr) * m2;
    double cg = 0.02 + (0.08 - 0.02) * m1;
    cg += (0.35 - cg) * m2;
    double cb = 0.12 + (0.55 - 0.12) * m1;
    cb += (0.65 - cb) * m2;
    const double inten = qBound(0.0, intensity, 1.5);
    cr *= inten;
    cg *= inten;
    cb *= inten;
    const double gx = u * 90.0 * s, gy = v * 65.0 * s;
    const double cx = qFloor(gx), cy = qFloor(gy);
    const double ox = gx - cx - 0.5, oy = gy - cy - 0.5;
    const double h = hash21Cpu(cx, cy);
    double star = (h >= 0.965 ? 1.0 : 0.0) * (1.0 - smoothstepCpu(0.0, 0.18, qSqrt(ox * ox + oy * oy)));
    star *= 0.6 + 0.4 * qSin(t * 3.0 + hash21Cpu(cx + 7.0, cy + 7.0) * 6.2831853);
    cr += star;
    cg += star * 0.98;
    cb += star * 0.95;
    r = qBound(0, int(qBound(0.0, cr, 1.0) * 255.0 + 0.5), 255);
    g = qBound(0, int(qBound(0.0, cg, 1.0) * 255.0 + 0.5), 255);
    b = qBound(0, int(qBound(0.0, cb, 1.0) * 255.0 + 0.5), 255);
}

// Vortex swirl 0..255: must match shaders/vortex.frag.
inline void vortexRgb(double u, double v, double t, double zoom, int &r, int &g, int &b) {
    const double cx = u - 0.5, cy = v - 0.5;
    const double zm = qMax(0.1, zoom);
    const double px = cx * zm, py = cy * zm;
    const double rad = qSqrt(px * px + py * py);
    double ang = rad < 0.00001 ? 0.0 : qAtan2(py, px);
    ang += t * (1.2 - rad * 1.6) + qSin(rad * 9.0 - t * 2.0) * 0.35;
    const double qx = qCos(ang) * rad, qy = qSin(ang) * rad;
    const double vv = qSin(qx * 14.0 + t * 2.0) + qSin(qy * 14.0 - t * 1.6) + qSin((qx + qy) * 10.0 + t)
        + qSin(rad * 22.0 - t * 2.4);
    double e = vv * 0.25 + t * 0.05;
    e -= qFloor(e);
    const double rim = 1.0 - smoothstepCpu(0.1, 0.7, qSqrt(cx * cx + cy * cy));
    const double k = 0.35 + 0.65 * rim;
    r = qBound(0, int(qBound(0.0, (0.5 + 0.5 * qCos(e * 6.2831853 + 0.6)) * k, 1.0) * 255.0 + 0.5), 255);
    g = qBound(0, int(qBound(0.0, (0.5 + 0.5 * qCos(e * 6.2831853 + 2.294)) * k, 1.0) * 255.0 + 0.5), 255);
    b = qBound(0, int(qBound(0.0, (0.5 + 0.5 * qCos(e * 6.2831853 + 6.988)) * k, 1.0) * 255.0 + 0.5), 255);
}

// Matrix code rain 0..255: must match shaders/matrix.frag.
inline void matrixRgb(double u, double v, double t, double scale, int &r, int &g, int &b) {
    const double s = qMax(0.1, scale);
    const double gx = 48.0 * s, gy = 26.0 * s;
    const double colId = qFloor(u * gx);
    const double cspd = 4.0 + 8.0 * hash12Cpu(colId, 3.7);
    const double gy2 = v * gy + t * cspd;
    const double cellX = qFloor(u * gx), cellY = qFloor(gy2);
    const double fx = u * gx - cellX, fy = gy2 - cellY;
    const double head = hash12Cpu(colId, qFloor(t * 0.5) * 0.13);
    double trail = head + v + t * cspd / gy * 0.2;
    trail -= qFloor(trail);
    const double glyph = hash12Cpu(cellX, cellY + qFloor(t * 8.0)) >= 0.35 ? 1.0 : 0.0;
    const double glow = smoothstepCpu(0.0, 0.25, trail) * (1.0 - smoothstepCpu(0.55, 1.0, trail));
    const double bar = (qAbs(fx - 0.5) <= 0.28 ? 1.0 : 0.0) * (qAbs(fy - 0.5) <= 0.38 ? 1.0 : 0.0);
    const double flick = 0.55 + 0.45 * qSin(t * 20.0 + hash12Cpu(cellX, cellY) * 40.0);
    const double headGlow = smoothstepCpu(0.92, 1.0, trail);
    const double cr = 0.1 * bar * glyph * glow * flick + 0.7 * bar * headGlow + 0.02;
    const double cg = 1.0 * bar * glyph * glow * flick + 1.0 * bar * headGlow + 0.06;
    const double cb = 0.35 * bar * glyph * glow * flick + 0.8 * bar * headGlow + 0.03;
    r = qBound(0, int(qBound(0.0, cr, 1.0) * 255.0 + 0.5), 255);
    g = qBound(0, int(qBound(0.0, cg, 1.0) * 255.0 + 0.5), 255);
    b = qBound(0, int(qBound(0.0, cb, 1.0) * 255.0 + 0.5), 255);
}

const char kSharedVert[] = R"(#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vTexCoord;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
void main() {
    vTexCoord = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
)";

const char kPlasmaVert[] = R"(#version 440
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
)";

const char kPlasmaFrag[] = R"(#version 440
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;
// Single uniform block (Qt Quick supports only one); must match
// plasma.vert member-for-member so the pair links on strict drivers.
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
    // Fill replaces base rgb but keeps base alpha (coverage, strokes,
    // translucency), so output stays confined to the silhouette with
    // no extra mask. Matches ShaderEngine CPU fill.
    vec4 base = texture(source, vTexCoord);
    float t = uTime * uSpeed;
    vec2 uv = vTexCoord;
    float s = max(0.1, uScale);
    float v1 = sin(uv.x * 6.2831 * s + t * 1.7);
    float v2 = sin(uv.y * 6.2831 * s - t * 1.3);
    float v3 = sin((uv.x + uv.y) * 6.2831 * s + t * 0.9);
    float v4 = sin(length(uv) * 12.566 * s - t * 2.1);
    float v = (v1 + v2 + v3 + v4) * 0.25;
    float e = 0.5 + 0.5 * v;
    vec3 col = (0.5 + 0.5 * cos(e * 6.2831 + vec3(0.0, 2.094, 4.188))) * uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
)";

const char kAuroraVert[] = R"(#version 440
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
    float uIntensity;
    vec4 uColorA;
    vec4 uColorB;
};
void main() {
    vTexCoord = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
)";

const char kAuroraFrag[] = R"(#version 440
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
    float t = uTime * uSpeed;
    vec2 uv = vTexCoord;
    float s = max(0.1, uScale);
    float w = sin(uv.y * 6.2831 * s + t * 1.2) * 0.35;
    float ph = (uv.x * s * 2.0 + uv.y * s * 1.2 + w) * 6.2831 + t * 0.8;
    float a = 0.5 + 0.5 * sin(ph);
    float inten = clamp(uIntensity, 0.0, 1.5);
    vec3 col = clamp(mix(uColorA.rgb, uColorB.rgb, a) * inten, 0.0, 1.0);
    float pa = clamp(uOpacity, 0.0, 1.0);
    float al = base.a * pa;
    fragColor = vec4(col * al, al) * qt_Opacity;
}
)";

const char kCloudsVert[] = R"(#version 440
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
    float uDensity;
    vec4 uTint;
};
void main() {
    vTexCoord = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
)";

const char kCloudsFrag[] = R"(#version 440
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
    vec3 col = uTint.rgb * cov;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
)";

const char kKaleidoVert[] = R"(#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vTexCoord;
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
void main() {
    vTexCoord = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
)";

const char kKaleidoFrag[] = R"(#version 440
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
    vec3 col = (0.5 + 0.5 * cos(e * 6.2831 + vec3(0.0, 2.094, 4.188))) * uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float al = base.a * pa;
    fragColor = vec4(col * al, al) * qt_Opacity;
}
)";

const char kScanVert[] = R"(#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vTexCoord;
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
void main() {
    vTexCoord = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
)";

const char kScanFrag[] = R"(#version 440
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
    float t = uTime * uSpeed;
    vec2 uv = vTexCoord;
    float freq = clamp(uFrequency, 20.0, 300.0);
    float li = 0.5 + 0.5 * sin(uv.y * freq * 6.2831 + t * 2.0);
    float inten = clamp(uIntensity, 0.0, 1.0);
    float lines = 1.0 - inten * (1.0 - li);
    float d = distance(uv, vec2(0.5));
    float vig = 1.0 - clamp(uVignette, 0.0, 1.0) * smoothstep(0.3, 0.75, d);
    vec3 col = vec3(lines * vig) * uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
)";

const char kFireVert[] = R"(#version 440
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
)";

const char kNebulaVert[] = R"(#version 440
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
    float uIntensity;
    vec4 uTint;
};
void main() {
    vTexCoord = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
)";

const char kVortexVert[] = R"(#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 vTexCoord;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uZoom;
    float uSpeed;
    float uOpacity;
    vec4 uTint;
};
void main() {
    vTexCoord = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
)";

const char kMatrixVert[] = R"(#version 440
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
)";

const char kFireFrag[] = R"(#version 440
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
    float t = uTime * uSpeed;
    vec2 uv = vTexCoord;
    float s = max(0.1, uScale);
    float wob = sin(uv.x * 18.0 * s + t * 3.0) * 0.5 + sin(uv.x * 31.0 * s - t * 4.2) * 0.3;
    float rise = fract(uv.y + wob * 0.08 * uv.y - t * 0.15);
    float body = 1.0 - smoothstep(0.0, 1.0, rise);
    float n = sin(uv.x * 24.0 * s + t * 5.0 + sin(uv.y * 16.0 * s - t * 3.0) * 2.0);
    float flame = clamp(body * (0.65 + 0.35 * n) - uv.y * 0.25, 0.0, 1.0);
    vec3 col = mix(vec3(0.45, 0.03, 0.0), vec3(1.0, 0.32, 0.02), smoothstep(0.05, 0.55, flame));
    col = mix(col, vec3(1.0, 0.9, 0.35), smoothstep(0.55, 0.95, flame)) * uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
)";

const char kNebulaFrag[] = R"(#version 440
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
    vec4 uTint;
};
layout(binding = 1) uniform sampler2D source;
float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}
void main() {
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
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
)";

const char kVortexFrag[] = R"(#version 440
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
    vec3 col = 0.5 + 0.5 * cos(e * 6.2831 + vec3(0.6, 2.294, 6.988));
    float rim = 1.0 - smoothstep(0.1, 0.7, length(c));
    col *= (0.35 + 0.65 * rim) * uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
)";

const char kMatrixFrag[] = R"(#version 440
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
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
void main() {
    vec4 base = texture(source, vTexCoord);
    float t = uTime * uSpeed;
    vec2 uv = vTexCoord;
    float s = max(0.1, uScale);
    vec2 grid = vec2(48.0, 26.0) * s;
    float colId = floor(uv.x * grid.x);
    float cspd = 4.0 + 8.0 * hash12(vec2(colId, 3.7));
    vec2 g = vec2(uv.x * grid.x, uv.y * grid.y + t * cspd);
    vec2 cell = floor(g);
    vec2 f = fract(g);
    float head = hash12(vec2(colId, floor(t * 0.5) * 0.13));
    float trail = fract(head + uv.y + t * cspd / grid.y * 0.2);
    float glyph = step(0.35, hash12(vec2(cell.x, cell.y + floor(t * 8.0))));
    float glow = smoothstep(0.0, 0.25, trail) * (1.0 - smoothstep(0.55, 1.0, trail));
    float bar = step(abs(f.x - 0.5), 0.28) * step(abs(f.y - 0.5), 0.38);
    float flick = 0.55 + 0.45 * sin(t * 20.0 + hash12(cell) * 40.0);
    vec3 col = vec3(0.1, 1.0, 0.35) * bar * glyph * glow * flick;
    col += vec3(0.7, 1.0, 0.8) * bar * smoothstep(0.92, 1.0, trail);
    col += vec3(0.02, 0.06, 0.03);
    col *= uTint.rgb;
    float pa = clamp(uOpacity, 0.0, 1.0);
    float a = base.a * pa;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
)";

} // namespace

QStringList presetIds() {
    return {QStringLiteral("plasma"), QStringLiteral("aurora"), QStringLiteral("clouds"),
        QStringLiteral("kaleidoscope"), QStringLiteral("scanlines"), QStringLiteral("fire"),
        QStringLiteral("nebula"), QStringLiteral("vortex"), QStringLiteral("matrix")};
}

QString presetName(const QString &id) {
    if (id == QLatin1String("custom"))
        return QStringLiteral("Custom");
    if (id == QLatin1String("plasma"))
        return QStringLiteral("Plasma");
    if (id == QLatin1String("aurora"))
        return QStringLiteral("Aurora");
    if (id == QLatin1String("clouds"))
        return QStringLiteral("Clouds");
    if (id == QLatin1String("kaleidoscope"))
        return QStringLiteral("Kaleidoscope");
    if (id == QLatin1String("scanlines"))
        return QStringLiteral("Scanlines");
    if (id == QLatin1String("fire"))
        return QStringLiteral("Fire");
    if (id == QLatin1String("nebula"))
        return QStringLiteral("Nebula");
    if (id == QLatin1String("vortex"))
        return QStringLiteral("Vortex");
    if (id == QLatin1String("matrix"))
        return QStringLiteral("Matrix");
    // Retired preset: kept so old designs still label correctly.
    // It no longer appears in presetIds() and renders as a no-op.
    if (id == QLatin1String("pixelate"))
        return QStringLiteral("Pixelate");
    return id;
}

QString presetDescription(const QString &id) {
    if (id == QLatin1String("custom"))
        return QStringLiteral("Custom GLSL shader (from scratch or imported)");
    if (id == QLatin1String("plasma"))
        return QStringLiteral("Animated plasma fill");
    if (id == QLatin1String("aurora"))
        return QStringLiteral("Flowing aurora bands");
    if (id == QLatin1String("clouds"))
        return QStringLiteral("Soft drifting clouds");
    if (id == QLatin1String("kaleidoscope"))
        return QStringLiteral("Mirrored kaleidoscope");
    if (id == QLatin1String("scanlines"))
        return QStringLiteral("CRT scanlines + vignette");
    if (id == QLatin1String("fire"))
        return QStringLiteral("Rising flames");
    if (id == QLatin1String("nebula"))
        return QStringLiteral("Starfield nebula");
    if (id == QLatin1String("vortex"))
        return QStringLiteral("Warped plasma swirl");
    if (id == QLatin1String("matrix"))
        return QStringLiteral("Falling code rain");
    return {};
}

QString presetMode(const QString &id) {
    if (id == QLatin1String("custom"))
        return QStringLiteral("fill");
    if (id == QLatin1String("plasma"))
        return QStringLiteral("fill");
    if (id == QLatin1String("aurora"))
        return QStringLiteral("fill");
    if (id == QLatin1String("clouds"))
        return QStringLiteral("fill");
    if (id == QLatin1String("kaleidoscope"))
        return QStringLiteral("fill");
    if (id == QLatin1String("scanlines"))
        return QStringLiteral("overlay");
    if (id == QLatin1String("fire"))
        return QStringLiteral("fill");
    if (id == QLatin1String("nebula"))
        return QStringLiteral("fill");
    if (id == QLatin1String("vortex"))
        return QStringLiteral("fill");
    if (id == QLatin1String("matrix"))
        return QStringLiteral("fill");
    // Retired pixelate was an overlay; keep the fallback so stored
    // modes on old nodes keep their interpretation (no visual effect).
    return QStringLiteral("overlay");
}

QVariantMap presetDefaults(const QString &id) {
    if (id == QLatin1String("custom"))
        return customDefaults();
    if (id == QLatin1String("plasma"))
        return {{QStringLiteral("scale"), 1.0}, {QStringLiteral("speed"), 1.0}, {QStringLiteral("opacity"), 1.0},
            {QStringLiteral("tint"), QStringLiteral("#ffffff")}};
    if (id == QLatin1String("aurora"))
        return {{QStringLiteral("scale"), 1.0}, {QStringLiteral("speed"), 1.0}, {QStringLiteral("opacity"), 1.0},
            {QStringLiteral("intensity"), 1.0}, {QStringLiteral("colorA"), QStringLiteral("#00e5ff")},
            {QStringLiteral("colorB"), QStringLiteral("#b537f2")}};
    if (id == QLatin1String("clouds"))
        return {{QStringLiteral("scale"), 1.0}, {QStringLiteral("speed"), 0.6}, {QStringLiteral("opacity"), 1.0},
            {QStringLiteral("density"), 0.5}, {QStringLiteral("tint"), QStringLiteral("#ffffff")}};
    if (id == QLatin1String("kaleidoscope"))
        return {{QStringLiteral("segments"), 6.0}, {QStringLiteral("zoom"), 1.2}, {QStringLiteral("speed"), 1.0},
            {QStringLiteral("opacity"), 1.0}, {QStringLiteral("tint"), QStringLiteral("#ffffff")}};
    if (id == QLatin1String("scanlines"))
        return {{QStringLiteral("frequency"), 120.0}, {QStringLiteral("intensity"), 0.5},
            {QStringLiteral("vignette"), 0.4}, {QStringLiteral("speed"), 1.0}, {QStringLiteral("opacity"), 1.0},
            {QStringLiteral("tint"), QStringLiteral("#ffffff")}};
    if (id == QLatin1String("fire"))
        return {{QStringLiteral("scale"), 1.0}, {QStringLiteral("speed"), 1.0}, {QStringLiteral("opacity"), 1.0},
            {QStringLiteral("tint"), QStringLiteral("#ffffff")}};
    if (id == QLatin1String("nebula"))
        return {{QStringLiteral("scale"), 1.0}, {QStringLiteral("speed"), 1.0}, {QStringLiteral("opacity"), 1.0},
            {QStringLiteral("intensity"), 1.0}, {QStringLiteral("tint"), QStringLiteral("#ffffff")}};
    if (id == QLatin1String("vortex"))
        return {{QStringLiteral("zoom"), 1.2}, {QStringLiteral("speed"), 1.0}, {QStringLiteral("opacity"), 1.0},
            {QStringLiteral("tint"), QStringLiteral("#ffffff")}};
    if (id == QLatin1String("matrix"))
        return {{QStringLiteral("scale"), 1.0}, {QStringLiteral("speed"), 1.0}, {QStringLiteral("opacity"), 1.0},
            {QStringLiteral("tint"), QStringLiteral("#ffffff")}};
    return {};
}

QVariantList presetSchema(const QString &id) {
    if (id == QLatin1String("custom"))
        return customSchema();
    if (id == QLatin1String("plasma")) {
        return {QVariantMap{{QStringLiteral("name"), QStringLiteral("scale")}, {QStringLiteral("type"), QStringLiteral("float")},
                    {QStringLiteral("min"), 0.2}, {QStringLiteral("max"), 3.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("speed")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 4.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("opacity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("tint")}, {QStringLiteral("type"), QStringLiteral("color")},
                {QStringLiteral("def"), QStringLiteral("#ffffff")}}};
    }
    if (id == QLatin1String("aurora")) {
        return {QVariantMap{{QStringLiteral("name"), QStringLiteral("scale")}, {QStringLiteral("type"), QStringLiteral("float")},
                    {QStringLiteral("min"), 0.2}, {QStringLiteral("max"), 3.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("speed")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 4.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("opacity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("intensity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.5}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("colorA")}, {QStringLiteral("type"), QStringLiteral("color")},
                {QStringLiteral("def"), QStringLiteral("#00e5ff")}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("colorB")}, {QStringLiteral("type"), QStringLiteral("color")},
                {QStringLiteral("def"), QStringLiteral("#b537f2")}}};
    }
    if (id == QLatin1String("clouds")) {
        return {QVariantMap{{QStringLiteral("name"), QStringLiteral("scale")}, {QStringLiteral("type"), QStringLiteral("float")},
                    {QStringLiteral("min"), 0.2}, {QStringLiteral("max"), 3.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("speed")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 4.0}, {QStringLiteral("def"), 0.6}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("opacity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("density")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 0.5}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("tint")}, {QStringLiteral("type"), QStringLiteral("color")},
                {QStringLiteral("def"), QStringLiteral("#ffffff")}}};
    }
    if (id == QLatin1String("kaleidoscope")) {
        return {QVariantMap{{QStringLiteral("name"), QStringLiteral("segments")}, {QStringLiteral("type"), QStringLiteral("float")},
                    {QStringLiteral("min"), 3.0}, {QStringLiteral("max"), 12.0}, {QStringLiteral("def"), 6.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("zoom")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.5}, {QStringLiteral("max"), 3.0}, {QStringLiteral("def"), 1.2}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("speed")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 4.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("opacity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("tint")}, {QStringLiteral("type"), QStringLiteral("color")},
                {QStringLiteral("def"), QStringLiteral("#ffffff")}}};
    }
    if (id == QLatin1String("scanlines")) {
        return {QVariantMap{{QStringLiteral("name"), QStringLiteral("frequency")}, {QStringLiteral("type"), QStringLiteral("float")},
                    {QStringLiteral("min"), 20.0}, {QStringLiteral("max"), 300.0}, {QStringLiteral("def"), 120.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("intensity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 0.5}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("vignette")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 0.4}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("speed")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 4.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("opacity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("tint")}, {QStringLiteral("type"), QStringLiteral("color")},
                {QStringLiteral("def"), QStringLiteral("#ffffff")}}};
    }
    if (id == QLatin1String("fire")) {
        return {QVariantMap{{QStringLiteral("name"), QStringLiteral("scale")}, {QStringLiteral("type"), QStringLiteral("float")},
                    {QStringLiteral("min"), 0.2}, {QStringLiteral("max"), 3.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("speed")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 4.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("opacity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("tint")}, {QStringLiteral("type"), QStringLiteral("color")},
                {QStringLiteral("def"), QStringLiteral("#ffffff")}}};
    }
    if (id == QLatin1String("nebula")) {
        return {QVariantMap{{QStringLiteral("name"), QStringLiteral("scale")}, {QStringLiteral("type"), QStringLiteral("float")},
                    {QStringLiteral("min"), 0.2}, {QStringLiteral("max"), 3.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("speed")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 4.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("opacity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("intensity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.5}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("tint")}, {QStringLiteral("type"), QStringLiteral("color")},
                {QStringLiteral("def"), QStringLiteral("#ffffff")}}};
    }
    if (id == QLatin1String("vortex")) {
        return {QVariantMap{{QStringLiteral("name"), QStringLiteral("zoom")}, {QStringLiteral("type"), QStringLiteral("float")},
                    {QStringLiteral("min"), 0.5}, {QStringLiteral("max"), 3.0}, {QStringLiteral("def"), 1.2}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("speed")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 4.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("opacity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("tint")}, {QStringLiteral("type"), QStringLiteral("color")},
                {QStringLiteral("def"), QStringLiteral("#ffffff")}}};
    }
    if (id == QLatin1String("matrix")) {
        return {QVariantMap{{QStringLiteral("name"), QStringLiteral("scale")}, {QStringLiteral("type"), QStringLiteral("float")},
                    {QStringLiteral("min"), 0.2}, {QStringLiteral("max"), 3.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("speed")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 4.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("opacity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 1.0}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("tint")}, {QStringLiteral("type"), QStringLiteral("color")},
                {QStringLiteral("def"), QStringLiteral("#ffffff")}}};
    }
    return {};
}

QVariantMap customDefaults() {
    return {{QStringLiteral("tint"), QStringLiteral("#ffffff")}, {QStringLiteral("opacity"), 1.0},
        {QStringLiteral("speed"), 1.0}};
}

QVariantList customSchema() {
    return {QVariantMap{{QStringLiteral("name"), QStringLiteral("opacity")}, {QStringLiteral("type"), QStringLiteral("float")},
                {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 1.0}, {QStringLiteral("def"), 1.0}},
        QVariantMap{{QStringLiteral("name"), QStringLiteral("speed")}, {QStringLiteral("type"), QStringLiteral("float")},
            {QStringLiteral("min"), 0.0}, {QStringLiteral("max"), 4.0}, {QStringLiteral("def"), 1.0}},
        QVariantMap{{QStringLiteral("name"), QStringLiteral("tint")}, {QStringLiteral("type"), QStringLiteral("color")},
            {QStringLiteral("def"), QStringLiteral("#ffffff")}}};
}

QString customTemplateVertex() {
    return QStringLiteral("#version 440\n"
                          "layout(location = 0) in vec4 qt_Vertex;\n"
                          "layout(location = 1) in vec2 qt_MultiTexCoord0;\n"
                          "layout(location = 0) out vec2 vTexCoord;\n"
                          "layout(std140, binding = 0) uniform buf {\n"
                          "    mat4 qt_Matrix;\n"
                          "    float qt_Opacity;\n"
                          "    float uTime;\n"
                          "    float uOpacity;\n"
                          "    vec4 uTint;\n"
                          "};\n"
                          "void main() {\n"
                          "    vTexCoord = qt_MultiTexCoord0;\n"
                          "    gl_Position = qt_Matrix * qt_Vertex;\n"
                          "}\n");
}

QString customTemplateFragment() {
    return QStringLiteral("#version 440\n"
                          "layout(location = 0) in vec2 vTexCoord;\n"
                          "layout(location = 0) out vec4 fragColor;\n"
                          "layout(std140, binding = 0) uniform buf {\n"
                          "    mat4 qt_Matrix;\n"
                          "    float qt_Opacity;\n"
                          "    float uTime;\n"
                          "    float uOpacity;\n"
                          "    vec4 uTint;\n"
                          "};\n"
                          "layout(binding = 1) uniform sampler2D source;\n"
                          "void main() {\n"
                          "    vec4 base = texture(source, vTexCoord);\n"
                          "    float pulse = 0.5 + 0.5 * sin(uTime * 2.0 + vTexCoord.x * 6.2831);\n"
                          "    vec3 col = uTint.rgb * (0.75 + 0.25 * pulse);\n"
                          "    float a = base.a * clamp(uOpacity, 0.0, 1.0);\n"
                          "    fragColor = vec4(col * a, a) * qt_Opacity;\n"
                          "}\n");
}

QString customContractError(const QString &vertex, const QString &fragment) {
    static const QRegularExpression mainRe(QStringLiteral("\\bvoid\\s+main\\s*\\("));
    if (!vertex.contains(mainRe))
        return QStringLiteral("Vertex shader must contain void main.");
    if (!fragment.contains(mainRe))
        return QStringLiteral("Fragment shader must contain void main.");
    if (!vertex.contains(QLatin1String("qt_Matrix")))
        return QStringLiteral("Vertex shader must declare qt_Matrix in its uniform block.");
    if (!vertex.contains(QLatin1String("qt_Opacity")))
        return QStringLiteral("Vertex shader must declare qt_Opacity in its uniform block.");
    if (!vertex.contains(QLatin1String("vTexCoord")))
        return QStringLiteral("Vertex shader must pass vTexCoord to the fragment stage.");
    static const QRegularExpression samplerRe(QStringLiteral("sampler2D\\s+source\\b"));
    if (!fragment.contains(samplerRe))
        return QStringLiteral("Fragment shader must declare `uniform sampler2D source` (the base paint sampler).");
    if (!fragment.contains(QLatin1String("vTexCoord")))
        return QStringLiteral("Fragment shader must read vTexCoord.");
    if (!fragment.contains(QLatin1String("uTime")))
        return QStringLiteral("Fragment shader must declare uniform float uTime.");
    if (!fragment.contains(QLatin1String("uOpacity")))
        return QStringLiteral("Fragment shader must declare uniform float uOpacity.");
    if (!fragment.contains(QLatin1String("uTint")))
        return QStringLiteral("Fragment shader must declare uniform vec4 uTint.");
    // Strict drivers reject vert/frag pairs whose uniform blocks differ:
    // both stages bake separately, so catch member drift textually here
    // instead of a silent GPU link failure on canvas (base would vanish
    // in fill mode before the Ready-gate fallback).
    static const QRegularExpression bufRe(QStringLiteral("uniform\\s+buf\\s*\\{([^}]*)\\}"));
    const auto vm = bufRe.match(vertex);
    const auto fm = bufRe.match(fragment);
    if (vm.hasMatch() && fm.hasMatch()) {
        auto norm = [](const QString &s) {
            QString t = s;
            t.remove(QRegularExpression(QStringLiteral("\\s+")));
            return t;
        };
        if (norm(vm.captured(1)) != norm(fm.captured(1)))
            return QStringLiteral("Vertex and fragment uniform blocks `buf` must match member-for-member.");
    }
    return {};
}

QStringList shaderFileSuffixes() {
    return {QStringLiteral("vert"), QStringLiteral("frag"), QStringLiteral("vs"), QStringLiteral("fs"),
        QStringLiteral("glsl"), QStringLiteral("txt")};
}

QVariantMap readShaderFile(const QUrl &url) {
    QVariantMap out;
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    const QFileInfo info(path);
    out[QStringLiteral("fileName")] = info.fileName();
    out[QStringLiteral("size")] = 0;
    if (!url.isLocalFile() || !info.isFile()) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("Pick a local shader file.");
        return out;
    }
    if (info.size() > 128 * 1024) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("Shader file is too large (128 KB max).");
        out[QStringLiteral("size")] = info.size();
        return out;
    }
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("Could not read the shader file.");
        return out;
    }
    const QByteArray raw = f.readAll();
    out[QStringLiteral("size")] = raw.size();
    // Strict UTF-8: fromUtf8 lossy round-trip check rejects binary blobs.
    const QString text = QString::fromUtf8(raw);
    if (!raw.isEmpty() && text.toUtf8() != raw) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("Shader file is not valid UTF-8 text.");
        return out;
    }
    out[QStringLiteral("ok")] = true;
    out[QStringLiteral("text")] = text;
    out[QStringLiteral("error")] = QString();
    return out;
}

namespace {
// In-process bake via QShaderBaker (QtShaderTools): same --qt6 target set
// as the qsb tool (SPIR-V + GLSL 100es/120/150 + HLSL 50 + MSL 12), so
// packaged builds need no external tool next to the app.
bool bakeStage(const QByteArray &src, QShader::Stage stage, QByteArray *outSerialized, QString *err) {
    QShaderBaker baker;
    baker.setSourceString(src, stage);
    // Both calls are required: an empty variants list bakes zero shaders
    // (invalid pack, empty error), and qsb strips debug info by default.
    baker.setGeneratedShaderVariants({QShader::StandardShader});
    baker.setSpirvOptions(QShaderBaker::SpirvOption::StripDebugAndVarInfo);
    baker.setGeneratedShaders({
        {QShader::SpirvShader, QShaderVersion(100)},
        {QShader::GlslShader, QShaderVersion(100, QShaderVersion::GlslEs)},
        {QShader::GlslShader, QShaderVersion(120)},
        {QShader::GlslShader, QShaderVersion(150)},
        {QShader::HlslShader, QShaderVersion(50)},
        {QShader::MslShader, QShaderVersion(12)},
    });
    QShader shader = baker.bake();
    if (!shader.isValid()) {
        if (err)
            *err = baker.errorMessage().trimmed().left(2048);
        return false;
    }
    const QByteArray blob = shader.serialized();
    if (blob.size() <= 256) {
        if (err)
            *err = QStringLiteral("Baker produced an empty shader pack.");
        return false;
    }
    if (outSerialized)
        *outSerialized = blob;
    return true;
}

bool qsbOutputSane(const QString &outPath) {
    // Bake success is the real gate; this only rejects truncated writes
    // (real outputs are kilobytes: headers plus several translations).
    const QFileInfo fi(outPath);
    return fi.isFile() && fi.size() > 256;
}

// In-memory bake results by source hash: binding evaluations run per
// custom node on the GUI thread, so repeat nodes reuse the result
// without file I/O or re-baking.
QHash<QString, QVariantMap> &bakeMemCache() {
    static QHash<QString, QVariantMap> cache;
    return cache;
}
} // namespace

QVariantMap compileCustom(const QString &vertex, const QString &fragment) {
    QVariantMap out;
    QString err;
    if (!validateShaders(vertex, fragment, &err)) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = err;
        out[QStringLiteral("log")] = QString();
        return out;
    }
    const QString contract = customContractError(vertex, fragment);
    if (!contract.isEmpty()) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = contract;
        out[QStringLiteral("log")] = QString();
        return out;
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(vertex.toUtf8());
    hash.addData(QByteArrayView("\0", 1));
    hash.addData(fragment.toUtf8());
    const QString key = QString::fromLatin1(hash.result().toHex()).left(16);
    auto memHit = bakeMemCache().constFind(key);
    if (memHit != bakeMemCache().constEnd()) {
        // Verify sources still match (collision-safe); file outputs are
        // re-checked below so a cleared cache dir re-bakes cleanly.
        const QVariantMap cached = memHit.value();
        if (cached.value(QStringLiteral("vertexSrc")).toString() == vertex
            && cached.value(QStringLiteral("fragmentSrc")).toString() == fragment) {
            const QString cv = cached.value(QStringLiteral("vertPath")).toString();
            const QString cf = cached.value(QStringLiteral("fragPath")).toString();
            if (!cv.isEmpty() && QFileInfo(QUrl(cv).toLocalFile()).isFile() && qsbOutputSane(QUrl(cv).toLocalFile())
                && !cf.isEmpty() && QFileInfo(QUrl(cf).toLocalFile()).isFile()
                && qsbOutputSane(QUrl(cf).toLocalFile())) {
                QVariantMap hit;
                hit[QStringLiteral("ok")] = true;
                hit[QStringLiteral("vertUrl")] = cv;
                hit[QStringLiteral("fragUrl")] = cf;
                hit[QStringLiteral("error")] = QString();
                hit[QStringLiteral("log")] = cached.value(QStringLiteral("log")).toString();
                return hit;
            }
        }
    }
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
        + QStringLiteral("/totm/custom_shaders");
    QDir().mkpath(dir);
    const QString vertPath = dir + QLatin1Char('/') + key + QStringLiteral(".vert");
    const QString fragPath = dir + QLatin1Char('/') + key + QStringLiteral(".frag");
    const QString vertQsb = vertPath + QStringLiteral(".qsb");
    const QString fragQsb = fragPath + QStringLiteral(".qsb");
    // Cache hit: same sources already baked (compare stored sources so
    // a hash collision or partial write can never serve stale .qsb).
    QFile ev(vertPath), ef(fragPath);
    if (QFileInfo(vertQsb).isFile() && QFileInfo(fragQsb).isFile() && ev.open(QIODevice::ReadOnly)
        && ef.open(QIODevice::ReadOnly)) {
        const bool hit = QString::fromUtf8(ev.readAll()) == vertex && QString::fromUtf8(ef.readAll()) == fragment
            && qsbOutputSane(vertQsb) && qsbOutputSane(fragQsb);
        if (hit) {
            out[QStringLiteral("ok")] = true;
            out[QStringLiteral("vertUrl")] = QUrl::fromLocalFile(vertQsb).toString();
            out[QStringLiteral("fragUrl")] = QUrl::fromLocalFile(fragQsb).toString();
            out[QStringLiteral("error")] = QString();
            out[QStringLiteral("log")] = QString();
            QVariantMap mem;
            mem[QStringLiteral("vertexSrc")] = vertex;
            mem[QStringLiteral("fragmentSrc")] = fragment;
            mem[QStringLiteral("vertPath")] = out[QStringLiteral("vertUrl")].toString();
            mem[QStringLiteral("fragPath")] = out[QStringLiteral("fragUrl")].toString();
            mem[QStringLiteral("log")] = QString();
            bakeMemCache().insert(key, mem);
            return out;
        }
    }
    QFile wv(vertPath), wf(fragPath);
    if (!wv.open(QIODevice::WriteOnly | QIODevice::Truncate) || !wf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("Could not write the shader cache.");
        out[QStringLiteral("log")] = QString();
        return out;
    }
    wv.write(vertex.toUtf8());
    wf.write(fragment.toUtf8());
    wv.close();
    wf.close();
    QString vertErr, fragErr;
    QByteArray vertBlob, fragBlob;
    QFile::remove(vertQsb);
    QFile::remove(fragQsb);
    const bool vok = bakeStage(vertex.toUtf8(), QShader::VertexStage, &vertBlob, &vertErr);
    const bool fok = vok && bakeStage(fragment.toUtf8(), QShader::FragmentStage, &fragBlob, &fragErr);
    const QString log = (vertErr + QLatin1Char('\n') + fragErr).trimmed().left(2048);
    if (!vok || !fok) {
        QFile::remove(vertQsb);
        QFile::remove(fragQsb);
        bakeMemCache().remove(key);
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("Shader failed to compile (see log).");
        out[QStringLiteral("log")] = log;
        return out;
    }
    QFile ov(vertQsb), of(fragQsb);
    const bool wrote = ov.open(QIODevice::WriteOnly | QIODevice::Truncate) && ov.write(vertBlob) == vertBlob.size()
        && of.open(QIODevice::WriteOnly | QIODevice::Truncate) && of.write(fragBlob) == fragBlob.size();
    ov.close();
    of.close();
    if (!wrote || !qsbOutputSane(vertQsb) || !qsbOutputSane(fragQsb)) {
        QFile::remove(vertQsb);
        QFile::remove(fragQsb);
        bakeMemCache().remove(key);
        out[QStringLiteral("ok")] = false;
        out[QStringLiteral("error")] = QStringLiteral("Could not write the shader cache.");
        out[QStringLiteral("log")] = log;
        return out;
    }
    out[QStringLiteral("ok")] = true;
    out[QStringLiteral("vertUrl")] = QUrl::fromLocalFile(vertQsb).toString();
    out[QStringLiteral("fragUrl")] = QUrl::fromLocalFile(fragQsb).toString();
    out[QStringLiteral("error")] = QString();
    out[QStringLiteral("log")] = log;
    QVariantMap mem;
    mem[QStringLiteral("vertexSrc")] = vertex;
    mem[QStringLiteral("fragmentSrc")] = fragment;
    mem[QStringLiteral("vertPath")] = out[QStringLiteral("vertUrl")].toString();
    mem[QStringLiteral("fragPath")] = out[QStringLiteral("fragUrl")].toString();
    mem[QStringLiteral("log")] = log;
    bakeMemCache().insert(key, mem);
    return out;
}

QString presetVertex(const QString &id) {
    if (id == QLatin1String("custom"))
        return {};
    if (id == QLatin1String("fire"))
        return QString::fromLatin1(kFireVert);
    if (id == QLatin1String("nebula"))
        return QString::fromLatin1(kNebulaVert);
    if (id == QLatin1String("vortex"))
        return QString::fromLatin1(kVortexVert);
    if (id == QLatin1String("matrix"))
        return QString::fromLatin1(kMatrixVert);
    if (id == QLatin1String("plasma"))
        return QString::fromLatin1(kPlasmaVert);
    if (id == QLatin1String("aurora"))
        return QString::fromLatin1(kAuroraVert);
    if (id == QLatin1String("clouds"))
        return QString::fromLatin1(kCloudsVert);
    if (id == QLatin1String("kaleidoscope"))
        return QString::fromLatin1(kKaleidoVert);
    if (id == QLatin1String("scanlines"))
        return QString::fromLatin1(kScanVert);
    Q_UNUSED(id);
    return QString::fromLatin1(kSharedVert);
}

QString presetFragment(const QString &id) {
    if (id == QLatin1String("custom"))
        return {};
    if (id == QLatin1String("fire"))
        return QString::fromLatin1(kFireFrag);
    if (id == QLatin1String("nebula"))
        return QString::fromLatin1(kNebulaFrag);
    if (id == QLatin1String("vortex"))
        return QString::fromLatin1(kVortexFrag);
    if (id == QLatin1String("matrix"))
        return QString::fromLatin1(kMatrixFrag);
    if (id == QLatin1String("plasma"))
        return QString::fromLatin1(kPlasmaFrag);
    if (id == QLatin1String("aurora"))
        return QString::fromLatin1(kAuroraFrag);
    if (id == QLatin1String("clouds"))
        return QString::fromLatin1(kCloudsFrag);
    if (id == QLatin1String("kaleidoscope"))
        return QString::fromLatin1(kKaleidoFrag);
    if (id == QLatin1String("scanlines"))
        return QString::fromLatin1(kScanFrag);
    return {};
}

bool isShaderableType(const QString &type) {
    return type == QLatin1String("rectangle") || type == QLatin1String("ellipse")
        || type == QLatin1String("triangle") || type == QLatin1String("star")
        || type == QLatin1String("pen") || type == QLatin1String("boolean");
}

QString normMode(const QString &mode, const QString &presetId) {
    if (mode == QLatin1String("fill") || mode == QLatin1String("overlay"))
        return mode;
    return presetMode(presetId);
}

QVariantMap normParams(const QString &presetId, const QVariantMap &params) {
    QVariantMap def = presetDefaults(presetId);
    if (def.isEmpty())
        return {};
    QVariantMap out = def;
    for (auto it = params.constBegin(); it != params.constEnd(); ++it) {
        if (!def.contains(it.key()))
            continue;
        // Color uniforms carry hex strings in defaults; normalize any
        // such key as a color (aurora colorA/colorB, clouds tint).
        const QVariant defVal = def.value(it.key());
        if (defVal.typeId() == QMetaType::QString && QColor(defVal.toString()).isValid()
            && QColor(it.value().toString()).isValid()) {
            out[it.key()] = QColor(it.value().toString()).name();
            continue;
        }
        if (it.key() == QLatin1String("color")) {
            const QColor c = colorOf(it.value(), QColor(def.value(it.key()).toString()));
            out[it.key()] = c.name();
            continue;
        }
        bool ok = false;
        double v = it.value().toDouble(&ok);
        if (!ok || !qIsFinite(v))
            continue;
        // Clamp per schema.
        for (const QVariant &s : presetSchema(presetId)) {
            const QVariantMap sm = s.toMap();
            if (sm.value(QStringLiteral("name")).toString() != it.key())
                continue;
            v = qBound(sm.value(QStringLiteral("min"), 0.0).toDouble(),
                v, sm.value(QStringLiteral("max"), 1.0).toDouble());
        }
        out[it.key()] = v;
    }
    return out;
}

bool validateShaders(const QString &vertex, const QString &fragment, QString *error) {
    auto fail = [&](const QString &m) {
        if (error)
            *error = m;
        return false;
    };
    // Word-boundaried main: a bare substring match would accept
    // "void mainImage(" (Shadertoy) as a valid entry point.
    static const QRegularExpression mainRe(QStringLiteral("\\bvoid\\s+main\\s*\\("));
    if (!vertex.contains(mainRe))
        return fail(QStringLiteral("Vertex shader must contain void main."));
    if (!fragment.contains(mainRe))
        return fail(QStringLiteral("Fragment shader must contain void main."));
    if (vertex.size() > 64 * 1024 || fragment.size() > 128 * 1024)
        return fail(QStringLiteral("Shader source is too large."));
    return true;
}

QVariantList parseUniforms(const QString &fragment) {
    QVariantList out;
    static const QRegularExpression re(QStringLiteral("uniform\\s+(float|vec2|vec3|vec4)\\s+(\\w+)\\s*;"));
    auto it = re.globalMatch(fragment);
    while (it.hasNext()) {
        const auto m = it.next();
        out.append(QVariantMap{{QStringLiteral("type"), m.captured(1)}, {QStringLiteral("name"), m.captured(2)}});
    }
    // Include color-ish vec4 as color for the panel.
    static const QRegularExpression reColor(QStringLiteral("uniform\\s+vec4\\s+(\\w*[Cc]olor\\w*)\\s*;"));
    Q_UNUSED(reColor);
    return out;
}

QImage generateFill(int w, int h, const QString &presetId, const QVariantMap &params, double timeSec) {
    const int W = qMax(1, w), H = qMax(1, h);
    QImage img(W, H, QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    if (presetId == QLatin1String("plasma")) {
        const double scale = qMax(0.1, num(params, "scale", 1.0));
        const double speed = num(params, "speed", 1.0);
        const double op = qBound(0.0, num(params, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(params.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        const double t = timeSec * speed;
        for (int y = 0; y < H; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5) / double(H);
            for (int x = 0; x < W; ++x) {
                const double u = (double(x) + 0.5) / double(W);
                int r, g, b;
                plasmaRgb(u, v, t, scale, r, g, b);
                const int a = int(255 * op);
                row[x] = qRgba(int(r * tr * op + 0.5), int(g * tg * op + 0.5), int(b * tb * op + 0.5), a);
            }
        }
    } else if (presetId == QLatin1String("aurora")) {
        const double scale = qMax(0.1, num(params, "scale", 1.0));
        const double speed = num(params, "speed", 1.0);
        const double op = qBound(0.0, num(params, "opacity", 1.0), 1.0);
        const double inten = num(params, "intensity", 1.0);
        const QColor cA = colorOf(params.value(QStringLiteral("colorA")), QColor(QStringLiteral("#00e5ff")));
        const QColor cB = colorOf(params.value(QStringLiteral("colorB")), QColor(QStringLiteral("#b537f2")));
        const double t = timeSec * speed;
        for (int y = 0; y < H; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5) / double(H);
            for (int x = 0; x < W; ++x) {
                const double u = (double(x) + 0.5) / double(W);
                int r, g, b;
                auroraRgb(u, v, t, scale, inten, cA, cB, r, g, b);
                const int a = int(255 * op);
                row[x] = qRgba(int(r * op), int(g * op), int(b * op), a);
            }
        }
    } else if (presetId == QLatin1String("clouds")) {
        const double scale = qMax(0.1, num(params, "scale", 1.0));
        const double speed = num(params, "speed", 0.6);
        const double op = qBound(0.0, num(params, "opacity", 1.0), 1.0);
        const double density = num(params, "density", 0.5);
        const QColor tint = colorOf(params.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double t = timeSec * speed;
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        for (int y = 0; y < H; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5) / double(H);
            for (int x = 0; x < W; ++x) {
                const double u = (double(x) + 0.5) / double(W);
                const double cov = cloudsCov(u, v, t, scale, density);
                const int r = qBound(0, int(tr * cov * op * 255.0 + 0.5), 255);
                const int g = qBound(0, int(tg * cov * op * 255.0 + 0.5), 255);
                const int b = qBound(0, int(tb * cov * op * 255.0 + 0.5), 255);
                const int a = int(255 * op);
                row[x] = qRgba(int(r * 1.0), int(g * 1.0), int(b * 1.0), a);
            }
        }
    } else if (presetId == QLatin1String("kaleidoscope")) {
        const double segs = num(params, "segments", 6.0);
        const double zoom = num(params, "zoom", 1.2);
        const double speed = num(params, "speed", 1.0);
        const double op = qBound(0.0, num(params, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(params.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        const double t = timeSec * speed;
        for (int y = 0; y < H; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5) / double(H);
            for (int x = 0; x < W; ++x) {
                const double u = (double(x) + 0.5) / double(W);
                int r, g, b;
                kaleidoRgb(u, v, t, segs, zoom, r, g, b);
                const int a = int(255 * op);
                row[x] = qRgba(int(r * tr * op), int(g * tg * op), int(b * tb * op), a);
            }
        }
    } else if (presetId == QLatin1String("scanlines")) {
        const double freq = num(params, "frequency", 120.0);
        const double inten = num(params, "intensity", 0.5);
        const double vig = num(params, "vignette", 0.4);
        const double speed = num(params, "speed", 1.0);
        const double op = qBound(0.0, num(params, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(params.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        const double t = timeSec * speed;
        for (int y = 0; y < H; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5) / double(H);
            for (int x = 0; x < W; ++x) {
                const double u = (double(x) + 0.5) / double(W);
                const double pat = scanPat(u, v, t, freq, inten, vig);
                const int rr = qBound(0, int(pat * tr * op * 255.0 + 0.5), 255);
                const int gg = qBound(0, int(pat * tg * op * 255.0 + 0.5), 255);
                const int bb = qBound(0, int(pat * tb * op * 255.0 + 0.5), 255);
                const int a = int(255 * op);
                row[x] = qRgba(rr, gg, bb, a);
            }
        }
    } else if (presetId == QLatin1String("fire")) {
        const double scale = qMax(0.1, num(params, "scale", 1.0));
        const double speed = num(params, "speed", 1.0);
        const double op = qBound(0.0, num(params, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(params.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        const double t = timeSec * speed;
        for (int y = 0; y < H; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5) / double(H);
            for (int x = 0; x < W; ++x) {
                const double u = (double(x) + 0.5) / double(W);
                int r, g, b;
                fireRgb(u, v, t, scale, r, g, b);
                const int a = int(255 * op);
                row[x] = qRgba(int(r * tr * op), int(g * tg * op), int(b * tb * op), a);
            }
        }
    } else if (presetId == QLatin1String("nebula")) {
        const double scale = qMax(0.1, num(params, "scale", 1.0));
        const double speed = num(params, "speed", 1.0);
        const double op = qBound(0.0, num(params, "opacity", 1.0), 1.0);
        const double inten = num(params, "intensity", 1.0);
        const QColor tint = colorOf(params.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        const double t = timeSec * speed;
        for (int y = 0; y < H; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5) / double(H);
            for (int x = 0; x < W; ++x) {
                const double u = (double(x) + 0.5) / double(W);
                int r, g, b;
                nebulaRgb(u, v, t, scale, inten, r, g, b);
                const int a = int(255 * op);
                row[x] = qRgba(int(r * tr * op), int(g * tg * op), int(b * tb * op), a);
            }
        }
    } else if (presetId == QLatin1String("vortex")) {
        const double zoom = qMax(0.1, num(params, "zoom", 1.2));
        const double speed = num(params, "speed", 1.0);
        const double op = qBound(0.0, num(params, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(params.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        const double t = timeSec * speed;
        for (int y = 0; y < H; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5) / double(H);
            for (int x = 0; x < W; ++x) {
                const double u = (double(x) + 0.5) / double(W);
                int r, g, b;
                vortexRgb(u, v, t, zoom, r, g, b);
                const int a = int(255 * op);
                row[x] = qRgba(int(r * tr * op), int(g * tg * op), int(b * tb * op), a);
            }
        }
    } else if (presetId == QLatin1String("matrix")) {
        const double scale = qMax(0.1, num(params, "scale", 1.0));
        const double speed = num(params, "speed", 1.0);
        const double op = qBound(0.0, num(params, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(params.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        const double t = timeSec * speed;
        for (int y = 0; y < H; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5) / double(H);
            for (int x = 0; x < W; ++x) {
                const double u = (double(x) + 0.5) / double(W);
                int r, g, b;
                matrixRgb(u, v, t, scale, r, g, b);
                const int a = int(255 * op);
                row[x] = qRgba(int(r * tr * op), int(g * tg * op), int(b * tb * op), a);
            }
        }
    }
    img = img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    return img;
}

void applyCpu(QImage &img, const QString &presetId, const QVariantMap &params, double timeSec,
    const QString &mode) {
    applyCpu(img, presetId, params, timeSec, mode, QRectF());
}

void applyCpu(QImage &img, const QString &presetId, const QVariantMap &params, double timeSec,
    const QString &mode, const QRectF &leafRectDevice) {
    if (img.isNull() || presetId.isEmpty())
        return;
    // Unknown (e.g. retired pixelate) presets are a no-op so old designs
    // keep their base paint on export; preview hides them the same way.
    if (!isKnownPreset(presetId))
        return;
    if (img.format() != QImage::Format_ARGB32_Premultiplied)
        img = img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    const QString m = normMode(mode, presetId);
    const QVariantMap p = normParams(presetId, params);
    const int W = img.width(), H = img.height();
    if (W <= 0 || H <= 0)
        return;
    // Leaf-relative uv to match QML (0..1 across leaf bbox). Empty rect
    // falls back to full-image uv for compatibility.
    double leafX = 0, leafY = 0, leafW = double(W), leafH = double(H);
    if (leafRectDevice.isValid() && leafRectDevice.width() > 0.5 && leafRectDevice.height() > 0.5) {
        leafX = leafRectDevice.x();
        leafY = leafRectDevice.y();
        leafW = leafRectDevice.width();
        leafH = leafRectDevice.height();
    }
    if (m == QLatin1String("fill")) {
        // Fill mode: procedural tile masked by existing alpha (so strokes
        // and silhouette confine it, matching the QML fill branch).
        // Leaf-relative uv; src tile is premultiplied (see generateFill).
        // Layers are full-frame transparent except the leaf + halo, so
        // restrict the trig loops to the tight alpha bbox (skipped for
        // fullscreen leaves where the bbox is the frame anyway).
        int bx0 = 0, by0 = 0, bx1 = W, by1 = H;
        if (!coversFrame(leafX, leafY, leafW, leafH, W, H) && !alphaBounds(img, bx0, by0, bx1, by1))
            return;
        if (presetId == QLatin1String("plasma")) {
            const double scale = qMax(0.1, num(p, "scale", 1.0));
            const double speed = num(p, "speed", 1.0);
            const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
            const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
            const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
            if (op <= 0.001) {
                // Transparent fill: clear covered pixels, skip trig.
                for (int y = by0; y < by1; ++y) {
                    QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                    for (int x = bx0; x < bx1; ++x) {
                        if (qAlpha(dst[x]) != 0)
                            dst[x] = qRgba(0, 0, 0, 0);
                    }
                }
                return;
            }
            const double t = timeSec * speed;
            const int pa = int(255 * op);
            // Row/col hoist: v1 depends only on x, v2 only on y. Precompute
            // both plus the uv arrays once per tile so the inner loop pays
            // 1 sin (v4) + mults instead of 4 sins. v3 uses
            // sin(Au+Av+t3) = (sinAu*cosAv+cosAu*sinAv)*Ct3
            //   + (cosAu*cosAv-sinAu*sinAv)*St3, exact to ~1e-15
            // (<1 LSB after the palette LUT).
            const int bw = bx1 - bx0, bh = by1 - by0;
            std::vector<double> uArr(bw), v1Arr(bw), sinAuArr(bw), cosAuArr(bw);
            const double k = 6.2831 * scale;
            const double t1 = t * 1.7, t2 = t * 1.3, t3 = t * 0.9, t4 = t * 2.1;
            const double Ct3 = qCos(t3), St3 = qSin(t3);
            for (int ix = 0; ix < bw; ++ix) {
                const double u = (double(bx0 + ix) + 0.5 - leafX) / qMax(1.0, leafW);
                uArr[ix] = u;
                v1Arr[ix] = qSin(u * k + t1);
                const double au = u * k;
                sinAuArr[ix] = qSin(au);
                cosAuArr[ix] = qCos(au);
            }
            std::vector<double> vArr(bh), v2Arr(bh), sinAvArr(bh), cosAvArr(bh);
            for (int iy = 0; iy < bh; ++iy) {
                const double v = (double(by0 + iy) + 0.5 - leafY) / qMax(1.0, leafH);
                vArr[iy] = v;
                v2Arr[iy] = qSin(v * k - t2);
                const double av = v * k;
                sinAvArr[iy] = qSin(av);
                cosAvArr[iy] = qCos(av);
            }
            const double k2 = 12.566 * scale;
            for (int iy = 0; iy < bh; ++iy) {
                const int y = by0 + iy;
                QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                const double v = vArr[iy];
                const double v2 = v2Arr[iy];
                const double sinAv = sinAvArr[iy], cosAv = cosAvArr[iy];
                for (int ix = 0; ix < bw; ++ix) {
                    const int x = bx0 + ix;
                    const int da = qAlpha(dst[x]);
                    if (da == 0)
                        continue;
                    const double u = uArr[ix];
                    const double v1 = v1Arr[ix];
                    const double sinSum = sinAuArr[ix] * cosAv + cosAuArr[ix] * sinAv;
                    const double cosSum = cosAuArr[ix] * cosAv - sinAuArr[ix] * sinAv;
                    const double v3 = sinSum * Ct3 + cosSum * St3;
                    const double v4 = qSin(qSqrt(u * u + v * v) * k2 - t4);
                    const double vv = (v1 + v2 + v3 + v4) * 0.25;
                    int pr, pg, pb;
                    plasmaLutRgb(0.5 + 0.5 * vv, pr, pg, pb);
                    const int a = (da * pa + 127) / 255;
                    // src premultiplied: pr*tint*op etc, scaled by coverage da/255.
                    dst[x] = qRgba((pr * tr * op * da + 127) / 255, (pg * tg * op * da + 127) / 255,
                        (pb * tb * op * da + 127) / 255, a);
                }
            }
            return;
        }
        if (presetId == QLatin1String("aurora")) {
            const double scale = qMax(0.1, num(p, "scale", 1.0));
            const double speed = num(p, "speed", 1.0);
            const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
            const double inten = num(p, "intensity", 1.0);
            const QColor cA = colorOf(p.value(QStringLiteral("colorA")), QColor(QStringLiteral("#00e5ff")));
            const QColor cB = colorOf(p.value(QStringLiteral("colorB")), QColor(QStringLiteral("#b537f2")));
            if (op <= 0.001) {
                for (int y = by0; y < by1; ++y) {
                    QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                    for (int x = bx0; x < bx1; ++x) {
                        if (qAlpha(dst[x]) != 0)
                            dst[x] = qRgba(0, 0, 0, 0);
                    }
                }
                return;
            }
            const double t = timeSec * speed;
            const int pa = int(255 * op);
            // Row hoist: the wobble term depends only on v. Hoisted
            // verbatim from auroraRgb (must match aurora.frag); the inner
            // loop keeps 1 sin instead of 2. Color channels and clamps are
            // loop-invariant scalars, hoisted unchanged.
            const double sA = qMax(0.1, scale);
            const double intenA = qBound(0.0, inten, 1.5);
            const double arA = cA.redF(), agA = cA.greenF(), abA = cA.blueF();
            const double brA = cB.redF(), bgA = cB.greenF(), bbA = cB.blueF();
            const int bhA = by1 - by0;
            std::vector<double> wArrA(bhA);
            for (int iy = 0; iy < bhA; ++iy) {
                const double vv = (double(by0 + iy) + 0.5 - leafY) / qMax(1.0, leafH);
                wArrA[iy] = qSin(vv * 6.2831 * sA + t * 1.2) * 0.35;
            }
            for (int y = by0; y < by1; ++y) {
                QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
                const double wRow = wArrA[y - by0];
                for (int x = bx0; x < bx1; ++x) {
                    const int da = qAlpha(dst[x]);
                    if (da == 0)
                        continue;
                    const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                    const double ph = (u * sA * 2.0 + v * sA * 1.2 + wRow) * 6.2831 + t * 0.8;
                    const double aa = 0.5 + 0.5 * qSin(ph);
                    const int pr = qBound(0, int(qBound(0.0, (arA + (brA - arA) * aa) * intenA, 1.0) * 255.0 + 0.5), 255);
                    const int pg = qBound(0, int(qBound(0.0, (agA + (bgA - agA) * aa) * intenA, 1.0) * 255.0 + 0.5), 255);
                    const int pb = qBound(0, int(qBound(0.0, (abA + (bbA - abA) * aa) * intenA, 1.0) * 255.0 + 0.5), 255);
                    const int a = (da * pa + 127) / 255;
                    dst[x] = qRgba((pr * op * da + 127) / 255, (pg * op * da + 127) / 255,
                        (pb * op * da + 127) / 255, a);
                }
            }
            return;
        }
        if (presetId == QLatin1String("clouds")) {
            const double scale = qMax(0.1, num(p, "scale", 1.0));
            const double speed = num(p, "speed", 0.6);
            const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
            const double density = num(p, "density", 0.5);
            const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
            if (op <= 0.001) {
                for (int y = by0; y < by1; ++y) {
                    QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                    for (int x = bx0; x < bx1; ++x) {
                        if (qAlpha(dst[x]) != 0)
                            dst[x] = qRgba(0, 0, 0, 0);
                    }
                }
                return;
            }
            const double t = timeSec * speed;
            const int pa = int(255 * op);
            const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
            // Row/col hoist: n1 depends only on x, n2 only on y. Hoisted
            // verbatim from cloudsCov (must match clouds.frag); the inner
            // loop keeps 2 sins instead of 4.
            const double sC = qMax(0.1, scale);
            const double kC = 6.2831 * sC;
            const double e0C = qBound(0.0, 1.0 - qBound(0.0, density, 1.0), 1.0);
            const int bwC = bx1 - bx0, bhC = by1 - by0;
            std::vector<double> uArrC(bwC), n1ArrC(bwC);
            for (int ix = 0; ix < bwC; ++ix) {
                const double u = (double(bx0 + ix) + 0.5 - leafX) / qMax(1.0, leafW);
                uArrC[ix] = u;
                n1ArrC[ix] = qSin(u * kC + t * 1.0);
            }
            std::vector<double> vArrC(bhC), n2ArrC(bhC);
            for (int iy = 0; iy < bhC; ++iy) {
                const double v = (double(by0 + iy) + 0.5 - leafY) / qMax(1.0, leafH);
                vArrC[iy] = v;
                n2ArrC[iy] = qSin(v * kC * 1.3 - t * 0.8);
            }
            for (int iy = 0; iy < bhC; ++iy) {
                const int y = by0 + iy;
                QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                const double v = vArrC[iy];
                const double n2 = n2ArrC[iy];
                const double dy = v - 0.5;
                for (int ix = 0; ix < bwC; ++ix) {
                    const int x = bx0 + ix;
                    const int da = qAlpha(dst[x]);
                    if (da == 0)
                        continue;
                    const double u = uArrC[ix];
                    const double n3 = qSin((u + v) * kC * 0.7 + t * 0.5);
                    const double dx = u - 0.5;
                    const double n4 = qSin(qSqrt(dx * dx + dy * dy) * kC * 2.0 - t * 0.9);
                    const double e = 0.5 + 0.5 * (n1ArrC[ix] + n2 + n3 + n4) * 0.25;
                    const double cov = smoothstepCpu(e0C, e0C + 0.4, e);
                    const int pr = qBound(0, int(tr * cov * 255.0 + 0.5), 255);
                    const int pg = qBound(0, int(tg * cov * 255.0 + 0.5), 255);
                    const int pb = qBound(0, int(tb * cov * 255.0 + 0.5), 255);
                    const int a = (da * pa + 127) / 255;
                    dst[x] = qRgba((pr * op * da + 127) / 255, (pg * op * da + 127) / 255,
                        (pb * op * da + 127) / 255, a);
                }
            }
            return;
        }
        if (presetId == QLatin1String("kaleidoscope")) {
            const double segs = num(p, "segments", 6.0);
            const double zoom = num(p, "zoom", 1.2);
            const double speed = num(p, "speed", 1.0);
            const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
            const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
            const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
            if (op <= 0.001) {
                for (int y = by0; y < by1; ++y) {
                    QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                    for (int x = bx0; x < bx1; ++x) {
                        if (qAlpha(dst[x]) != 0)
                            dst[x] = qRgba(0, 0, 0, 0);
                    }
                }
                return;
            }
            const double t = timeSec * speed;
            const int pa = int(255 * op);
            for (int y = by0; y < by1; ++y) {
                QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
                for (int x = bx0; x < bx1; ++x) {
                    const int da = qAlpha(dst[x]);
                    if (da == 0)
                        continue;
                    const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                    int pr, pg, pb;
                    kaleidoRgb(u, v, t, segs, zoom, pr, pg, pb);
                    const int a = (da * pa + 127) / 255;
                    dst[x] = qRgba((pr * tr * op * da + 127) / 255, (pg * tg * op * da + 127) / 255,
                        (pb * tb * op * da + 127) / 255, a);
                }
            }
            return;
        }
        if (presetId == QLatin1String("scanlines")) {
            const double freq = num(p, "frequency", 120.0);
            const double inten = num(p, "intensity", 0.5);
            const double vig = num(p, "vignette", 0.4);
            const double speed = num(p, "speed", 1.0);
            const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
            const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
            const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
            if (op <= 0.001) {
                for (int y = by0; y < by1; ++y) {
                    QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                    for (int x = bx0; x < bx1; ++x) {
                        if (qAlpha(dst[x]) != 0)
                            dst[x] = qRgba(0, 0, 0, 0);
                    }
                }
                return;
            }
            const double t = timeSec * speed;
            const int pa = int(255 * op);
            // Row hoist: the line pattern depends only on v. Hoisted
            // verbatim from scanPat (must match scanlines.frag); the inner
            // loop keeps the vignette sqrt, no sin.
            const double freqS = qBound(20.0, freq, 300.0);
            const double intenS = qBound(0.0, inten, 1.0);
            const double vigS = qBound(0.0, vig, 1.0);
            const double kS = freqS * 6.2831;
            const int bhS = by1 - by0;
            std::vector<double> linesArrS(bhS);
            for (int iy = 0; iy < bhS; ++iy) {
                const double v = (double(by0 + iy) + 0.5 - leafY) / qMax(1.0, leafH);
                const double li = 0.5 + 0.5 * qSin(v * kS + t * 2.0);
                linesArrS[iy] = 1.0 - intenS * (1.0 - li);
            }
            for (int iy = 0; iy < bhS; ++iy) {
                const int y = by0 + iy;
                QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
                const double lines = linesArrS[iy];
                const double dy = v - 0.5;
                for (int x = bx0; x < bx1; ++x) {
                    const int da = qAlpha(dst[x]);
                    if (da == 0)
                        continue;
                    const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                    const double dx = u - 0.5;
                    const double d = qSqrt(dx * dx + dy * dy);
                    const double vvig = 1.0 - vigS * smoothstepCpu(0.3, 0.75, d);
                    const double pat = qBound(0.0, lines * vvig, 1.0);
                    const int rr = qBound(0, int(pat * tr * op * 255.0 + 0.5), 255);
                    const int gg = qBound(0, int(pat * tg * op * 255.0 + 0.5), 255);
                    const int bb = qBound(0, int(pat * tb * op * 255.0 + 0.5), 255);
                    const int a = (da * pa + 127) / 255;
                    dst[x] = qRgba((rr * da + 127) / 255, (gg * da + 127) / 255, (bb * da + 127) / 255, a);
                }
            }
            return;
        }
        if (presetId == QLatin1String("fire")) {
            const double scale = qMax(0.1, num(p, "scale", 1.0));
            const double speed = num(p, "speed", 1.0);
            const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
            const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
            const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
            if (op <= 0.001) {
                for (int y = by0; y < by1; ++y) {
                    QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                    for (int x = bx0; x < bx1; ++x) {
                        if (qAlpha(dst[x]) != 0)
                            dst[x] = qRgba(0, 0, 0, 0);
                    }
                }
                return;
            }
            const double t = timeSec * speed;
            const int pa = int(255 * op);
            for (int y = by0; y < by1; ++y) {
                QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
                for (int x = bx0; x < bx1; ++x) {
                    const int da = qAlpha(dst[x]);
                    if (da == 0)
                        continue;
                    const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                    int pr, pg, pb;
                    fireRgb(u, v, t, scale, pr, pg, pb);
                    const int a = (da * pa + 127) / 255;
                    dst[x] = qRgba((pr * tr * op * da + 127) / 255, (pg * tg * op * da + 127) / 255,
                        (pb * tb * op * da + 127) / 255, a);
                }
            }
            return;
        }
        if (presetId == QLatin1String("nebula")) {
            const double scale = qMax(0.1, num(p, "scale", 1.0));
            const double speed = num(p, "speed", 1.0);
            const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
            const double inten = num(p, "intensity", 1.0);
            const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
            const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
            if (op <= 0.001) {
                for (int y = by0; y < by1; ++y) {
                    QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                    for (int x = bx0; x < bx1; ++x) {
                        if (qAlpha(dst[x]) != 0)
                            dst[x] = qRgba(0, 0, 0, 0);
                    }
                }
                return;
            }
            const double t = timeSec * speed;
            const int pa = int(255 * op);
            for (int y = by0; y < by1; ++y) {
                QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
                for (int x = bx0; x < bx1; ++x) {
                    const int da = qAlpha(dst[x]);
                    if (da == 0)
                        continue;
                    const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                    int pr, pg, pb;
                    nebulaRgb(u, v, t, scale, inten, pr, pg, pb);
                    const int a = (da * pa + 127) / 255;
                    dst[x] = qRgba((pr * tr * op * da + 127) / 255, (pg * tg * op * da + 127) / 255,
                        (pb * tb * op * da + 127) / 255, a);
                }
            }
            return;
        }
        if (presetId == QLatin1String("vortex")) {
            const double zoom = qMax(0.1, num(p, "zoom", 1.2));
            const double speed = num(p, "speed", 1.0);
            const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
            const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
            const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
            if (op <= 0.001) {
                for (int y = by0; y < by1; ++y) {
                    QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                    for (int x = bx0; x < bx1; ++x) {
                        if (qAlpha(dst[x]) != 0)
                            dst[x] = qRgba(0, 0, 0, 0);
                    }
                }
                return;
            }
            const double t = timeSec * speed;
            const int pa = int(255 * op);
            for (int y = by0; y < by1; ++y) {
                QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
                for (int x = bx0; x < bx1; ++x) {
                    const int da = qAlpha(dst[x]);
                    if (da == 0)
                        continue;
                    const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                    int pr, pg, pb;
                    vortexRgb(u, v, t, zoom, pr, pg, pb);
                    const int a = (da * pa + 127) / 255;
                    dst[x] = qRgba((pr * tr * op * da + 127) / 255, (pg * tg * op * da + 127) / 255,
                        (pb * tb * op * da + 127) / 255, a);
                }
            }
            return;
        }
        if (presetId == QLatin1String("matrix")) {
            const double scale = qMax(0.1, num(p, "scale", 1.0));
            const double speed = num(p, "speed", 1.0);
            const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
            const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
            const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
            if (op <= 0.001) {
                for (int y = by0; y < by1; ++y) {
                    QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                    for (int x = bx0; x < bx1; ++x) {
                        if (qAlpha(dst[x]) != 0)
                            dst[x] = qRgba(0, 0, 0, 0);
                    }
                }
                return;
            }
            const double t = timeSec * speed;
            const int pa = int(255 * op);
            for (int y = by0; y < by1; ++y) {
                QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
                const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
                for (int x = bx0; x < bx1; ++x) {
                    const int da = qAlpha(dst[x]);
                    if (da == 0)
                        continue;
                    const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                    int pr, pg, pb;
                    matrixRgb(u, v, t, scale, pr, pg, pb);
                    const int a = (da * pa + 127) / 255;
                    dst[x] = qRgba((pr * tr * op * da + 127) / 255, (pg * tg * op * da + 127) / 255,
                        (pb * tb * op * da + 127) / 255, a);
                }
            }
            return;
        }
        // Unknown preset fill: fall back to full-tile generateFill masked.
        QImage gen = generateFill(W, H, presetId, p, timeSec);
        for (int y = 0; y < H; ++y) {
            QRgb *dst = reinterpret_cast<QRgb *>(img.scanLine(y));
            const QRgb *src = reinterpret_cast<const QRgb *>(gen.constScanLine(y));
            for (int x = 0; x < W; ++x) {
                const int da = qAlpha(dst[x]);
                if (da == 0)
                    continue;
                // src is premultiplied: scale by coverage da/255.
                const int sr = qRed(src[x]), sg = qGreen(src[x]), sb = qBlue(src[x]);
                const int sa = qAlpha(src[x]);
                const int a = (da * sa + 127) / 255;
                dst[x] = qRgba((sr * da + 127) / 255, (sg * da + 127) / 255, (sb * da + 127) / 255, a);
            }
        }
        return;
    }
    // Overlay mode (leaf-relative to match QML).
    // Like fill, restrict to the tight alpha bbox: layers are sparse.
    if (presetId == QLatin1String("plasma")) {
        // Plasma overlay: screen-blend procedural plasma at opacity,
        // matching plasma_overlay.frag (straight screen, mix by k).
        const double scale = qMax(0.1, num(p, "scale", 1.0));
        const double speed = num(p, "speed", 1.0);
        const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        if (op <= 0.001)
            return;
        int bx0 = 0, by0 = 0, bx1 = W, by1 = H;
        if (!coversFrame(leafX, leafY, leafW, leafH, W, H) && !alphaBounds(img, bx0, by0, bx1, by1))
            return;
        const double t = timeSec * speed;
        const int bw = bx1 - bx0, bh = by1 - by0;
        std::vector<double> uArr(bw), v1Arr(bw), sinAuArr(bw), cosAuArr(bw);
        const double k = 6.2831 * scale;
        const double t1 = t * 1.7, t2 = t * 1.3, t3 = t * 0.9, t4 = t * 2.1;
        const double Ct3 = qCos(t3), St3 = qSin(t3);
        for (int ix = 0; ix < bw; ++ix) {
            const double u = (double(bx0 + ix) + 0.5 - leafX) / qMax(1.0, leafW);
            uArr[ix] = u;
            v1Arr[ix] = qSin(u * k + t1);
            const double au = u * k;
            sinAuArr[ix] = qSin(au);
            cosAuArr[ix] = qCos(au);
        }
        std::vector<double> vArr(bh), v2Arr(bh), sinAvArr(bh), cosAvArr(bh);
        for (int iy = 0; iy < bh; ++iy) {
            const double v = (double(by0 + iy) + 0.5 - leafY) / qMax(1.0, leafH);
            vArr[iy] = v;
            v2Arr[iy] = qSin(v * k - t2);
            const double av = v * k;
            sinAvArr[iy] = qSin(av);
            cosAvArr[iy] = qCos(av);
        }
        const double k2 = 12.566 * scale;
        for (int iy = 0; iy < bh; ++iy) {
            const int y = by0 + iy;
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = vArr[iy];
            const double v2 = v2Arr[iy];
            const double sinAv = sinAvArr[iy], cosAv = cosAvArr[iy];
            for (int ix = 0; ix < bw; ++ix) {
                const int x = bx0 + ix;
                const int a = qAlpha(row[x]);
                if (a == 0)
                    continue;
                const double u = uArr[ix];
                const double v1 = v1Arr[ix];
                const double sinSum = sinAuArr[ix] * cosAv + cosAuArr[ix] * sinAv;
                const double cosSum = cosAuArr[ix] * cosAv - sinAuArr[ix] * sinAv;
                const double v3 = sinSum * Ct3 + cosSum * St3;
                const double v4 = qSin(qSqrt(u * u + v * v) * k2 - t4);
                int pr, pg, pb;
                plasmaLutRgb(0.5 + 0.5 * (v1 + v2 + v3 + v4) * 0.25, pr, pg, pb);
                const double pa = a / 255.0;
                if (pa <= 0.001)
                    continue;
                const double br = (qRed(row[x]) / 255.0) / pa;
                const double bg = (qGreen(row[x]) / 255.0) / pa;
                const double bb = (qBlue(row[x]) / 255.0) / pa;
                const double prn = pr / 255.0 * tr, pgn = pg / 255.0 * tg, pbn = pb / 255.0 * tb;
                const double scrR = 1.0 - (1.0 - qBound(0.0, br, 1.0)) * (1.0 - prn);
                const double scrG = 1.0 - (1.0 - qBound(0.0, bg, 1.0)) * (1.0 - pgn);
                const double scrB = 1.0 - (1.0 - qBound(0.0, bb, 1.0)) * (1.0 - pbn);
                const double mr = br * (1 - op) + scrR * op;
                const double mg = bg * (1 - op) + scrG * op;
                const double mb = bb * (1 - op) + scrB * op;
                const int nr = qBound(0, int(mr * pa * 255.0 + 0.5), 255);
                const int ng = qBound(0, int(mg * pa * 255.0 + 0.5), 255);
                const int nb = qBound(0, int(mb * pa * 255.0 + 0.5), 255);
                row[x] = qRgba(nr, ng, nb, a);
            }
        }
        return;
    }
    if (presetId == QLatin1String("aurora")) {
        // Aurora overlay: screen-blend aurora bands at opacity,
        // matching aurora_overlay.frag (straight screen, mix by k).
        const double scale = qMax(0.1, num(p, "scale", 1.0));
        const double speed = num(p, "speed", 1.0);
        const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
        const double inten = num(p, "intensity", 1.0);
        const QColor cA = colorOf(p.value(QStringLiteral("colorA")), QColor(QStringLiteral("#00e5ff")));
        const QColor cB = colorOf(p.value(QStringLiteral("colorB")), QColor(QStringLiteral("#b537f2")));
        if (op <= 0.001)
            return;
        int bx0 = 0, by0 = 0, bx1 = W, by1 = H;
        if (!coversFrame(leafX, leafY, leafW, leafH, W, H) && !alphaBounds(img, bx0, by0, bx1, by1))
            return;
        const double t = timeSec * speed;
        // Row hoist: the wobble term depends only on v. Hoisted verbatim
        // from auroraRgb (must match aurora_overlay.frag).
        const double sA = qMax(0.1, scale);
        const double intenA = qBound(0.0, inten, 1.5);
        const double arA = cA.redF(), agA = cA.greenF(), abA = cA.blueF();
        const double brA = cB.redF(), bgA = cB.greenF(), bbA = cB.blueF();
        const int bhA = by1 - by0;
        std::vector<double> wArrA(bhA);
        for (int iy = 0; iy < bhA; ++iy) {
            const double vv = (double(by0 + iy) + 0.5 - leafY) / qMax(1.0, leafH);
            wArrA[iy] = qSin(vv * 6.2831 * sA + t * 1.2) * 0.35;
        }
        for (int y = by0; y < by1; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
            const double wRow = wArrA[y - by0];
            for (int x = bx0; x < bx1; ++x) {
                const int a = qAlpha(row[x]);
                if (a == 0)
                    continue;
                const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                const double ph = (u * sA * 2.0 + v * sA * 1.2 + wRow) * 6.2831 + t * 0.8;
                const double aa = 0.5 + 0.5 * qSin(ph);
                const int pr = qBound(0, int(qBound(0.0, (arA + (brA - arA) * aa) * intenA, 1.0) * 255.0 + 0.5), 255);
                const int pg = qBound(0, int(qBound(0.0, (agA + (bgA - agA) * aa) * intenA, 1.0) * 255.0 + 0.5), 255);
                const int pb = qBound(0, int(qBound(0.0, (abA + (bbA - abA) * aa) * intenA, 1.0) * 255.0 + 0.5), 255);
                const double pa = a / 255.0;
                if (pa <= 0.001)
                    continue;
                const double br = (qRed(row[x]) / 255.0) / pa;
                const double bg = (qGreen(row[x]) / 255.0) / pa;
                const double bb = (qBlue(row[x]) / 255.0) / pa;
                const double prn = pr / 255.0, pgn = pg / 255.0, pbn = pb / 255.0;
                const double scrR = 1.0 - (1.0 - qBound(0.0, br, 1.0)) * (1.0 - prn);
                const double scrG = 1.0 - (1.0 - qBound(0.0, bg, 1.0)) * (1.0 - pgn);
                const double scrB = 1.0 - (1.0 - qBound(0.0, bb, 1.0)) * (1.0 - pbn);
                const double mr = br * (1 - op) + scrR * op;
                const double mg = bg * (1 - op) + scrG * op;
                const double mb = bb * (1 - op) + scrB * op;
                row[x] = qRgba(qBound(0, int(mr * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mg * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mb * pa * 255.0 + 0.5), 255), a);
            }
        }
        return;
    }
    if (presetId == QLatin1String("clouds")) {
        // Clouds overlay: screen-blend tinted coverage at opacity,
        // matching clouds_overlay.frag.
        const double scale = qMax(0.1, num(p, "scale", 1.0));
        const double speed = num(p, "speed", 0.6);
        const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
        const double density = num(p, "density", 0.5);
        const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        if (op <= 0.001)
            return;
        int bx0 = 0, by0 = 0, bx1 = W, by1 = H;
        if (!coversFrame(leafX, leafY, leafW, leafH, W, H) && !alphaBounds(img, bx0, by0, bx1, by1))
            return;
        const double t = timeSec * speed;
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        // Row/col hoist: n1 depends only on x, n2 only on y. Hoisted
        // verbatim from cloudsCov (must match clouds_overlay.frag).
        const double sC = qMax(0.1, scale);
        const double kC = 6.2831 * sC;
        const double e0C = qBound(0.0, 1.0 - qBound(0.0, density, 1.0), 1.0);
        const int bwC = bx1 - bx0, bhC = by1 - by0;
        std::vector<double> uArrC(bwC), n1ArrC(bwC);
        for (int ix = 0; ix < bwC; ++ix) {
            const double u = (double(bx0 + ix) + 0.5 - leafX) / qMax(1.0, leafW);
            uArrC[ix] = u;
            n1ArrC[ix] = qSin(u * kC + t * 1.0);
        }
        std::vector<double> vArrC(bhC), n2ArrC(bhC);
        for (int iy = 0; iy < bhC; ++iy) {
            const double v = (double(by0 + iy) + 0.5 - leafY) / qMax(1.0, leafH);
            vArrC[iy] = v;
            n2ArrC[iy] = qSin(v * kC * 1.3 - t * 0.8);
        }
        for (int iy = 0; iy < bhC; ++iy) {
            const int y = by0 + iy;
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = vArrC[iy];
            const double n2 = n2ArrC[iy];
            const double dy = v - 0.5;
            for (int ix = 0; ix < bwC; ++ix) {
                const int x = bx0 + ix;
                const int a = qAlpha(row[x]);
                if (a == 0)
                    continue;
                const double u = uArrC[ix];
                const double n3 = qSin((u + v) * kC * 0.7 + t * 0.5);
                const double dx = u - 0.5;
                const double n4 = qSin(qSqrt(dx * dx + dy * dy) * kC * 2.0 - t * 0.9);
                const double e = 0.5 + 0.5 * (n1ArrC[ix] + n2 + n3 + n4) * 0.25;
                const double cov = smoothstepCpu(e0C, e0C + 0.4, e);
                const double pa = a / 255.0;
                if (pa <= 0.001)
                    continue;
                const double br = (qRed(row[x]) / 255.0) / pa;
                const double bg = (qGreen(row[x]) / 255.0) / pa;
                const double bb = (qBlue(row[x]) / 255.0) / pa;
                const double prn = qBound(0.0, tr * cov, 1.0);
                const double pgn = qBound(0.0, tg * cov, 1.0);
                const double pbn = qBound(0.0, tb * cov, 1.0);
                const double scrR = 1.0 - (1.0 - qBound(0.0, br, 1.0)) * (1.0 - prn);
                const double scrG = 1.0 - (1.0 - qBound(0.0, bg, 1.0)) * (1.0 - pgn);
                const double scrB = 1.0 - (1.0 - qBound(0.0, bb, 1.0)) * (1.0 - pbn);
                const double mr = br * (1 - op) + scrR * op;
                const double mg = bg * (1 - op) + scrG * op;
                const double mb = bb * (1 - op) + scrB * op;
                row[x] = qRgba(qBound(0, int(mr * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mg * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mb * pa * 255.0 + 0.5), 255), a);
            }
        }
        return;
    }
    if (presetId == QLatin1String("kaleidoscope")) {
        // Kaleidoscope overlay: screen-blend facets at opacity,
        // matching kaleidoscope_overlay.frag.
        const double segs = num(p, "segments", 6.0);
        const double zoom = num(p, "zoom", 1.2);
        const double speed = num(p, "speed", 1.0);
        const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        if (op <= 0.001)
            return;
        int bx0 = 0, by0 = 0, bx1 = W, by1 = H;
        if (!coversFrame(leafX, leafY, leafW, leafH, W, H) && !alphaBounds(img, bx0, by0, bx1, by1))
            return;
        const double t = timeSec * speed;
        for (int y = by0; y < by1; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
            for (int x = bx0; x < bx1; ++x) {
                const int a = qAlpha(row[x]);
                if (a == 0)
                    continue;
                const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                int pr, pg, pb;
                kaleidoRgb(u, v, t, segs, zoom, pr, pg, pb);
                const double pa = a / 255.0;
                if (pa <= 0.001)
                    continue;
                const double br = (qRed(row[x]) / 255.0) / pa;
                const double bg = (qGreen(row[x]) / 255.0) / pa;
                const double bb = (qBlue(row[x]) / 255.0) / pa;
                const double prn = pr / 255.0 * tr, pgn = pg / 255.0 * tg, pbn = pb / 255.0 * tb;
                const double scrR = 1.0 - (1.0 - qBound(0.0, br, 1.0)) * (1.0 - prn);
                const double scrG = 1.0 - (1.0 - qBound(0.0, bg, 1.0)) * (1.0 - pgn);
                const double scrB = 1.0 - (1.0 - qBound(0.0, bb, 1.0)) * (1.0 - pbn);
                const double mr = br * (1 - op) + scrR * op;
                const double mg = bg * (1 - op) + scrG * op;
                const double mb = bb * (1 - op) + scrB * op;
                row[x] = qRgba(qBound(0, int(mr * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mg * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mb * pa * 255.0 + 0.5), 255), a);
            }
        }
        return;
    }
    if (presetId == QLatin1String("scanlines")) {
        // Scanlines overlay: multiply base by the tinted line/vignette
        // pattern, matching scanlines_overlay.frag.
        const double freq = num(p, "frequency", 120.0);
        const double inten = num(p, "intensity", 0.5);
        const double vig = num(p, "vignette", 0.4);
        const double speed = num(p, "speed", 1.0);
        const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        if (op <= 0.001)
            return;
        int bx0 = 0, by0 = 0, bx1 = W, by1 = H;
        if (!coversFrame(leafX, leafY, leafW, leafH, W, H) && !alphaBounds(img, bx0, by0, bx1, by1))
            return;
        const double t = timeSec * speed;
        // Row hoist: the line pattern depends only on v. Hoisted verbatim
        // from scanPat (must match scanlines_overlay.frag).
        const double freqS = qBound(20.0, freq, 300.0);
        const double intenS = qBound(0.0, inten, 1.0);
        const double vigS = qBound(0.0, vig, 1.0);
        const double kS = freqS * 6.2831;
        const int bhS = by1 - by0;
        std::vector<double> linesArrS(bhS);
        for (int iy = 0; iy < bhS; ++iy) {
            const double v = (double(by0 + iy) + 0.5 - leafY) / qMax(1.0, leafH);
            const double li = 0.5 + 0.5 * qSin(v * kS + t * 2.0);
            linesArrS[iy] = 1.0 - intenS * (1.0 - li);
        }
        for (int iy = 0; iy < bhS; ++iy) {
            const int y = by0 + iy;
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
            const double lines = linesArrS[iy];
            const double dy = v - 0.5;
            for (int x = bx0; x < bx1; ++x) {
                const int a = qAlpha(row[x]);
                if (a == 0)
                    continue;
                const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                const double dx = u - 0.5;
                const double d = qSqrt(dx * dx + dy * dy);
                const double vvig = 1.0 - vigS * smoothstepCpu(0.3, 0.75, d);
                const double pat = qBound(0.0, lines * vvig, 1.0);
                const double txr = tr * pat, txg = tg * pat, txb = tb * pat;
                const double pa = a / 255.0;
                if (pa <= 0.001)
                    continue;
                const double br = (qRed(row[x]) / 255.0) / pa;
                const double bg = (qGreen(row[x]) / 255.0) / pa;
                const double bb = (qBlue(row[x]) / 255.0) / pa;
                const double mr = br * (1 - op) + br * txr * op;
                const double mg = bg * (1 - op) + bg * txg * op;
                const double mb = bb * (1 - op) + bb * txb * op;
                row[x] = qRgba(qBound(0, int(mr * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mg * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mb * pa * 255.0 + 0.5), 255), a);
            }
        }
        return;
    }
    if (presetId == QLatin1String("fire")) {
        // Fire overlay: screen-blend flames at opacity,
        // matching fire_overlay.frag (straight screen, mix by k).
        const double scale = qMax(0.1, num(p, "scale", 1.0));
        const double speed = num(p, "speed", 1.0);
        const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        if (op <= 0.001)
            return;
        int bx0 = 0, by0 = 0, bx1 = W, by1 = H;
        if (!coversFrame(leafX, leafY, leafW, leafH, W, H) && !alphaBounds(img, bx0, by0, bx1, by1))
            return;
        const double t = timeSec * speed;
        for (int y = by0; y < by1; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
            for (int x = bx0; x < bx1; ++x) {
                const int a = qAlpha(row[x]);
                if (a == 0)
                    continue;
                const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                int pr, pg, pb;
                fireRgb(u, v, t, scale, pr, pg, pb);
                const double pa = a / 255.0;
                if (pa <= 0.001)
                    continue;
                const double br = (qRed(row[x]) / 255.0) / pa;
                const double bg = (qGreen(row[x]) / 255.0) / pa;
                const double bb = (qBlue(row[x]) / 255.0) / pa;
                const double prn = pr / 255.0 * tr, pgn = pg / 255.0 * tg, pbn = pb / 255.0 * tb;
                const double scrR = 1.0 - (1.0 - qBound(0.0, br, 1.0)) * (1.0 - prn);
                const double scrG = 1.0 - (1.0 - qBound(0.0, bg, 1.0)) * (1.0 - pgn);
                const double scrB = 1.0 - (1.0 - qBound(0.0, bb, 1.0)) * (1.0 - pbn);
                const double mr = br * (1 - op) + scrR * op;
                const double mg = bg * (1 - op) + scrG * op;
                const double mb = bb * (1 - op) + scrB * op;
                row[x] = qRgba(qBound(0, int(mr * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mg * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mb * pa * 255.0 + 0.5), 255), a);
            }
        }
        return;
    }
    if (presetId == QLatin1String("nebula")) {
        // Nebula overlay: screen-blend gas + stars at opacity,
        // matching nebula_overlay.frag (straight screen, mix by k).
        const double scale = qMax(0.1, num(p, "scale", 1.0));
        const double speed = num(p, "speed", 1.0);
        const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
        const double inten = num(p, "intensity", 1.0);
        const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        if (op <= 0.001)
            return;
        int bx0 = 0, by0 = 0, bx1 = W, by1 = H;
        if (!coversFrame(leafX, leafY, leafW, leafH, W, H) && !alphaBounds(img, bx0, by0, bx1, by1))
            return;
        const double t = timeSec * speed;
        for (int y = by0; y < by1; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
            for (int x = bx0; x < bx1; ++x) {
                const int a = qAlpha(row[x]);
                if (a == 0)
                    continue;
                const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                int pr, pg, pb;
                nebulaRgb(u, v, t, scale, inten, pr, pg, pb);
                const double pa = a / 255.0;
                if (pa <= 0.001)
                    continue;
                const double br = (qRed(row[x]) / 255.0) / pa;
                const double bg = (qGreen(row[x]) / 255.0) / pa;
                const double bb = (qBlue(row[x]) / 255.0) / pa;
                const double prn = pr / 255.0 * tr, pgn = pg / 255.0 * tg, pbn = pb / 255.0 * tb;
                const double scrR = 1.0 - (1.0 - qBound(0.0, br, 1.0)) * (1.0 - prn);
                const double scrG = 1.0 - (1.0 - qBound(0.0, bg, 1.0)) * (1.0 - pgn);
                const double scrB = 1.0 - (1.0 - qBound(0.0, bb, 1.0)) * (1.0 - pbn);
                const double mr = br * (1 - op) + scrR * op;
                const double mg = bg * (1 - op) + scrG * op;
                const double mb = bb * (1 - op) + scrB * op;
                row[x] = qRgba(qBound(0, int(mr * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mg * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mb * pa * 255.0 + 0.5), 255), a);
            }
        }
        return;
    }
    if (presetId == QLatin1String("vortex")) {
        // Vortex overlay: screen-blend swirl at opacity,
        // matching vortex_overlay.frag (straight screen, mix by k).
        const double zoom = qMax(0.1, num(p, "zoom", 1.2));
        const double speed = num(p, "speed", 1.0);
        const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        if (op <= 0.001)
            return;
        int bx0 = 0, by0 = 0, bx1 = W, by1 = H;
        if (!coversFrame(leafX, leafY, leafW, leafH, W, H) && !alphaBounds(img, bx0, by0, bx1, by1))
            return;
        const double t = timeSec * speed;
        for (int y = by0; y < by1; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
            for (int x = bx0; x < bx1; ++x) {
                const int a = qAlpha(row[x]);
                if (a == 0)
                    continue;
                const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                int pr, pg, pb;
                vortexRgb(u, v, t, zoom, pr, pg, pb);
                const double pa = a / 255.0;
                if (pa <= 0.001)
                    continue;
                const double br = (qRed(row[x]) / 255.0) / pa;
                const double bg = (qGreen(row[x]) / 255.0) / pa;
                const double bb = (qBlue(row[x]) / 255.0) / pa;
                const double prn = pr / 255.0 * tr, pgn = pg / 255.0 * tg, pbn = pb / 255.0 * tb;
                const double scrR = 1.0 - (1.0 - qBound(0.0, br, 1.0)) * (1.0 - prn);
                const double scrG = 1.0 - (1.0 - qBound(0.0, bg, 1.0)) * (1.0 - pgn);
                const double scrB = 1.0 - (1.0 - qBound(0.0, bb, 1.0)) * (1.0 - pbn);
                const double mr = br * (1 - op) + scrR * op;
                const double mg = bg * (1 - op) + scrG * op;
                const double mb = bb * (1 - op) + scrB * op;
                row[x] = qRgba(qBound(0, int(mr * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mg * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mb * pa * 255.0 + 0.5), 255), a);
            }
        }
        return;
    }
    if (presetId == QLatin1String("matrix")) {
        // Matrix overlay: screen-blend code rain at opacity,
        // matching matrix_overlay.frag (straight screen, mix by k).
        const double scale = qMax(0.1, num(p, "scale", 1.0));
        const double speed = num(p, "speed", 1.0);
        const double op = qBound(0.0, num(p, "opacity", 1.0), 1.0);
        const QColor tint = colorOf(p.value(QStringLiteral("tint")), QColor(QStringLiteral("#ffffff")));
        const double tr = tint.redF(), tg = tint.greenF(), tb = tint.blueF();
        if (op <= 0.001)
            return;
        int bx0 = 0, by0 = 0, bx1 = W, by1 = H;
        if (!coversFrame(leafX, leafY, leafW, leafH, W, H) && !alphaBounds(img, bx0, by0, bx1, by1))
            return;
        const double t = timeSec * speed;
        for (int y = by0; y < by1; ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(img.scanLine(y));
            const double v = (double(y) + 0.5 - leafY) / qMax(1.0, leafH);
            for (int x = bx0; x < bx1; ++x) {
                const int a = qAlpha(row[x]);
                if (a == 0)
                    continue;
                const double u = (double(x) + 0.5 - leafX) / qMax(1.0, leafW);
                int pr, pg, pb;
                matrixRgb(u, v, t, scale, pr, pg, pb);
                const double pa = a / 255.0;
                if (pa <= 0.001)
                    continue;
                const double br = (qRed(row[x]) / 255.0) / pa;
                const double bg = (qGreen(row[x]) / 255.0) / pa;
                const double bb = (qBlue(row[x]) / 255.0) / pa;
                const double prn = pr / 255.0 * tr, pgn = pg / 255.0 * tg, pbn = pb / 255.0 * tb;
                const double scrR = 1.0 - (1.0 - qBound(0.0, br, 1.0)) * (1.0 - prn);
                const double scrG = 1.0 - (1.0 - qBound(0.0, bg, 1.0)) * (1.0 - pgn);
                const double scrB = 1.0 - (1.0 - qBound(0.0, bb, 1.0)) * (1.0 - pbn);
                const double mr = br * (1 - op) + scrR * op;
                const double mg = bg * (1 - op) + scrG * op;
                const double mb = bb * (1 - op) + scrB * op;
                row[x] = qRgba(qBound(0, int(mr * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mg * pa * 255.0 + 0.5), 255),
                    qBound(0, int(mb * pa * 255.0 + 0.5), 255), a);
            }
        }
        return;
    }
}

} // namespace Shaders

ShaderEngine::ShaderEngine(QObject *parent)
    : QObject(parent) {
}

ShaderEngine *ShaderEngine::create(QQmlEngine *engine, QJSEngine *scriptEngine) {
    Q_UNUSED(scriptEngine);
    auto *o = new ShaderEngine(engine);
    QJSEngine::setObjectOwnership(o, QJSEngine::CppOwnership);
    return o;
}

QStringList ShaderEngine::presetIds() const {
    return Shaders::presetIds();
}
QString ShaderEngine::presetName(const QString &id) const {
    return Shaders::presetName(id);
}
QString ShaderEngine::presetDescription(const QString &id) const {
    return Shaders::presetDescription(id);
}
QString ShaderEngine::presetMode(const QString &id) const {
    return Shaders::presetMode(id);
}
QVariantMap ShaderEngine::presetDefaults(const QString &id) const {
    return Shaders::presetDefaults(id);
}
QVariantList ShaderEngine::presetSchema(const QString &id) const {
    return Shaders::presetSchema(id);
}
QString ShaderEngine::presetVertex(const QString &id) const {
    return Shaders::presetVertex(id);
}
QString ShaderEngine::presetFragment(const QString &id) const {
    return Shaders::presetFragment(id);
}
bool ShaderEngine::isShaderableType(const QString &type) const {
    return Shaders::isShaderableType(type);
}
QString ShaderEngine::normMode(const QString &mode, const QString &presetId) const {
    return Shaders::normMode(mode, presetId);
}
QVariantMap ShaderEngine::normParams(const QString &presetId, const QVariantMap &params) const {
    return Shaders::normParams(presetId, params);
}
QString ShaderEngine::validateError(const QString &vertex, const QString &fragment) const {
    QString e;
    Shaders::validateShaders(vertex, fragment, &e);
    return e;
}
QVariantList ShaderEngine::parseUniforms(const QString &fragment) const {
    return Shaders::parseUniforms(fragment);
}
QVariantMap ShaderEngine::customDefaults() const {
    return Shaders::customDefaults();
}
QVariantList ShaderEngine::customSchema() const {
    return Shaders::customSchema();
}
QString ShaderEngine::customTemplateVertex() const {
    return Shaders::customTemplateVertex();
}
QString ShaderEngine::customTemplateFragment() const {
    return Shaders::customTemplateFragment();
}
QString ShaderEngine::customContractError(const QString &vertex, const QString &fragment) const {
    return Shaders::customContractError(vertex, fragment);
}
QStringList ShaderEngine::shaderFileSuffixes() const {
    return Shaders::shaderFileSuffixes();
}
QVariantMap ShaderEngine::readShaderFile(const QUrl &url) const {
    return Shaders::readShaderFile(url);
}
QVariantMap ShaderEngine::compileCustom(const QString &vertex, const QString &fragment) const {
    return Shaders::compileCustom(vertex, fragment);
}
