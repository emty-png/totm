#pragma once

#include <QImage>
#include <QObject>
#include <QQmlEngine>
#include <QRectF>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// ShaderEngine: procedural shader presets shared by preview (QML
// ShaderEffect .qsb) and export (CPU QImage) so both match by
// construction, like Effects::grainHash.
//
// Presets: plasma, aurora, clouds, kaleidoscope, scanlines, fire,
// nebula, vortex, matrix (animated procedural
// fill/overlay). Each preset declares a fixed
// uniform contract: uv 0..1 across the leaf bbox, time seconds from
// the 60Hz frame clock, plus per-preset uniforms in shaderParams.
// Custom shaders are stored as LibraryStore shader assets with
// vertex+fragment source + uniform defaults; v1 executes presets on
// the CPU for export and via .qsb ShaderEffect for preview using the
// same formulas. Custom GLSL previews via ShaderEffect and exports
// via the preset fallback matching its base presetId (exact for
// presets, best-effort raster for fully custom — SVG skips shaders).
// Retired preset ids (e.g. pixelate) resolve as no-ops so old designs
// keep their base paint in both preview and export.
namespace Shaders {

// Supported preset ids.
QStringList presetIds();
// Display name / description for the gallery.
QString presetName(const QString &id);
QString presetDescription(const QString &id);
// Suggested apply mode: "fill" (procedural) or "overlay" (post).
QString presetMode(const QString &id);
// Default uniform values for one preset (plain map, QML-editable).
// The "custom" id resolves to customDefaults() (tint/opacity/speed).
QVariantMap presetDefaults(const QString &id);
// Uniform schema for the settings panel:
// [{name, type ("float"|"color"), min, max, def}].
// The "custom" id resolves to customSchema().
QVariantList presetSchema(const QString &id);
// Reference GLSL sources shown in the custom editor tabs (the .qsb
// files compiled from qml/components/editor/shaders/<id>.frag).
// The "custom" id returns "" (from-scratch starts truly blank).
QString presetVertex(const QString &id);
QString presetFragment(const QString &id);
// Defaults/schema for fully custom ("custom" id) shaders: the only
// uniforms the live custom pipeline binds (uTint/uOpacity/uTime).
QVariantMap customDefaults();
QVariantList customSchema();
// Minimal working custom shader pair satisfying the live contract
// below. The scratch editor starts blank; "Insert contract" pastes
// these so one click yields a renderable skeleton.
QString customTemplateVertex();
QString customTemplateFragment();
// Live custom-shader contract (v1): ShaderOverlay binds exactly
// uTime (= timeSec * speed), uOpacity, uTint plus sampler2D source
// and the Qt block (qt_Matrix/qt_Opacity) with vTexCoord varying.
// Returns "" when satisfied, else the first missing piece for the UI.
QString customContractError(const QString &vertex, const QString &fragment);
// Importable plain-GLSL suffixes for the file picker.
QStringList shaderFileSuffixes();
// Read a plain-GLSL file for import: {ok, text, error, fileName,
// size}. Local files only, UTF-8 text, capped like validateShaders.
QVariantMap readShaderFile(const QUrl &url);
// Compile a custom pair to .qsb in-process via QShaderBaker (same --qt6
// target set as the qsb tool, so packaged builds work with no external
// tool): {ok, vertUrl, fragUrl, error, log}. Results cache by source
// hash in memory plus under CacheLocation/totm/custom_shaders, so
// repeated nodes and re-opens reuse the files without re-baking.
// ok=false when validation/contract fails or baking fails; the caller
// keeps the base paint in that case.
QVariantMap compileCustom(const QString &vertex, const QString &fragment);

// True for rectangle/ellipse/triangle/star/pen leaves and boolean
// group maps that may carry a shader.
bool isShaderableType(const QString &type);
// Normalize a stored mode ("fill"|"overlay", fallback to preset).
QString normMode(const QString &mode, const QString &presetId);
// Normalize uniform params against the preset defaults (numbers
// clamped, colors stringified, unknown keys dropped).
QVariantMap normParams(const QString &presetId, const QVariantMap &params);

// Validate custom vertex+fragment source. Returns true when both
// contain "void main". *error carries the first problem for the UI.
bool validateShaders(const QString &vertex, const QString &fragment, QString *error = nullptr);
// Declared `uniform float/color <name>;` lines in fragment source.
QVariantList parseUniforms(const QString &fragment);

// CPU raster shared by export and thumbnails. img is ARGB32_Premultiplied
// leaf tile (already painted); timeSec drives animation. mode selects
// fill (procedural replaces transparent pixels inside the tile) vs
// overlay (post-process existing pixels). No-op for unknown presets.
// leafRectDevice is the leaf bbox in device px (same coords as img
// pixels); uv is 0..1 across it to match the QML overlay. Empty rect
// falls back to full-image uv for compatibility.
void applyCpu(QImage &img, const QString &presetId, const QVariantMap &params, double timeSec,
    const QString &mode);
void applyCpu(QImage &img, const QString &presetId, const QVariantMap &params, double timeSec,
    const QString &mode, const QRectF &leafRectDevice);
// Procedural fill tile (w*h, transparent outside caller clip).
QImage generateFill(int w, int h, const QString &presetId, const QVariantMap &params, double timeSec);

} // namespace Shaders

// QML bridge: stateless invokables over the preset registry + validation.
class ShaderEngine : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit ShaderEngine(QObject *parent = nullptr);

    static ShaderEngine *create(QQmlEngine *engine, QJSEngine *scriptEngine);

    Q_INVOKABLE QStringList presetIds() const;
    Q_INVOKABLE QString presetName(const QString &id) const;
    Q_INVOKABLE QString presetDescription(const QString &id) const;
    Q_INVOKABLE QString presetMode(const QString &id) const;
    Q_INVOKABLE QVariantMap presetDefaults(const QString &id) const;
    Q_INVOKABLE QVariantList presetSchema(const QString &id) const;
    Q_INVOKABLE QString presetVertex(const QString &id) const;
    Q_INVOKABLE QString presetFragment(const QString &id) const;
    Q_INVOKABLE QVariantMap customDefaults() const;
    Q_INVOKABLE QVariantList customSchema() const;
    Q_INVOKABLE QString customTemplateVertex() const;
    Q_INVOKABLE QString customTemplateFragment() const;
    Q_INVOKABLE QString customContractError(const QString &vertex, const QString &fragment) const;
    Q_INVOKABLE QStringList shaderFileSuffixes() const;
    Q_INVOKABLE QVariantMap readShaderFile(const QUrl &url) const;
    Q_INVOKABLE QVariantMap compileCustom(const QString &vertex, const QString &fragment) const;
    Q_INVOKABLE bool isShaderableType(const QString &type) const;
    Q_INVOKABLE QString normMode(const QString &mode, const QString &presetId) const;
    Q_INVOKABLE QVariantMap normParams(const QString &presetId, const QVariantMap &params) const;
    // Returns "" when valid, else the first problem (hybrid editor gate).
    Q_INVOKABLE QString validateError(const QString &vertex, const QString &fragment) const;
    Q_INVOKABLE QVariantList parseUniforms(const QString &fragment) const;
};
