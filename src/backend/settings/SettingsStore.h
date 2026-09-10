#pragma once

#include <QObject>
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
};
