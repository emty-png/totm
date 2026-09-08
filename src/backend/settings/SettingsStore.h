#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantMap>
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
    // Last normal (unmaximized) window geometry plus maximized flag.
    // QML restores these on launch and saves them debounced; the store
    // clamps to the current screens so a disconnected monitor never
    // strands the window off-screen (Wayland may ignore x/y).
    Q_PROPERTY(int windowX READ windowX NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowY READ windowY NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowWidth READ windowWidth NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowHeight READ windowHeight NOTIFY windowGeometryChanged)
    Q_PROPERTY(bool windowMaximized READ windowMaximized NOTIFY windowGeometryChanged)
    Q_PROPERTY(bool hasWindowGeometry READ hasWindowGeometry NOTIFY windowGeometryChanged)

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

    int windowX() const;
    int windowY() const;
    int windowWidth() const;
    int windowHeight() const;
    bool windowMaximized() const;
    bool hasWindowGeometry() const;
    // Validated snapshot for one-shot restore ({x,y,width,height,
    // maximized, hasGeometry}). Geometry is clamped to the available
    // screens; garbage/missing values fall back to centered 900x640.
    Q_INVOKABLE QVariantMap windowGeometry() const;
    // Saves the normal geometry; maximized only flips the flag so the
    // restore size is never overwritten by the maximized frame.
    Q_INVOKABLE void saveWindowGeometry(int x, int y, int width, int height, bool maximized);

signals:
    void isDarkChanged();
    void followSystemChanged();
    void systemDarkChanged();
    void windowGeometryChanged();

private:
    void load();
    void persist();
    void persistWindow();
    void refreshSystemDark();
    void onSystemSchemeChanged();

    // Stored explicit choice (meaningful when not following system).
    bool m_isDark = true;
    bool m_followSystem = true;
    // Last seen OS scheme; Unknown maps to dark to keep the old default.
    bool m_systemDark = true;
    // Last normal window geometry; applied on launch when present.
    bool m_hasWindowGeometry = false;
    int m_windowX = 0;
    int m_windowY = 0;
    int m_windowWidth = 900;
    int m_windowHeight = 640;
    bool m_windowMaximized = false;
};
