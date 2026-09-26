#pragma once

#include <QCursor>
#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QSet>
#include <QWindow>
#include <QtQml/qqmlregistration.h>

// CursorStore: theme-aware Bibata mouse cursors.
//
// Ownership: app-wide singleton (QML_ELEMENT + QML_SINGLETON, same pattern
// as SettingsStore). Created on first QML reference; main() never touches it.
// Threading: main thread only.
//
// Contract: every standard Qt::CursorShape the app uses (Arrow, PointingHand,
// resize grips, hands, ...) is replaced with a Bibata pixmap cursor built via
// QCursor(const QPixmap&, hotX, hotY) — see https://doc.qt.io/qt-6/qcursor.html
// Light theme uses Bibata Modern Ice, dark theme uses Bibata Modern Classic
// (SVGs vendored under packaging/cursors/, embedded as :/cursors/<theme>/).
// Wait/Busy keep the system spinners (Bibata's are animated and QCursor has
// no animation support); Blank/Bitmap pass through untouched.
//
// Mechanism: QML keeps declaring plain cursorShape values. Each hover change
// lands on the window via QWindow::setCursor, which emits CursorChange — the
// filter swaps in the themed pixmap and remembers the logical shape per
// window so refresh() (theme toggle) can repaint every window immediately.
// New windows attach through focusWindowChanged plus a full scan in refresh().
class CursorStore : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    static CursorStore *create(QQmlEngine *engine, QJSEngine *scriptEngine);
    explicit CursorStore(QObject *parent = nullptr);
    static CursorStore *instance();

    // Applies the Bibata set for the given theme (dark = Classic, light =
    // Ice) to every known window. Called from Main.qml on launch and on
    // SettingsStore.isDarkChanged. Cheap when the theme did not change.
    Q_INVOKABLE void refresh(bool dark);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    struct Entry {
        const char *file = nullptr;
        int hotX256 = 128;
        int hotY256 = 128;
    };
    static const Entry *entryFor(int shape);

    void attach(QWindow *window);
    void detach(QWindow *window);
    QCursor cursorFor(int shape);
    QCursor loadSvg(const QString &resource, int hotX256, int hotY256);

    static CursorStore *s_instance;
    // Active theme. Defaults to dark so pre-QML windows get Classic until
    // Main.qml reports the real SettingsStore theme on launch.
    bool m_dark = true;
    QHash<int, QCursor> m_cache;
    // Logical standard shape per window (pixmap cursors report BitmapCursor,
    // so the requested shape must be remembered for theme repaints).
    QHash<QWindow *, int> m_shapes;
    QSet<QWindow *> m_attached;
    bool m_guard = false;
};
