#pragma once

#include <QObject>
#include <QMap>
#include <QQmlEngine>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// SettingsStore: app preferences, separate from the design library.
//
// Ownership: all QSettings access lives here. QML binds to the properties
// below and never touches QSettings directly.
// Storage: native platform storage (org "tot", app "totm").
// Theme contract: effective theme is derived as
//   followSystem ? systemDark : stored dark.
// QML binds to isDark, so OS changes propagate while following and stop
// once the user makes an explicit choice.
// Window contract: stores the last normal (unmaximized) geometry plus a
// maximized flag. Geometry is validated against current screens on read
// and write, so a disconnected monitor never restores off-screen.
// Threading: main thread only.
class SettingsStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool isDark READ isDark WRITE setIsDark NOTIFY isDarkChanged)
    Q_PROPERTY(bool followSystem READ followSystem WRITE setFollowSystem NOTIFY followSystemChanged)
    Q_PROPERTY(bool systemDark READ systemDark NOTIFY systemDarkChanged)
    // Last normal window geometry. QML restores on launch and saves
    // debounced; Wayland may ignore x/y on restore.
    Q_PROPERTY(int windowX READ windowX NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowY READ windowY NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowWidth READ windowWidth NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowHeight READ windowHeight NOTIFY windowGeometryChanged)
    Q_PROPERTY(bool windowMaximized READ windowMaximized NOTIFY windowGeometryChanged)
    Q_PROPERTY(bool hasWindowGeometry READ hasWindowGeometry NOTIFY windowGeometryChanged)
    // Shortcut overrides keyed by action id (e.g. "homeNew" -> "Ctrl+N").
    // Only non-default values are stored; missing keys mean "use default".
    // Reassigned wholesale so QML bindings update.
    Q_PROPERTY(QVariantMap shortcutOverrides READ shortcutOverrides NOTIFY shortcutsChanged)
    // Appearance: theme colors per light/dark (only non-defaults stored),
    // corner-radius preset + custom per-size values, UI font family.
    // Reassigned wholesale so QML bindings update.
    Q_PROPERTY(QVariantMap lightColors READ lightColors NOTIFY appearanceChanged)
    Q_PROPERTY(QVariantMap darkColors READ darkColors NOTIFY appearanceChanged)
    Q_PROPERTY(QString radiusPreset READ radiusPreset WRITE setRadiusPreset NOTIFY appearanceChanged)
    Q_PROPERTY(int customRadiusSmall READ customRadiusSmall WRITE setCustomRadiusSmall NOTIFY appearanceChanged)
    Q_PROPERTY(int customRadiusMedium READ customRadiusMedium WRITE setCustomRadiusMedium NOTIFY appearanceChanged)
    Q_PROPERTY(int customRadiusLarge READ customRadiusLarge WRITE setCustomRadiusLarge NOTIFY appearanceChanged)
    Q_PROPERTY(int customRadiusXLarge READ customRadiusXLarge WRITE setCustomRadiusXLarge NOTIFY appearanceChanged)
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY appearanceChanged)
    Q_PROPERTY(QStringList importedFonts READ importedFonts NOTIFY appearanceChanged)
    // File name -> detected family for imported fonts. Reassigned
    // wholesale so QML bindings update.
    Q_PROPERTY(QVariantMap importedFontFamilyMap READ importedFontFamilyMap NOTIFY appearanceChanged)
    // True when the stored family is not available (e.g. its file was
    // deleted): the app falls back to the system font and the UI shows
    // a "Font not found" error until another font is picked or reset.
    Q_PROPERTY(bool fontMissing READ fontMissing NOTIFY appearanceChanged)
    // Canvas zoom pill visibility (out, percent, in, fit). On by
    // default; toggled from the Appearance tab.
    Q_PROPERTY(bool showZoomPill READ showZoomPill WRITE setShowZoomPill NOTIFY appearanceChanged)
    // Native-feeling window buttons (traffic lights on mac, min/max +
    // close elsewhere). Tiling-WM users can hide them so the app
    // matches their environment. On by default; Appearance tab.
    Q_PROPERTY(bool showWindowControls READ showWindowControls WRITE setShowWindowControls NOTIFY appearanceChanged)
    // General: defaults for new designs (canvas size, background, timeline
    // length) plus the video-export picker defaults. Only non-default
    // values are stored; the export popup loads these on open and writes
    // back the used choice on Render. Reassigned wholesale via the
    // generalChanged signal so QML bindings update.
    Q_PROPERTY(int defaultSceneWidth READ defaultSceneWidth WRITE setDefaultSceneWidth NOTIFY generalChanged)
    Q_PROPERTY(int defaultSceneHeight READ defaultSceneHeight WRITE setDefaultSceneHeight NOTIFY generalChanged)
    Q_PROPERTY(QString defaultSceneColor READ defaultSceneColor WRITE setDefaultSceneColor NOTIFY generalChanged)
    Q_PROPERTY(double defaultDuration READ defaultDuration WRITE setDefaultDuration NOTIFY generalChanged)
    Q_PROPERTY(QString defaultQuality READ defaultQuality WRITE setDefaultQuality NOTIFY generalChanged)
    Q_PROPERTY(int defaultFps READ defaultFps WRITE setDefaultFps NOTIFY generalChanged)
    Q_PROPERTY(QString defaultPerformance READ defaultPerformance WRITE setDefaultPerformance NOTIFY generalChanged)
    Q_PROPERTY(QString defaultFormat READ defaultFormat WRITE setDefaultFormat NOTIFY generalChanged)

public:
    static SettingsStore *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit SettingsStore(QObject *parent = nullptr);

    bool isDark() const;
    // Pins an explicit choice: sets followSystem to false.
    void setIsDark(bool dark);
    Q_INVOKABLE void toggle();

    bool followSystem() const;
    void setFollowSystem(bool follow);
    Q_INVOKABLE void useSystemTheme();

    bool systemDark() const;

    int windowX() const;
    int windowY() const;
    int windowWidth() const;
    int windowHeight() const;
    bool windowMaximized() const;
    bool hasWindowGeometry() const;
    // One-shot restore snapshot: {x, y, width, height, maximized,
    // hasGeometry}. Out-of-range values fall back to a centered 900x640.
    Q_INVOKABLE QVariantMap windowGeometry() const;
    // Saves the normal geometry. When maximized, only the flag is stored
    // so restore never inherits the maximized frame.
    Q_INVOKABLE void saveWindowGeometry(int x, int y, int width, int height, bool maximized);

    // Shortcut overrides (persisted under QSettings group "shortcuts/").
    // fallback is returned when no override exists. setShortcut stores the
    // canonical PortableText form; empty resets to default, invalid
    // sequences are ignored. Only known ids are accepted.
    Q_INVOKABLE QString shortcut(const QString &id, const QString &fallback) const;
    Q_INVOKABLE void setShortcut(const QString &id, const QString &sequence);
    Q_INVOKABLE void resetShortcut(const QString &id);
    Q_INVOKABLE void resetAllShortcuts();
    QVariantMap shortcutOverrides() const;

    // Appearance colors: effective value for key in the given theme.
    // fallback is returned when no override exists. setAppearanceColor
    // stores the canonical #rrggbb (or #aarrggbb when translucent) form;
    // empty resets to default, invalid values are ignored. Only known
    // AppTheme keys are accepted.
    Q_INVOKABLE QString appearanceColor(const QString &key, bool dark, const QString &fallback) const;
    Q_INVOKABLE void setAppearanceColor(const QString &key, bool dark, const QString &color);
    Q_INVOKABLE void resetAppearanceColor(const QString &key, bool dark);
    Q_INVOKABLE void resetAllAppearanceColors(bool dark);
    QVariantMap lightColors() const;
    QVariantMap darkColors() const;

    // Corner radius: preset is one of "sharp", "rounded", "pill",
    // "custom". Unknown values fall back to "rounded". Custom per-size
    // values (0..28px) apply only when preset is "custom"; presets map
    // to fixed values in AppTheme (sharp 0, rounded 6/8/10/12,
    // pill 14/18/22/28).
    QString radiusPreset() const;
    void setRadiusPreset(const QString &preset);
    int customRadiusSmall() const;
    void setCustomRadiusSmall(int v);
    int customRadiusMedium() const;
    void setCustomRadiusMedium(int v);
    int customRadiusLarge() const;
    void setCustomRadiusLarge(int v);
    int customRadiusXLarge() const;
    void setCustomRadiusXLarge(int v);

    // UI font: empty means system default. Imported .ttf/.otf files live
    // under <AppData>/totm/fonts/ and are loaded via QFontDatabase at
    // startup; importFont copies + registers, removeImportedFont deletes.
    QString fontFamily() const;
    void setFontFamily(const QString &family);
    QStringList importedFonts() const;
    QVariantMap importedFontFamilyMap() const;
    bool fontMissing() const;
    bool showZoomPill() const;
    void setShowZoomPill(bool show);
    bool showWindowControls() const;
    void setShowWindowControls(bool show);
    Q_INVOKABLE QStringList importedFontFamilies() const;
    Q_INVOKABLE QString importFont(const QUrl &fileUrl);
    Q_INVOKABLE void removeImportedFont(const QString &fileName);
    Q_INVOKABLE void selectImportedFont(const QString &fileName);
    Q_INVOKABLE QString fontsDir() const;

    // Opens CREDITS.html in the default browser. Candidates mirror
    // PluginStore.openGuide: installed doc dir beside the binary first,
    // then the file in a dev checkout (build/<preset>/src -> src/docs).
    Q_INVOKABLE bool openCredits();

    // Clears all appearance overrides (colors, radius, font) to defaults.
    Q_INVOKABLE void resetAppearance();

    // General defaults (persisted under QSettings group "general/").
    // Scene sizes clamp to 16..7680px, duration to 0.5..60s; unknown
    // quality/performance/format fall back to "hd"/"normal"/"mp4", fps to
    // 30; invalid colors are ignored. Setters are Q_INVOKABLE so QML can
    // call them directly as well as assign the properties.
    Q_INVOKABLE int defaultSceneWidth() const;
    Q_INVOKABLE void setDefaultSceneWidth(int v);
    Q_INVOKABLE int defaultSceneHeight() const;
    Q_INVOKABLE void setDefaultSceneHeight(int v);
    Q_INVOKABLE QString defaultSceneColor() const;
    Q_INVOKABLE void setDefaultSceneColor(const QString &color);
    Q_INVOKABLE double defaultDuration() const;
    Q_INVOKABLE void setDefaultDuration(double v);
    Q_INVOKABLE QString defaultQuality() const;
    Q_INVOKABLE void setDefaultQuality(const QString &quality);
    Q_INVOKABLE int defaultFps() const;
    Q_INVOKABLE void setDefaultFps(int v);
    Q_INVOKABLE QString defaultPerformance() const;
    Q_INVOKABLE void setDefaultPerformance(const QString &performance);
    Q_INVOKABLE QString defaultFormat() const;
    Q_INVOKABLE void setDefaultFormat(const QString &format);
    // Applies one canvas preset (16:9, 9:16, 1:1, 4:3) to both defaults
    // in a single change; unknown names are ignored.
    Q_INVOKABLE void applyScenePreset(const QString &name);
    // Clears all general overrides to defaults.
    Q_INVOKABLE void resetGeneral();

signals:
    void isDarkChanged();
    void followSystemChanged();
    void systemDarkChanged();
    void windowGeometryChanged();
    void shortcutsChanged();
    void appearanceChanged();
    void generalChanged();

private:
    void load();
    void persist();
    void persistWindow();
    void loadShortcuts();
    void loadAppearance();
    void persistAppearance();
    void loadGeneral();
    void persistGeneral();
    void loadImportedFonts();
    void applyFontFamily();
    void refreshFontMissing();
    void refreshSystemDark();
    void onSystemSchemeChanged();

    // Explicit user choice; meaningful only when not following the system.
    bool m_isDark = true;
    bool m_followSystem = true;
    // Last seen OS scheme. Unknown maps to dark (previous default).
    bool m_systemDark = true;
    // Last normal geometry; applied on launch when present.
    bool m_hasWindowGeometry = false;
    int m_windowX = 0;
    int m_windowY = 0;
    int m_windowWidth = 900;
    int m_windowHeight = 640;
    bool m_windowMaximized = false;
    // Non-default shortcut sequences by action id.
    QVariantMap m_shortcutOverrides;
    // Non-default appearance colors by AppTheme key, split per theme.
    QVariantMap m_lightColors;
    QVariantMap m_darkColors;
    QString m_radiusPreset = QStringLiteral("rounded");
    int m_customRadiusSmall = 6;
    int m_customRadiusMedium = 8;
    int m_customRadiusLarge = 10;
    int m_customRadiusXLarge = 12;
    QString m_fontFamily;
    bool m_showZoomPill = true;
    bool m_showWindowControls = true;
    QStringList m_importedFonts;
    // Detected family per imported file name. Populated at load/import
    // from the QFontDatabase id so QML never needs per-row FontLoaders.
    QMap<QString, QString> m_importedFontFamily;
    bool m_fontMissing = false;
    // General defaults for new designs + video export.
    int m_defaultSceneWidth = 1920;
    int m_defaultSceneHeight = 1080;
    QString m_defaultSceneColor = QStringLiteral("#ffffff");
    double m_defaultDuration = 4.0;
    QString m_defaultQuality = QStringLiteral("hd");
    int m_defaultFps = 30;
    QString m_defaultPerformance = QStringLiteral("normal");
    QString m_defaultFormat = QStringLiteral("mp4");
};
