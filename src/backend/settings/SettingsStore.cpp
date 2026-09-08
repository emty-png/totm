#include "SettingsStore.h"

#include <QGuiApplication>
#include <QSettings>
#include <QStyleHints>

namespace {
constexpr char kFollowKey[] = "theme/followSystem";
constexpr char kDarkKey[] = "theme/isDark";
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
}

void SettingsStore::persist() {
    QSettings settings;
    settings.setValue(QString::fromLatin1(kFollowKey), m_followSystem);
    settings.setValue(QString::fromLatin1(kDarkKey), m_isDark);
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
