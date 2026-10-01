#include "SettingsStore.h"

#include <algorithm>
#include <utility>
#include <QColor>
#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeySequence>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QQuickWindow>
#include <QScreen>
#include <QSet>
#include <QSettings>
#include <QStandardPaths>
#include <QStyleHints>
#include <QTemporaryDir>
#include <QUrl>
#include <QWindow>

#include <optional>

namespace {
constexpr char kFollowKey[] = "theme/followSystem";
constexpr char kDarkKey[] = "theme/isDark";
constexpr char kWinHasKey[] = "window/hasGeometry";
constexpr char kWinXKey[] = "window/x";
constexpr char kWinYKey[] = "window/y";
constexpr char kWinWKey[] = "window/width";
constexpr char kWinHKey[] = "window/height";
constexpr char kWinMaxKey[] = "window/maximized";

constexpr int kDefaultWidth = 900;
constexpr int kDefaultHeight = 640;
constexpr int kMinWidth = 480;
constexpr int kMinHeight = 360;

constexpr char kRadiusPresetKey[] = "appearance/radiusPreset";
constexpr char kRadiusSmallKey[] = "appearance/radiusSmall";
constexpr char kRadiusMediumKey[] = "appearance/radiusMedium";
constexpr char kRadiusLargeKey[] = "appearance/radiusLarge";
constexpr char kRadiusXLargeKey[] = "appearance/radiusXLarge";
constexpr char kFontFamilyKey[] = "appearance/fontFamily";
constexpr char kZoomPillKey[] = "appearance/showZoomPill";
constexpr char kWindowControlsKey[] = "appearance/showWindowControls";
constexpr char kTopBarKey[] = "appearance/showTopBar";
constexpr char kThemeToggleKey[] = "appearance/showThemeToggle";
constexpr char kWindowDragKey[] = "appearance/windowDragEnabled";
constexpr char kTabPositionKey[] = "appearance/tabPosition";
constexpr char kTabRailCollapsedKey[] = "appearance/tabRailCollapsed";
constexpr char kCursorSizeKey[] = "appearance/cursorSize";

constexpr char kGenSceneWKey[] = "general/sceneWidth";
constexpr char kGenSceneHKey[] = "general/sceneHeight";
constexpr char kGenSceneColorKey[] = "general/sceneColor";
constexpr char kGenDurationKey[] = "general/duration";
constexpr char kGenQualityKey[] = "general/quality";
constexpr char kGenFpsKey[] = "general/fps";
constexpr char kGenPerformanceKey[] = "general/performance";
constexpr char kGenFormatKey[] = "general/format";
constexpr char kGenLowSpecKey[] = "general/lowSpec";

constexpr int kSceneMin = 16;
constexpr int kSceneMax = 7680;
constexpr double kDurationMin = 0.5;
constexpr double kDurationMax = 1800.0;

constexpr int kRadiusMin = 0;
constexpr int kRadiusMax = 28;

// Known shortcut action ids. QML defaults live in ShortcutState; C++ only
// accepts these so corrupt storage or callers can't pollute the group.
bool isKnownShortcutId(const QString &id) {
    static const QSet<QString> known = {
        QStringLiteral("homeNew"), QStringLiteral("homeOpen"), QStringLiteral("homeRename"), QStringLiteral("homeDelete"),
        QStringLiteral("homeDuplicate"), QStringLiteral("homeStar"), QStringLiteral("toolSelect"), QStringLiteral("toolRect"),
        QStringLiteral("toolEllipse"), QStringLiteral("toolTriangle"), QStringLiteral("toolStar"), QStringLiteral("toolPen"),
        QStringLiteral("toolText"), QStringLiteral("toolImage"), QStringLiteral("editUndo"), QStringLiteral("editRedo"),
        QStringLiteral("editCopy"), QStringLiteral("editPaste"), QStringLiteral("editDuplicate"), QStringLiteral("editDelete"),
        QStringLiteral("editGroup"), QStringLiteral("editUngroup"), QStringLiteral("arrangeFront"), QStringLiteral("arrangeBack"),
        QStringLiteral("arrangeForward"), QStringLiteral("arrangeBackward"), QStringLiteral("layersRename"),
        QStringLiteral("nudgeLeft"), QStringLiteral("nudgeRight"), QStringLiteral("nudgeUp"), QStringLiteral("nudgeDown"),
        QStringLiteral("nudgeLeftBig"), QStringLiteral("nudgeRightBig"), QStringLiteral("nudgeUpBig"), QStringLiteral("nudgeDownBig"),
        QStringLiteral("canvasZoomIn"), QStringLiteral("canvasZoomOut"), QStringLiteral("canvasZoomFit"),
        QStringLiteral("modeToggle"), QStringLiteral("modeDesign"), QStringLiteral("modeAnimate"), QStringLiteral("transportPlay"),
        QStringLiteral("transportStepBack"), QStringLiteral("transportStepFwd"), QStringLiteral("transportStart"),
        QStringLiteral("transportEnd"), QStringLiteral("timelineZoomIn"), QStringLiteral("timelineZoomOut"),
    };
    return known.contains(id);
}

// A chord is unusable when it carries no real trigger key: bare words
// like "Ctrl" parse to Key_unknown, trailing modifiers ("Ctrl+Shift")
// parse to the modifier key itself. Both must be rejected.
bool isNonTriggerKey(Qt::Key key) {
    switch (key) {
    case Qt::Key_unknown:
    case Qt::Key_Shift:
    case Qt::Key_Control:
    case Qt::Key_Alt:
    case Qt::Key_Meta:
    case Qt::Key_AltGr:
    case Qt::Key_Super_L:
    case Qt::Key_Super_R:
    case Qt::Key_Hyper_L:
    case Qt::Key_Hyper_R:
        return true;
    default:
        return false;
    }
}

std::optional<QString> canonicalShortcut(const QString &raw) {
    const QString trimmed = raw.trimmed();
    if (trimmed.isEmpty())
        return QString();
    const QKeySequence seq(trimmed, QKeySequence::PortableText);
    if (seq.isEmpty())
        return std::nullopt;
    // Bare modifiers ("Ctrl", "Ctrl+Shift") parse but never make sane
    // shortcuts: every chord must carry a real key.
    bool anyReal = false;
    for (int i = 0; i < seq.count(); i++) {
        if (!isNonTriggerKey(seq[i].key())) {
            anyReal = true;
            break;
        }
    }
    if (!anyReal)
        return std::nullopt;
    return seq.toString(QKeySequence::PortableText);
}

// Validates a stored rect against current screens.
// Contract: size is clamped to [480x360, largest screen]; position must
// intersect some screen, else the rect is centered on the primary screen.
QRect validatedRect(int x, int y, int w, int h) {
    const QList<QScreen *> screens = QGuiApplication::screens();
    if (screens.isEmpty())
        return QRect(x, y, w, h);
    int maxW = kDefaultWidth;
    int maxH = kDefaultHeight;
    for (const QScreen *s : screens) {
        const QRect avail = s->availableGeometry();
        maxW = qMax(maxW, avail.width());
        maxH = qMax(maxH, avail.height());
    }
    w = qBound(kMinWidth, w, maxW);
    h = qBound(kMinHeight, h, maxH);
    QRect rect(x, y, w, h);
    for (const QScreen *s : screens) {
        if (s->availableGeometry().intersects(rect))
            return rect;
    }
    const QRect primary = QGuiApplication::primaryScreen()->availableGeometry();
    return QRect(primary.x() + (primary.width() - w) / 2, primary.y() + (primary.height() - h) / 2, w, h);
}

// Known AppTheme color keys. QML defaults live in AppTheme; C++ only
// accepts these so corrupt storage can't pollute the palette.
bool isKnownAppearanceColor(const QString &key) {
    static const QSet<QString> known = {
        QStringLiteral("background"), QStringLiteral("foreground"), QStringLiteral("surface"), QStringLiteral("border"),
        QStringLiteral("muted"), QStringLiteral("hover"), QStringLiteral("pressed"), QStringLiteral("closeHover"),
        QStringLiteral("closePressed"), QStringLiteral("canvas"), QStringLiteral("sceneFrame"),
        QStringLiteral("fieldBorder"), QStringLiteral("selection"), QStringLiteral("snapGuide"),
        QStringLiteral("layerSelected"),
    };
    return known.contains(key);
}

bool isKnownRadiusPreset(const QString &preset) {
    return preset == QStringLiteral("sharp") || preset == QStringLiteral("rounded") || preset == QStringLiteral("pill")
        || preset == QStringLiteral("custom");
}

bool isKnownTabPosition(const QString &position) {
    return position == QStringLiteral("top") || position == QStringLiteral("bottom") || position == QStringLiteral("left")
        || position == QStringLiteral("right");
}

// Canonical #rrggbb (opaque) or #aarrggbb (translucent) form, lowercase.
// QColor accepts both #rrggbb and #aarrggbb; name() would drop alpha so
// translucent values keep the HexArgb form.
std::optional<QString> canonicalAppearanceColor(const QString &raw) {
    const QString trimmed = raw.trimmed();
    if (trimmed.isEmpty())
        return QString();
    const QColor c(trimmed);
    if (!c.isValid())
        return std::nullopt;
    if (c.alpha() < 255)
        return c.name(QColor::HexArgb).toLower();
    return c.name(QColor::HexRgb).toLower();
}

int clampedRadius(int v) {
    return qBound(kRadiusMin, v, kRadiusMax);
}

int clampedSceneSize(int v) {
    return qBound(kSceneMin, v, kSceneMax);
}

double clampedDuration(double v) {
    return qBound(kDurationMin, v, kDurationMax);
}

bool isKnownQuality(const QString &quality) {
    return quality == QStringLiteral("sd") || quality == QStringLiteral("hd") || quality == QStringLiteral("4k");
}

bool isKnownPerformance(const QString &performance) {
    return performance == QStringLiteral("slow") || performance == QStringLiteral("normal")
        || performance == QStringLiteral("fast");
}

bool isKnownFormat(const QString &format) {
    return format == QStringLiteral("mp4") || format == QStringLiteral("webm") || format == QStringLiteral("gif");
}

bool isSafeFontName(const QString &name) {
    if (name.isEmpty() || name.contains(QLatin1Char('/')) || name.contains(QLatin1Char('\\'))
        || name.contains(QStringLiteral("..")))
        return false;
    const QString lower = name.toLower();
    return lower.endsWith(QStringLiteral(".ttf")) || lower.endsWith(QStringLiteral(".otf"))
        || lower.endsWith(QStringLiteral(".ttc")) || lower.endsWith(QStringLiteral(".woff"))
        || lower.endsWith(QStringLiteral(".woff2"));
}

// Explicit OS-font choice in appearance/fontFamily (empty means bundled
// Inter). Compared case-insensitively so hand-edited storage still maps.
bool isSystemFontChoice(const QString &family) {
    return family.trimmed().compare(QStringLiteral("system"), Qt::CaseInsensitive) == 0;
}
} // namespace

SettingsStore *SettingsStore::create(QQmlEngine *engine, QJSEngine *scriptEngine) {
    Q_UNUSED(scriptEngine);
    auto *store = new SettingsStore(engine);
    QJSEngine::setObjectOwnership(store, QJSEngine::CppOwnership);
    return store;
}

SettingsStore *SettingsStore::s_instance = nullptr;

SettingsStore *SettingsStore::instance() {
    return s_instance;
}

SettingsStore::SettingsStore(QObject *parent)
    : QObject(parent) {
    s_instance = this;
    refreshSystemDark();
    load();
    loadImportedFonts();
    refreshFontMissing();
    applyFontFamily();
    // While following, OS scheme changes flow through isDark.
    auto *hints = QGuiApplication::styleHints();
    if (hints) {
        connect(hints, &QStyleHints::colorSchemeChanged, this, &SettingsStore::onSystemSchemeChanged);
    }
}

SettingsStore::~SettingsStore() {
    if (s_instance == this)
        s_instance = nullptr;
}

bool SettingsStore::isDark() const {
    return m_followSystem ? m_systemDark : m_isDark;
}

void SettingsStore::setIsDark(bool dark) {
    const bool oldEffective = isDark();
    const bool oldFollow = m_followSystem;
    m_isDark = dark;
    m_followSystem = false;
    persist();
    if (oldFollow != m_followSystem)
        emit followSystemChanged();
    if (oldEffective != isDark())
        emit isDarkChanged();
}

void SettingsStore::toggle() {
    setIsDark(!isDark());
}

bool SettingsStore::followSystem() const {
    return m_followSystem;
}

void SettingsStore::setFollowSystem(bool follow) {
    if (m_followSystem == follow)
        return;
    const bool oldEffective = isDark();
    m_followSystem = follow;
    persist();
    emit followSystemChanged();
    if (oldEffective != isDark())
        emit isDarkChanged();
}

void SettingsStore::useSystemTheme() {
    setFollowSystem(true);
}

bool SettingsStore::systemDark() const {
    return m_systemDark;
}

void SettingsStore::load() {
    QSettings settings;
    m_followSystem = settings.value(QString::fromLatin1(kFollowKey), true).toBool();
    m_isDark = settings.value(QString::fromLatin1(kDarkKey), m_systemDark).toBool();
    m_hasWindowGeometry = settings.value(QString::fromLatin1(kWinHasKey), false).toBool();
    m_windowX = settings.value(QString::fromLatin1(kWinXKey), 0).toInt();
    m_windowY = settings.value(QString::fromLatin1(kWinYKey), 0).toInt();
    m_windowWidth = settings.value(QString::fromLatin1(kWinWKey), kDefaultWidth).toInt();
    m_windowHeight = settings.value(QString::fromLatin1(kWinHKey), kDefaultHeight).toInt();
    m_windowMaximized = settings.value(QString::fromLatin1(kWinMaxKey), false).toBool();
    loadShortcuts();
    loadAppearance();
    loadGeneral();
}

void SettingsStore::loadShortcuts() {
    m_shortcutOverrides.clear();
    QSettings settings;
    settings.beginGroup(QStringLiteral("shortcuts"));
    const QStringList keys = settings.childKeys();
    for (const QString &id : keys) {
        if (!isKnownShortcutId(id))
            continue;
        const QString raw = settings.value(id).toString();
        const auto canon = canonicalShortcut(raw);
        if (!canon.has_value() || canon->isEmpty())
            continue;
        m_shortcutOverrides.insert(id, *canon);
    }
    settings.endGroup();
}

QVariantMap SettingsStore::shortcutOverrides() const {
    return m_shortcutOverrides;
}

QString SettingsStore::shortcut(const QString &id, const QString &fallback) const {
    if (!isKnownShortcutId(id))
        return fallback;
    return m_shortcutOverrides.value(id, fallback).toString();
}

void SettingsStore::setShortcut(const QString &id, const QString &sequence) {
    if (!isKnownShortcutId(id))
        return;
    const auto canon = canonicalShortcut(sequence);
    if (!canon.has_value())
        return;
    if (canon->isEmpty()) {
        resetShortcut(id);
        return;
    }
    if (m_shortcutOverrides.value(id).toString() == *canon)
        return;
    m_shortcutOverrides.insert(id, *canon);
    QSettings settings;
    settings.setValue(QStringLiteral("shortcuts/") + id, *canon);
    settings.sync();
    emit shortcutsChanged();
}

void SettingsStore::resetShortcut(const QString &id) {
    if (!isKnownShortcutId(id))
        return;
    if (!m_shortcutOverrides.contains(id))
        return;
    m_shortcutOverrides.remove(id);
    QSettings settings;
    settings.remove(QStringLiteral("shortcuts/") + id);
    settings.sync();
    emit shortcutsChanged();
}

void SettingsStore::resetAllShortcuts() {
    if (m_shortcutOverrides.isEmpty())
        return;
    m_shortcutOverrides.clear();
    QSettings settings;
    settings.beginGroup(QStringLiteral("shortcuts"));
    settings.remove(QString());
    settings.endGroup();
    settings.sync();
    emit shortcutsChanged();
}

void SettingsStore::loadAppearance() {
    m_lightColors.clear();
    m_darkColors.clear();
    QSettings settings;
    settings.beginGroup(QStringLiteral("appearanceColorsLight"));
    for (const QString &key : settings.childKeys()) {
        if (!isKnownAppearanceColor(key))
            continue;
        const auto canon = canonicalAppearanceColor(settings.value(key).toString());
        if (!canon.has_value() || canon->isEmpty())
            continue;
        m_lightColors.insert(key, *canon);
    }
    settings.endGroup();
    settings.beginGroup(QStringLiteral("appearanceColorsDark"));
    for (const QString &key : settings.childKeys()) {
        if (!isKnownAppearanceColor(key))
            continue;
        const auto canon = canonicalAppearanceColor(settings.value(key).toString());
        if (!canon.has_value() || canon->isEmpty())
            continue;
        m_darkColors.insert(key, *canon);
    }
    settings.endGroup();
    const QString preset = settings.value(QString::fromLatin1(kRadiusPresetKey), QStringLiteral("rounded")).toString();
    m_radiusPreset = isKnownRadiusPreset(preset) ? preset : QStringLiteral("rounded");
    m_customRadiusSmall = clampedRadius(settings.value(QString::fromLatin1(kRadiusSmallKey), 6).toInt());
    m_customRadiusMedium = clampedRadius(settings.value(QString::fromLatin1(kRadiusMediumKey), 8).toInt());
    m_customRadiusLarge = clampedRadius(settings.value(QString::fromLatin1(kRadiusLargeKey), 10).toInt());
    m_customRadiusXLarge = clampedRadius(settings.value(QString::fromLatin1(kRadiusXLargeKey), 12).toInt());
    m_fontFamily = settings.value(QString::fromLatin1(kFontFamilyKey), QString()).toString().trimmed();
    m_showZoomPill = settings.value(QString::fromLatin1(kZoomPillKey), true).toBool();
    m_showWindowControls = settings.value(QString::fromLatin1(kWindowControlsKey), true).toBool();
    m_showTopBar = settings.value(QString::fromLatin1(kTopBarKey), true).toBool();
    m_showThemeToggle = settings.value(QString::fromLatin1(kThemeToggleKey), true).toBool();
    m_windowDragEnabled = settings.value(QString::fromLatin1(kWindowDragKey), true).toBool();
    const QString tabPos = settings.value(QString::fromLatin1(kTabPositionKey), QStringLiteral("top")).toString().trimmed().toLower();
    m_tabPosition = isKnownTabPosition(tabPos) ? tabPos : QStringLiteral("top");
    m_tabRailCollapsed = settings.value(QString::fromLatin1(kTabRailCollapsedKey), false).toBool();
    m_cursorSize = qBound(12, settings.value(QString::fromLatin1(kCursorSizeKey), 20).toInt(), 32);
}

void SettingsStore::persistAppearance() {
    QSettings settings;
    settings.setValue(QString::fromLatin1(kRadiusPresetKey), m_radiusPreset);
    settings.setValue(QString::fromLatin1(kRadiusSmallKey), m_customRadiusSmall);
    settings.setValue(QString::fromLatin1(kRadiusMediumKey), m_customRadiusMedium);
    settings.setValue(QString::fromLatin1(kRadiusLargeKey), m_customRadiusLarge);
    settings.setValue(QString::fromLatin1(kRadiusXLargeKey), m_customRadiusXLarge);
    settings.setValue(QString::fromLatin1(kFontFamilyKey), m_fontFamily);
    settings.setValue(QString::fromLatin1(kZoomPillKey), m_showZoomPill);
    settings.setValue(QString::fromLatin1(kWindowControlsKey), m_showWindowControls);
    settings.setValue(QString::fromLatin1(kTopBarKey), m_showTopBar);
    settings.setValue(QString::fromLatin1(kThemeToggleKey), m_showThemeToggle);
    settings.setValue(QString::fromLatin1(kWindowDragKey), m_windowDragEnabled);
    settings.setValue(QString::fromLatin1(kTabPositionKey), m_tabPosition);
    settings.setValue(QString::fromLatin1(kTabRailCollapsedKey), m_tabRailCollapsed);
    settings.setValue(QString::fromLatin1(kCursorSizeKey), m_cursorSize);
    settings.sync();
}

QVariantMap SettingsStore::lightColors() const {
    return m_lightColors;
}

QVariantMap SettingsStore::darkColors() const {
    return m_darkColors;
}

QString SettingsStore::appearanceColor(const QString &key, bool dark, const QString &fallback) const {
    if (!isKnownAppearanceColor(key))
        return fallback;
    const QVariantMap &map = dark ? m_darkColors : m_lightColors;
    return map.value(key, fallback).toString();
}

void SettingsStore::setAppearanceColor(const QString &key, bool dark, const QString &color) {
    if (!isKnownAppearanceColor(key))
        return;
    const auto canon = canonicalAppearanceColor(color);
    if (!canon.has_value())
        return;
    if (canon->isEmpty()) {
        resetAppearanceColor(key, dark);
        return;
    }
    QVariantMap &map = dark ? m_darkColors : m_lightColors;
    if (map.value(key).toString() == *canon)
        return;
    map.insert(key, *canon);
    QSettings settings;
    const QString group = dark ? QStringLiteral("appearanceColorsDark/") : QStringLiteral("appearanceColorsLight/");
    settings.setValue(group + key, *canon);
    settings.sync();
    emit appearanceChanged();
}

void SettingsStore::resetAppearanceColor(const QString &key, bool dark) {
    if (!isKnownAppearanceColor(key))
        return;
    QVariantMap &map = dark ? m_darkColors : m_lightColors;
    if (!map.contains(key))
        return;
    map.remove(key);
    QSettings settings;
    const QString group = dark ? QStringLiteral("appearanceColorsDark/") : QStringLiteral("appearanceColorsLight/");
    settings.remove(group + key);
    settings.sync();
    emit appearanceChanged();
}

void SettingsStore::resetAllAppearanceColors(bool dark) {
    QVariantMap &map = dark ? m_darkColors : m_lightColors;
    if (map.isEmpty())
        return;
    map.clear();
    QSettings settings;
    settings.beginGroup(dark ? QStringLiteral("appearanceColorsDark") : QStringLiteral("appearanceColorsLight"));
    settings.remove(QString());
    settings.endGroup();
    settings.sync();
    emit appearanceChanged();
}

QString SettingsStore::radiusPreset() const {
    return m_radiusPreset;
}

void SettingsStore::setRadiusPreset(const QString &preset) {
    if (!isKnownRadiusPreset(preset) || m_radiusPreset == preset)
        return;
    m_radiusPreset = preset;
    persistAppearance();
    emit appearanceChanged();
}

int SettingsStore::customRadiusSmall() const {
    return m_customRadiusSmall;
}

void SettingsStore::setCustomRadiusSmall(int v) {
    v = clampedRadius(v);
    if (m_customRadiusSmall == v)
        return;
    m_customRadiusSmall = v;
    persistAppearance();
    emit appearanceChanged();
}

int SettingsStore::customRadiusMedium() const {
    return m_customRadiusMedium;
}

void SettingsStore::setCustomRadiusMedium(int v) {
    v = clampedRadius(v);
    if (m_customRadiusMedium == v)
        return;
    m_customRadiusMedium = v;
    persistAppearance();
    emit appearanceChanged();
}

int SettingsStore::customRadiusLarge() const {
    return m_customRadiusLarge;
}

void SettingsStore::setCustomRadiusLarge(int v) {
    v = clampedRadius(v);
    if (m_customRadiusLarge == v)
        return;
    m_customRadiusLarge = v;
    persistAppearance();
    emit appearanceChanged();
}

int SettingsStore::customRadiusXLarge() const {
    return m_customRadiusXLarge;
}

void SettingsStore::setCustomRadiusXLarge(int v) {
    v = clampedRadius(v);
    if (m_customRadiusXLarge == v)
        return;
    m_customRadiusXLarge = v;
    persistAppearance();
    emit appearanceChanged();
}

QString SettingsStore::fontFamily() const {
    return m_fontFamily;
}

void SettingsStore::setFontFamily(const QString &family) {
    const QString trimmed = family.trimmed();
    if (m_fontFamily == trimmed)
        return;
    m_fontFamily = trimmed;
    // QML text resolves its family at creation: the new face paints
    // after a restart (noted on the font card).
    m_fontRestartNeeded = true;
    persistAppearance();
    refreshFontMissing();
    applyFontFamily();
    emit appearanceChanged();
}

bool SettingsStore::fontRestartNeeded() const {
    return m_fontRestartNeeded;
}

void SettingsStore::restartApp() {
    QStringList args = QCoreApplication::arguments();
    args.removeFirst();
    args << QStringLiteral("--restart-wait");
    QProcess::startDetached(QCoreApplication::applicationFilePath(), args);
    // Same shutdown path as closing the window: closing triggers
    // Main.qml onClosing (saveWindowNow + TabState.saveAllOpen),
    // covering the debounced autosave window. quit() alone would
    // skip onClosing and could drop ~800ms of recent edits.
    for (QWindow *w : QGuiApplication::allWindows())
        w->close();
    QCoreApplication::quit();
}

QStringList SettingsStore::importedFonts() const {
    return m_importedFonts;
}

QVariantMap SettingsStore::importedFontFamilyMap() const {
    QVariantMap out;
    for (auto it = m_importedFontFamily.constBegin(); it != m_importedFontFamily.constEnd(); ++it)
        out.insert(it.key(), it.value());
    return out;
}

bool SettingsStore::fontMissing() const {
    return m_fontMissing;
}

bool SettingsStore::showZoomPill() const {
    return m_showZoomPill;
}

void SettingsStore::setShowZoomPill(bool show) {
    if (m_showZoomPill == show)
        return;
    m_showZoomPill = show;
    persistAppearance();
    emit appearanceChanged();
}

bool SettingsStore::showWindowControls() const {
    return m_showWindowControls;
}

void SettingsStore::setShowWindowControls(bool show) {
    if (m_showWindowControls == show)
        return;
    m_showWindowControls = show;
    persistAppearance();
    emit appearanceChanged();
}

bool SettingsStore::showTopBar() const {
    return m_showTopBar;
}

void SettingsStore::setShowTopBar(bool show) {
    if (m_showTopBar == show)
        return;
    m_showTopBar = show;
    persistAppearance();
    emit appearanceChanged();
}

bool SettingsStore::showThemeToggle() const {
    return m_showThemeToggle;
}

void SettingsStore::setShowThemeToggle(bool show) {
    if (m_showThemeToggle == show)
        return;
    m_showThemeToggle = show;
    persistAppearance();
    emit appearanceChanged();
}

bool SettingsStore::windowDragEnabled() const {
    return m_windowDragEnabled;
}

void SettingsStore::setWindowDragEnabled(bool enabled) {
    if (m_windowDragEnabled == enabled)
        return;
    m_windowDragEnabled = enabled;
    persistAppearance();
    emit appearanceChanged();
}

QString SettingsStore::tabPosition() const {
    return m_tabPosition;
}

void SettingsStore::setTabPosition(const QString &position) {
    const QString pos = position.trimmed().toLower();
    if (!isKnownTabPosition(pos) || m_tabPosition == pos)
        return;
    m_tabPosition = pos;
    persistAppearance();
    emit appearanceChanged();
}

bool SettingsStore::tabRailCollapsed() const {
    return m_tabRailCollapsed;
}

void SettingsStore::setTabRailCollapsed(bool collapsed) {
    if (m_tabRailCollapsed == collapsed)
        return;
    m_tabRailCollapsed = collapsed;
    persistAppearance();
    emit appearanceChanged();
}

int SettingsStore::cursorSize() const {
    return m_cursorSize;
}

void SettingsStore::setCursorSize(int pixels) {
    pixels = qBound(12, pixels, 32);
    if (m_cursorSize == pixels)
        return;
    m_cursorSize = pixels;
    persistAppearance();
    emit appearanceChanged();
}

void SettingsStore::refreshFontMissing() {
    // Empty means bundled Inter and "system" means the OS font: both
    // always available. Otherwise the family must exist in QFontDatabase
    // (system or imported); anything else fell back visually, so flag it
    // for the "Font not found" error.
    m_fontMissing = !m_fontFamily.isEmpty() && !isSystemFontChoice(m_fontFamily)
        && !QFontDatabase::families().contains(m_fontFamily);
}

QString SettingsStore::fontsDir() const {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        dir = QDir::homePath() + QStringLiteral("/.totm");
    if (!dir.endsWith(QStringLiteral("/totm"), Qt::CaseInsensitive))
        dir += QStringLiteral("/totm");
    return dir + QStringLiteral("/fonts");
}

QVariantList SettingsStore::loadFontCatalog() {
    // Curated web catalog (src/fonts/catalog.json, embedded under
    // :/fonts). Schema per entry: family/slug/license/category plus a
    // files[] list of repo-relative TTF paths. Extending the catalog is
    // appending one object; invalid entries warn and skip so one bad
    // row never breaks the installer.
    QVariantList out;
    QFile f(QStringLiteral(":/fonts/catalog.json"));
    if (!f.open(QIODevice::ReadOnly)) {
        qWarning() << "totm: font catalog missing from resources";
        return out;
    }
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning() << "totm: font catalog is not valid JSON:" << err.errorString();
        return out;
    }
    const QJsonArray families = doc.object().value(QStringLiteral("families")).toArray();
    for (const QJsonValue &v : families) {
        if (!v.isObject())
            continue;
        const QJsonObject o = v.toObject();
        const QString family = o.value(QStringLiteral("family")).toString().trimmed();
        const QString slug = o.value(QStringLiteral("slug")).toString().trimmed();
        QStringList files;
        for (const QJsonValue &fv : o.value(QStringLiteral("files")).toArray()) {
            const QString s = fv.toString().trimmed();
            if (!s.isEmpty())
                files.append(s);
        }
        if (family.isEmpty() || slug.isEmpty() || files.isEmpty()
            || slug.contains(QLatin1Char('/')) || slug.contains(QStringLiteral(".."))) {
            qWarning() << "totm: skipping invalid font catalog entry:" << family;
            continue;
        }
        QVariantMap entry;
        entry.insert(QStringLiteral("family"), family);
        entry.insert(QStringLiteral("slug"), slug);
        entry.insert(QStringLiteral("license"), o.value(QStringLiteral("license")).toString());
        entry.insert(QStringLiteral("category"), o.value(QStringLiteral("category")).toString());
        entry.insert(QStringLiteral("fileCount"), files.size());
        // Variable families (any [axes] file) interpolate weights at
        // render instead of shipping static instances; the editor
        // skips weight snapping for them (see nearestWeight).
        bool variable = false;
        for (const QString &path : files) {
            if (path.contains(QLatin1Char('['))) {
                variable = true;
                break;
            }
        }
        entry.insert(QStringLiteral("variable"), variable);
        out.append(entry);
    }
    return out;
}

QVariantList SettingsStore::fontCatalog() const {
    if (!m_fontCatalogLoaded) {
        const_cast<SettingsStore *>(this)->m_fontCatalog =
            const_cast<SettingsStore *>(this)->loadFontCatalog();
        const_cast<SettingsStore *>(this)->m_fontCatalogLoaded = true;
    }
    return m_fontCatalog;
}

bool SettingsStore::fontCatalogEntry(const QString &family, QVariantMap *entry) const {
    // Full entry (with files[]) re-read from the resource so the cached
    // QML-facing list stays lean; validated the same way on the way in.
    QFile f(QStringLiteral(":/fonts/catalog.json"));
    if (!f.open(QIODevice::ReadOnly))
        return false;
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return false;
    const QJsonArray families = doc.object().value(QStringLiteral("families")).toArray();
    for (const QJsonValue &v : families) {
        if (!v.isObject())
            continue;
        const QJsonObject o = v.toObject();
        if (o.value(QStringLiteral("family")).toString().trimmed().compare(family.trimmed(),
                                                                            Qt::CaseInsensitive)
            != 0)
            continue;
        const QString slug = o.value(QStringLiteral("slug")).toString().trimmed();
        QStringList files;
        for (const QJsonValue &fv : o.value(QStringLiteral("files")).toArray()) {
            const QString s = fv.toString().trimmed();
            if (!s.isEmpty())
                files.append(s);
        }
        if (slug.isEmpty() || files.isEmpty() || slug.contains(QLatin1Char('/'))
            || slug.contains(QStringLiteral("..")))
            return false;
        if (entry) {
            entry->insert(QStringLiteral("family"), o.value(QStringLiteral("family")).toString().trimmed());
            entry->insert(QStringLiteral("slug"), slug);
            entry->insert(QStringLiteral("files"), files);
        }
        return true;
    }
    return false;
}

QString SettingsStore::fontCatalogBase() const {
    // Pinned CDN snapshot from the catalog header (cdn + repo + commit).
    // Downloads refuse any other host/scheme (see installCatalogFont),
    // so a tampered catalog entry cannot redirect the installer.
    QFile f(QStringLiteral(":/fonts/catalog.json"));
    if (!f.open(QIODevice::ReadOnly))
        return QString();
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return QString();
    const QJsonObject o = doc.object();
    const QString cdn = o.value(QStringLiteral("cdn")).toString().trimmed();
    const QString repo = o.value(QStringLiteral("repo")).toString().trimmed();
    const QString pin = o.value(QStringLiteral("pin")).toString().trimmed();
    if (cdn.isEmpty() || repo.isEmpty() || pin.isEmpty())
        return QString();
    return cdn + QStringLiteral("/gh/") + repo + QStringLiteral("@") + pin + QStringLiteral("/");
}

bool SettingsStore::isFontInstalled(const QString &family) const {
    const QString name = family.trimmed();
    if (name.isEmpty())
        return false;
    // Bundled Inter is always present (loaded from resources at startup).
    if (name.compare(QStringLiteral("Inter"), Qt::CaseInsensitive) == 0)
        return QFontDatabase::families().contains(QStringLiteral("Inter"));
    for (auto it = m_importedFontFamily.constBegin(); it != m_importedFontFamily.constEnd(); ++it) {
        if (it.value().compare(name, Qt::CaseInsensitive) == 0)
            return true;
    }
    // Anything else on the system counts too: the editor picker only
    // lists families that actually resolve.
    return QFontDatabase::families().contains(name);
}

bool SettingsStore::fontDownloadBusy() const {
    return m_fontDownloadBusy;
}

QString SettingsStore::fontDownloadFamily() const {
    return m_dlFamily;
}

int SettingsStore::fontDownloadFileIndex() const {
    return m_dlFileIndex;
}

int SettingsStore::fontDownloadFileCount() const {
    return m_dlFileCount;
}

double SettingsStore::fontDownloadProgress() const {
    if (!m_fontDownloadBusy || m_dlFileCount <= 0)
        return 0.0;
    double frac = double(m_dlFileIndex);
    for (auto it = m_dlProgress.constBegin(); it != m_dlProgress.constEnd(); ++it) {
        const qint64 total = it.value().second;
        if (total > 0)
            frac += qBound(0.0, double(it.value().first) / double(total), 1.0);
    }
    return qBound(0.0, frac / double(m_dlFileCount), 1.0);
}

QStringList SettingsStore::fontDownloadQueue() const {
    QStringList out;
    if (!m_dlFamily.isEmpty())
        out.append(m_dlFamily);
    out.append(m_dlQueue);
    return out;
}

int SettingsStore::fontDownloadQueueTotal() const {
    return m_dlQueueTotal;
}

int SettingsStore::fontDownloadQueueDone() const {
    return m_dlQueueDone;
}

double SettingsStore::fontDownloadQueueProgress() const {
    if (!m_fontDownloadBusy || m_dlQueueTotal <= 0)
        return 0.0;
    return qBound(0.0, (double(m_dlQueueDone) + fontDownloadProgress()) / double(m_dlQueueTotal), 1.0);
}

QString SettingsStore::fontDownloadError() const {
    return m_fontDownloadError;
}

bool SettingsStore::installCatalogFont(const QString &family) {
    return installCatalogFonts(QStringList{family.trimmed()});
}

bool SettingsStore::installCatalogFonts(const QStringList &families) {
    if (m_fontDownloadBusy || !m_dlActive.isEmpty())
        return false;
    const QString base = fontCatalogBase();
    if (base.isEmpty())
        return false;
    // Allowlist: pinned CDN over https only. A catalog entry pointing
    // anywhere else is refused instead of followed.
    const QUrl probe(base);
    if (probe.scheme() != QStringLiteral("https")
        || probe.host() != QStringLiteral("cdn.jsdelivr.net"))
        return false;
    // Resolve, dedupe and drop unknowns/already-installed: the queue
    // only ever holds actionable families.
    QStringList queue;
    for (const QString &raw : families) {
        QVariantMap entry;
        if (!fontCatalogEntry(raw, &entry))
            continue;
        const QString name = entry.value(QStringLiteral("family")).toString();
        if (name.isEmpty() || isFontInstalled(name))
            continue;
        if (!queue.contains(name, Qt::CaseInsensitive))
            queue.append(name);
    }
    if (queue.isEmpty())
        return false;
    if (!m_fontNet)
        m_fontNet = new QNetworkAccessManager(this);
    m_dlQueue = queue;
    m_dlQueueTotal = queue.size();
    m_dlQueueDone = 0;
    m_fontDownloadBusy = true;
    m_fontDownloadError.clear();
    emit fontDownloadChanged();
    startNextFamily();
    return true;
}

void SettingsStore::startNextFamily() {
    if (m_dlQueue.isEmpty()) {
        m_dlFamily.clear();
        m_dlFileIndex = m_dlFileCount;
        m_fontDownloadBusy = false;
        emit fontDownloadChanged();
        return;
    }
    QVariantMap entry;
    if (!fontCatalogEntry(m_dlQueue.first(), &entry)) {
        m_dlQueue.removeFirst();
        startNextFamily();
        return;
    }
    m_dlQueue.removeFirst();
    const QString slug = entry.value(QStringLiteral("slug")).toString();
    QStringList pending = entry.value(QStringLiteral("files")).toStringList();
    pending.append(QStringLiteral("ofl/%1/OFL.txt").arg(slug));
    auto temp = std::make_unique<QTemporaryDir>();
    if (!temp->isValid()) {
        finishFontFamily(QStringLiteral("Could not stage download."));
        return;
    }
    m_dlTemp = std::move(temp);
    m_dlFamily = entry.value(QStringLiteral("family")).toString();
    m_dlSlug = slug;
    m_dlPending = pending;
    m_dlSaved.clear();
    m_dlFontIds.clear();
    m_dlFileIndex = 0;
    m_dlFileCount = pending.size();
    emit fontDownloadChanged();
    startFontFiles();
}

void SettingsStore::startFontFiles() {
    // Fill up to kParallelSlots in-flight requests; each finish
    // validates, launches its replacement, and finalizes the family
    // once pending and in-flight both drain.
    constexpr int kParallelSlots = 4;
    while (m_dlActive.size() < kParallelSlots && !m_dlPending.isEmpty()) {
        const QString rel = m_dlPending.takeFirst();
        const QUrl url(fontCatalogBase() + rel);
        if (url.scheme() != QStringLiteral("https")
            || url.host() != QStringLiteral("cdn.jsdelivr.net")) {
            finishFontFamily(QStringLiteral("Blocked unexpected download host."));
            return;
        }
        QNetworkRequest request(url);
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                             QNetworkRequest::NoLessSafeRedirectPolicy);
        QNetworkReply *reply = m_fontNet->get(request);
        m_dlActive.append(reply);
        m_dlProgress.insert(reply, qMakePair<qint64, qint64>(0, 0));
        connect(reply, &QNetworkReply::downloadProgress, this,
                [this, reply](qint64 received, qint64 total) {
                    if (!m_dlProgress.contains(reply))
                        return;
                    m_dlProgress[reply] = qMakePair(received, total);
                    emit fontDownloadChanged();
                });
        connect(reply, &QNetworkReply::finished, this, [this, reply, rel]() {
            // Stale signal after cancel()/failure: finalization already
            // closed the session, so there is nothing left to do.
            if (m_dlFinishing || !m_fontDownloadBusy || !m_dlActive.contains(reply))
                return;
            const QNetworkReply::NetworkError err = reply->error();
            const QString errStr = reply->errorString();
            const QByteArray data = reply->readAll();
            m_dlActive.removeAll(reply);
            m_dlProgress.remove(reply);
            reply->deleteLater();
            if (err != QNetworkReply::NoError) {
                finishFontFamily(errStr);
                return;
            }
            // Empty/trivial bodies are block pages, not fonts.
            if (data.size() < 1024) {
                finishFontFamily(QStringLiteral("Downloaded file is empty."));
                return;
            }
            QString saveName = QFileInfo(rel).fileName();
            if (!isSafeFontName(saveName) && saveName != QStringLiteral("OFL.txt")) {
                finishFontFamily(QStringLiteral("Unsafe file name from catalog."));
                return;
            }
            const QString dest = QDir(m_dlTemp->path()).filePath(saveName);
            QFile out(dest);
            if (!out.open(QIODevice::WriteOnly) || out.write(data) != data.size()) {
                finishFontFamily(QStringLiteral("Could not save download."));
                return;
            }
            out.close();
            // Font files must parse before install; the license travels
            // alongside unchecked (plain text). Validation registers the
            // family session-wide, so failures below unregister again.
            if (saveName != QStringLiteral("OFL.txt")) {
                const int fontId = QFontDatabase::addApplicationFont(dest);
                if (fontId < 0) {
                    finishFontFamily(QStringLiteral("Downloaded file is not a valid font."));
                    return;
                }
                m_dlFontIds.append(fontId);
            }
            m_dlSaved.append(dest);
            m_dlFileIndex++;
            emit fontDownloadChanged();
            startFontFiles();
            if (m_dlPending.isEmpty() && m_dlActive.isEmpty())
                finishFontFamily(QString());
        });
    }
}

void SettingsStore::finishFontFamily(const QString &error) {
    // Reentrancy guard: abort() below can synchronously re-emit
    // finished(), which funnels back here. The outer call owns
    // completion; the nested one stands down.
    if (m_dlFinishing)
        return;
    m_dlFinishing = true;
    // Steal the in-flight set first: abort() can synchronously re-emit
    // finished(), which must observe no live replies (else it
    // double-frees through a cleared pointer).
    const QList<QNetworkReply *> actives = m_dlActive;
    m_dlActive.clear();
    m_dlProgress.clear();
    for (QNetworkReply *reply : actives) {
        reply->abort();
        reply->deleteLater();
    }
    if (!error.isEmpty()) {
        // Validation above registers families session-wide: pull them
        // back out so a failed install leaves no ghost entries. The
        // queue stops at the first failure (predictable beats partial).
        for (int id : std::as_const(m_dlFontIds))
            QFontDatabase::removeApplicationFont(id);
        m_dlQueue.clear();
    } else {
        // Route finished files through importFont(): dedup, register and
        // row bookkeeping identical to manual imports. The OFL.txt is
        // kept beside them (ignored by the font loader, shipped as the
        // required license copy).
        for (const QString &path : std::as_const(m_dlSaved)) {
            const QString base = QFileInfo(path).fileName();
            if (base == QStringLiteral("OFL.txt")) {
                QDir().mkpath(fontsDir());
                QFile::remove(QDir(fontsDir()).filePath(m_dlSlug + QStringLiteral("-OFL.txt")));
                QFile::copy(path, QDir(fontsDir()).filePath(m_dlSlug + QStringLiteral("-OFL.txt")));
                continue;
            }
            importFont(QUrl::fromLocalFile(path));
        }
        m_dlQueueDone++;
    }
    m_dlTemp.reset();
    m_dlPending.clear();
    m_dlSaved.clear();
    m_dlFontIds.clear();
    m_dlFamily.clear();
    m_dlFileIndex = m_dlFileCount;
    m_dlFinishing = false;
    if (!error.isEmpty()) {
        m_dlQueue.clear();
        m_fontDownloadBusy = false;
        m_fontDownloadError = error;
        emit fontDownloadChanged();
        return;
    }
    emit fontDownloadChanged();
    startNextFamily();
}

void SettingsStore::cancelFontDownload() {
    if (!m_fontDownloadBusy)
        return;
    m_dlQueue.clear();
    finishFontFamily(QStringLiteral("Cancelled."));
}

QStringList SettingsStore::importedFontFamilies() const {
    return QFontDatabase::families();
}

QList<int> SettingsStore::fontWeights(const QString &family) const {
    QList<int> out;
    if (family.isEmpty())
        return out;
    const QStringList styleList = QFontDatabase::styles(family);
    for (const QString &style : styleList) {
        const int w = QFontDatabase::weight(family, style);
        const int clamped = qBound(1, w, 1000);
        if (!out.contains(clamped))
            out.append(clamped);
    }
    std::sort(out.begin(), out.end());
    return out;
}

void SettingsStore::loadImportedFonts() {
    m_importedFonts.clear();
    m_importedFontFamily.clear();
    QDir dir(fontsDir());
    if (!dir.exists())
        return;
    const QStringList files = dir.entryList(QDir::Files);
    for (const QString &name : files) {
        if (!isSafeFontName(name))
            continue;
        const QString path = dir.filePath(name);
        const int fontId = QFontDatabase::addApplicationFont(path);
        if (fontId < 0)
            continue;
        m_importedFonts.append(name);
        const QStringList families = QFontDatabase::applicationFontFamilies(fontId);
        if (!families.isEmpty())
            m_importedFontFamily.insert(name, families.first());
    }
}

void SettingsStore::applyFontFamily() {
    QFont font;
    if (isSystemFontChoice(m_fontFamily)) {
        // Default-constructed: OS font.
    } else if (!m_fontFamily.isEmpty()) {
        // Missing overrides fall back to bundled Inter (flagged via
        // fontMissing); Qt would otherwise substitute unpredictably.
        if (QFontDatabase::families().contains(m_fontFamily))
            font.setFamily(m_fontFamily);
        else
            font.setFamily(QStringLiteral("Inter"));
    } else {
        // App default: bundled Inter (loaded from resources in main()).
        font.setFamily(QStringLiteral("Inter"));
    }
    QGuiApplication::setFont(font);
    // Window updates only repaint: QML text resolves its family at
    // creation and ignores later setFont() calls, so a changed choice
    // paints after a restart (main() applies the stored value before
    // the engine loads; the font card notes the restart).
    for (QWindow *w : QGuiApplication::allWindows()) {
        if (auto *qw = qobject_cast<QQuickWindow *>(w))
            qw->update();
    }
}

QString SettingsStore::importFont(const QUrl &fileUrl) {
    const QString local = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    if (local.isEmpty())
        return QString();
    QFile src(local);
    if (!src.exists())
        return QString();
    QString name = QFileInfo(local).fileName();
    if (!isSafeFontName(name))
        return QString();
    QDir().mkpath(fontsDir());
    QString dest = QDir(fontsDir()).filePath(name);
    // Deduplicate: name (1), name (2), ... keeps imports lossless.
    if (QFile::exists(dest)) {
        const QString base = QFileInfo(name).completeBaseName();
        const QString suffix = QFileInfo(name).suffix();
        int n = 1;
        do {
            name = QStringLiteral("%1 (%2).%3").arg(base).arg(n).arg(suffix);
            dest = QDir(fontsDir()).filePath(name);
            n++;
        } while (QFile::exists(dest) && n < 100);
        if (QFile::exists(dest))
            return QString();
    }
    if (!QFile::copy(local, dest))
        return QString();
    const int fontId = QFontDatabase::addApplicationFont(dest);
    if (fontId < 0) {
        QFile::remove(dest);
        return QString();
    }
    m_importedFonts.append(name);
    const QStringList families = QFontDatabase::applicationFontFamilies(fontId);
    const QString family = families.isEmpty() ? QString() : families.first();
    if (!family.isEmpty())
        m_importedFontFamily.insert(name, family);
    emit appearanceChanged();
    return family;
}

void SettingsStore::removeImportedFont(const QString &fileName) {
    if (!m_importedFonts.contains(fileName) || !isSafeFontName(fileName))
        return;
    m_importedFonts.removeAll(fileName);
    m_importedFontFamily.remove(fileName);
    QFile::remove(QDir(fontsDir()).filePath(fileName));
    refreshFontMissing();
    emit appearanceChanged();
}

void SettingsStore::selectImportedFont(const QString &fileName) {
    if (!m_importedFonts.contains(fileName) || !isSafeFontName(fileName))
        return;
    const QString family = m_importedFontFamily.value(fileName);
    if (family.isEmpty() || family == m_fontFamily)
        return;
    m_fontFamily = family;
    m_fontRestartNeeded = true;
    persistAppearance();
    refreshFontMissing();
    applyFontFamily();
    emit appearanceChanged();
}

void SettingsStore::resetAppearance() {
    m_lightColors.clear();
    m_darkColors.clear();
    m_radiusPreset = QStringLiteral("rounded");
    m_customRadiusSmall = 6;
    m_customRadiusMedium = 8;
    m_customRadiusLarge = 10;
    m_customRadiusXLarge = 12;
    if (!m_fontFamily.isEmpty())
        m_fontRestartNeeded = true;
    m_fontFamily.clear();
    m_fontMissing = false;
    m_showZoomPill = true;
    m_showWindowControls = true;
    m_showTopBar = true;
    m_showThemeToggle = true;
    m_windowDragEnabled = true;
    m_tabPosition = QStringLiteral("top");
    m_tabRailCollapsed = false;
    m_cursorSize = 20;
    QSettings settings;
    settings.beginGroup(QStringLiteral("appearanceColorsLight"));
    settings.remove(QString());
    settings.endGroup();
    settings.beginGroup(QStringLiteral("appearanceColorsDark"));
    settings.remove(QString());
    settings.endGroup();
    persistAppearance();
    applyFontFamily();
    emit appearanceChanged();
}

int SettingsStore::applyThemeMaps(const QVariantMap &light, const QVariantMap &dark) {
    // Merge semantics: only known keys with valid colors apply, anything
    // else is skipped. Present-but-equal values count as applied (the
    // caller asked for them); unknown keys and invalid colors do not.
    int applied = 0;
    bool changed = false;
    QSettings settings;
    auto applyOne = [&](const QVariantMap &map, QVariantMap &target, const QString &group) {
        for (auto it = map.constBegin(); it != map.constEnd(); ++it) {
            if (!isKnownAppearanceColor(it.key()))
                continue;
            const auto canon = canonicalAppearanceColor(it.value().toString());
            if (!canon.has_value() || canon->isEmpty())
                continue;
            applied++;
            if (target.value(it.key()).toString() == *canon)
                continue;
            target.insert(it.key(), *canon);
            settings.setValue(group + it.key(), *canon);
            changed = true;
        }
    };
    applyOne(light, m_lightColors, QStringLiteral("appearanceColorsLight/"));
    applyOne(dark, m_darkColors, QStringLiteral("appearanceColorsDark/"));
    if (changed) {
        settings.sync();
        emit appearanceChanged();
    }
    return applied;
}

void SettingsStore::loadGeneral() {
    QSettings settings;
    m_defaultSceneWidth = clampedSceneSize(settings.value(QString::fromLatin1(kGenSceneWKey), 1920).toInt());
    m_defaultSceneHeight = clampedSceneSize(settings.value(QString::fromLatin1(kGenSceneHKey), 1080).toInt());
    const auto color = canonicalAppearanceColor(settings.value(QString::fromLatin1(kGenSceneColorKey), QStringLiteral("#ffffff")).toString());
    m_defaultSceneColor = (color.has_value() && !color->isEmpty()) ? *color : QStringLiteral("#ffffff");
    m_defaultDuration = clampedDuration(settings.value(QString::fromLatin1(kGenDurationKey), 4.0).toDouble());
    const QString quality = settings.value(QString::fromLatin1(kGenQualityKey), QStringLiteral("hd")).toString().trimmed().toLower();
    m_defaultQuality = isKnownQuality(quality) ? quality : QStringLiteral("hd");
    const int fps = settings.value(QString::fromLatin1(kGenFpsKey), 30).toInt();
    m_defaultFps = (fps == 60) ? 60 : 30;
    const QString performance = settings.value(QString::fromLatin1(kGenPerformanceKey), QStringLiteral("normal")).toString().trimmed().toLower();
    m_defaultPerformance = isKnownPerformance(performance) ? performance : QStringLiteral("normal");
    const QString format = settings.value(QString::fromLatin1(kGenFormatKey), QStringLiteral("mp4")).toString().trimmed().toLower();
    m_defaultFormat = isKnownFormat(format) ? format : QStringLiteral("mp4");
    m_lowSpecMode = settings.value(QString::fromLatin1(kGenLowSpecKey), false).toBool();
}

void SettingsStore::persistGeneral() {
    QSettings settings;
    settings.setValue(QString::fromLatin1(kGenSceneWKey), m_defaultSceneWidth);
    settings.setValue(QString::fromLatin1(kGenSceneHKey), m_defaultSceneHeight);
    settings.setValue(QString::fromLatin1(kGenSceneColorKey), m_defaultSceneColor);
    settings.setValue(QString::fromLatin1(kGenDurationKey), m_defaultDuration);
    settings.setValue(QString::fromLatin1(kGenQualityKey), m_defaultQuality);
    settings.setValue(QString::fromLatin1(kGenFpsKey), m_defaultFps);
    settings.setValue(QString::fromLatin1(kGenPerformanceKey), m_defaultPerformance);
    settings.setValue(QString::fromLatin1(kGenFormatKey), m_defaultFormat);
    settings.setValue(QString::fromLatin1(kGenLowSpecKey), m_lowSpecMode);
    settings.sync();
}

int SettingsStore::defaultSceneWidth() const {
    return m_defaultSceneWidth;
}

void SettingsStore::setDefaultSceneWidth(int v) {
    v = clampedSceneSize(v);
    if (m_defaultSceneWidth == v)
        return;
    m_defaultSceneWidth = v;
    persistGeneral();
    emit generalChanged();
}

int SettingsStore::defaultSceneHeight() const {
    return m_defaultSceneHeight;
}

void SettingsStore::setDefaultSceneHeight(int v) {
    v = clampedSceneSize(v);
    if (m_defaultSceneHeight == v)
        return;
    m_defaultSceneHeight = v;
    persistGeneral();
    emit generalChanged();
}

QString SettingsStore::defaultSceneColor() const {
    return m_defaultSceneColor;
}

void SettingsStore::setDefaultSceneColor(const QString &color) {
    const auto canon = canonicalAppearanceColor(color);
    if (!canon.has_value() || canon->isEmpty())
        return;
    if (m_defaultSceneColor == *canon)
        return;
    m_defaultSceneColor = *canon;
    persistGeneral();
    emit generalChanged();
}

double SettingsStore::defaultDuration() const {
    return m_defaultDuration;
}

void SettingsStore::setDefaultDuration(double v) {
    v = clampedDuration(v);
    if (qFuzzyCompare(m_defaultDuration, v))
        return;
    m_defaultDuration = v;
    persistGeneral();
    emit generalChanged();
}

QString SettingsStore::defaultQuality() const {
    return m_defaultQuality;
}

void SettingsStore::setDefaultQuality(const QString &quality) {
    const QString q = quality.trimmed().toLower();
    if (!isKnownQuality(q) || m_defaultQuality == q)
        return;
    m_defaultQuality = q;
    persistGeneral();
    emit generalChanged();
}

int SettingsStore::defaultFps() const {
    return m_defaultFps;
}

void SettingsStore::setDefaultFps(int v) {
    v = (v == 60) ? 60 : 30;
    if (m_defaultFps == v)
        return;
    m_defaultFps = v;
    persistGeneral();
    emit generalChanged();
}

QString SettingsStore::defaultPerformance() const {
    return m_defaultPerformance;
}

void SettingsStore::setDefaultPerformance(const QString &performance) {
    const QString p = performance.trimmed().toLower();
    if (!isKnownPerformance(p) || m_defaultPerformance == p)
        return;
    m_defaultPerformance = p;
    persistGeneral();
    emit generalChanged();
}

QString SettingsStore::defaultFormat() const {
    return m_defaultFormat;
}

void SettingsStore::setDefaultFormat(const QString &format) {
    const QString f = format.trimmed().toLower();
    if (!isKnownFormat(f) || m_defaultFormat == f)
        return;
    m_defaultFormat = f;
    persistGeneral();
    emit generalChanged();
}

bool SettingsStore::lowSpecMode() const {
    return m_lowSpecMode;
}

void SettingsStore::setLowSpecMode(bool on) {
    if (m_lowSpecMode == on)
        return;
    m_lowSpecMode = on;
    persistGeneral();
    emit generalChanged();
}

void SettingsStore::applyScenePreset(const QString &name) {
    const QString n = name.trimmed().toLower();
    int w = m_defaultSceneWidth;
    int h = m_defaultSceneHeight;
    if (n == QStringLiteral("16:9"))
        w = 1920, h = 1080;
    else if (n == QStringLiteral("9:16"))
        w = 1080, h = 1920;
    else if (n == QStringLiteral("1:1"))
        w = 1080, h = 1080;
    else if (n == QStringLiteral("4:3"))
        w = 1600, h = 1200;
    else
        return;
    if (w == m_defaultSceneWidth && h == m_defaultSceneHeight)
        return;
    m_defaultSceneWidth = w;
    m_defaultSceneHeight = h;
    persistGeneral();
    emit generalChanged();
}

void SettingsStore::resetGeneral() {
    if (m_defaultSceneWidth == 1920 && m_defaultSceneHeight == 1080 && m_defaultSceneColor == QStringLiteral("#ffffff")
        && qFuzzyCompare(m_defaultDuration, 4.0) && m_defaultQuality == QStringLiteral("hd") && m_defaultFps == 30
        && m_defaultPerformance == QStringLiteral("normal") && m_defaultFormat == QStringLiteral("mp4")
        && m_lowSpecMode == false)
        return;
    m_defaultSceneWidth = 1920;
    m_defaultSceneHeight = 1080;
    m_defaultSceneColor = QStringLiteral("#ffffff");
    m_defaultDuration = 4.0;
    m_defaultQuality = QStringLiteral("hd");
    m_defaultFps = 30;
    m_defaultPerformance = QStringLiteral("normal");
    m_defaultFormat = QStringLiteral("mp4");
    m_lowSpecMode = false;
    persistGeneral();
    emit generalChanged();
}

void SettingsStore::persist() {
    QSettings settings;
    settings.setValue(QString::fromLatin1(kFollowKey), m_followSystem);
    settings.setValue(QString::fromLatin1(kDarkKey), m_isDark);
    settings.sync();
}

void SettingsStore::persistWindow() {
    QSettings settings;
    settings.setValue(QString::fromLatin1(kWinHasKey), m_hasWindowGeometry);
    settings.setValue(QString::fromLatin1(kWinXKey), m_windowX);
    settings.setValue(QString::fromLatin1(kWinYKey), m_windowY);
    settings.setValue(QString::fromLatin1(kWinWKey), m_windowWidth);
    settings.setValue(QString::fromLatin1(kWinHKey), m_windowHeight);
    settings.setValue(QString::fromLatin1(kWinMaxKey), m_windowMaximized);
    settings.sync();
}

void SettingsStore::refreshSystemDark() {
    auto *hints = QGuiApplication::styleHints();
    if (!hints)
        return;
    const Qt::ColorScheme scheme = hints->colorScheme();
    if (scheme == Qt::ColorScheme::Unknown)
        m_systemDark = true;
    else
        m_systemDark = (scheme == Qt::ColorScheme::Dark);
}

void SettingsStore::onSystemSchemeChanged() {
    const bool oldSystem = m_systemDark;
    const bool oldEffective = isDark();
    refreshSystemDark();
    if (oldSystem != m_systemDark)
        emit systemDarkChanged();
    if (m_followSystem && oldEffective != isDark())
        emit isDarkChanged();
}

int SettingsStore::windowX() const {
    return m_windowX;
}

int SettingsStore::windowY() const {
    return m_windowY;
}

int SettingsStore::windowWidth() const {
    return m_windowWidth;
}

int SettingsStore::windowHeight() const {
    return m_windowHeight;
}

bool SettingsStore::windowMaximized() const {
    return m_windowMaximized;
}

bool SettingsStore::hasWindowGeometry() const {
    return m_hasWindowGeometry;
}

QVariantMap SettingsStore::windowGeometry() const {
    const QRect rect = validatedRect(m_windowX, m_windowY, m_windowWidth, m_windowHeight);
    QVariantMap out;
    out[QStringLiteral("x")] = rect.x();
    out[QStringLiteral("y")] = rect.y();
    out[QStringLiteral("width")] = rect.width();
    out[QStringLiteral("height")] = rect.height();
    out[QStringLiteral("maximized")] = m_windowMaximized;
    out[QStringLiteral("hasGeometry")] = m_hasWindowGeometry;
    return out;
}

void SettingsStore::saveWindowGeometry(int x, int y, int width, int height, bool maximized) {
    if (maximized) {
        // Contract: the maximized frame must never overwrite the restore
        // rect; only the flag changes while maximized.
        if (m_windowMaximized == maximized && m_hasWindowGeometry)
            return;
        m_windowMaximized = true;
        m_hasWindowGeometry = true;
    } else {
        const QRect rect = validatedRect(x, y, width, height);
        const bool same = m_hasWindowGeometry && m_windowX == rect.x() && m_windowY == rect.y() && m_windowWidth == rect.width()
            && m_windowHeight == rect.height() && m_windowMaximized == false;
        if (same)
            return;
        m_windowX = rect.x();
        m_windowY = rect.y();
        m_windowWidth = rect.width();
        m_windowHeight = rect.height();
        m_windowMaximized = false;
        m_hasWindowGeometry = true;
    }
    persistWindow();
    emit windowGeometryChanged();
}

bool SettingsStore::openCredits() {
    const QString exeDir = QCoreApplication::applicationDirPath();
    const QStringList candidates = {
        exeDir + QStringLiteral("/../share/doc/totm/CREDITS.html"),
        exeDir + QStringLiteral("/../Resources/CREDITS.html"),
        exeDir + QStringLiteral("/../../../src/docs/CREDITS.html"),
    };
    for (const QString &candidate : candidates) {
        const QString path = QDir::cleanPath(candidate);
        if (QFile::exists(path))
            return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    }
    return false;
}
