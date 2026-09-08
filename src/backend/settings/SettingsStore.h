#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QtQml/qqmlregistration.h>

// App settings for totm, separate from the design library.
// Persists explicit user choices via QSettings (native platform storage:
// org "tot", app "totm") so they survive restarts. First run follows the
// OS color scheme; the first explicit toggle pins an override.
//
// Effective theme is derived: followSystem ? systemDark : stored dark.
// QML keeps binding to isDark, so system changes flow through while
// following and stop once the user picks.
class SettingsStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool isDark READ isDark WRITE setIsDark NOTIFY isDarkChanged)
    Q_PROPERTY(bool followSystem READ followSystem WRITE setFollowSystem NOTIFY followSystemChanged)
    Q_PROPERTY(bool systemDark READ systemDark NOTIFY systemDarkChanged)

public:
    static SettingsStore *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit SettingsStore(QObject *parent = nullptr);

    bool isDark() const;
    void setIsDark(bool dark);
    Q_INVOKABLE void toggle();

    bool followSystem() const;
    void setFollowSystem(bool follow);
    Q_INVOKABLE void useSystemTheme();

    bool systemDark() const;

signals:
    void isDarkChanged();
    void followSystemChanged();
    void systemDarkChanged();

private:
    void load();
    void persist();
    void refreshSystemDark();
    void onSystemSchemeChanged();

    // Stored explicit choice (meaningful when not following system).
    bool m_isDark = true;
    bool m_followSystem = true;
    // Last seen OS scheme; Unknown maps to dark to keep the old default.
    bool m_systemDark = true;
};
