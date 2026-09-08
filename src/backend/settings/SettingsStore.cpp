#include "SettingsStore.h"

#include <QGuiApplication>
#include <QScreen>
#include <QSettings>
#include <QStyleHints>

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

// Clamps a stored rect to the current screens: size fits the largest
// screen, position lands on some screen, else centers on primary.
// Keeps monitor disconnects and stale Wayland/X11 coords from hiding
// the window.
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
} // namespace

SettingsStore *SettingsStore::create(QQmlEngine *engine, QJSEngine *scriptEngine) {
    Q_UNUSED(scriptEngine);
    auto *store = new SettingsStore(engine);
    QJSEngine::setObjectOwnership(store, QJSEngine::CppOwnership);
    return store;
}

SettingsStore::SettingsStore(QObject *parent)
    : QObject(parent) {
    refreshSystemDark();
    load();
    // Follow the OS while the user has no explicit choice; explicit
    // toggles set followSystem=false so later OS changes stay ignored.
    auto *hints = QGuiApplication::styleHints();
    if (hints) {
        connect(hints, &QStyleHints::colorSchemeChanged, this, &SettingsStore::onSystemSchemeChanged);
    }
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
        // Keep the last normal rect; only the flag changes while
        // maximized so restore never inherits the fullscreen frame.
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
