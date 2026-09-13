#include <QDebug>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QStandardPaths>

// Message filter for known-benign third-party noise: KDE Breeze styling
// of stock FileDialogs, missing desktop icon themes, the QtMultimedia
// backend banner, and VDPAU probes on machines without NVIDIA drivers
// (software fallback carries on). Scoped to those sources only; Totm
// QML and backend warnings still reach stderr.
void totMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    const QString file = QString::fromUtf8(context.file ? context.file : "");
    if (file.contains(QStringLiteral("org/kde/breeze"))
        || file.contains(QStringLiteral("Dialogs/quickimpl/qml/SideBar.qml"))
        || msg.contains(QStringLiteral("kf.iconthemes"))
        || msg.contains(QStringLiteral("Using Qt multimedia with FFmpeg"))
        || msg.contains(QStringLiteral("Failed to open VDPAU backend"))) {
        return;
    }
    // Matches the default handler (bare message); aborts on fatal.
    fprintf(stderr, "%s\n", qPrintable(msg));
    if (type == QtFatalMsg)
        abort();
}

int main(int argc, char *argv[])
{
    qInstallMessageHandler(totMessageHandler);

    QGuiApplication app(argc, argv);
    // Identity drives QSettings (org "tot", app "totm") and QStandardPaths.
    app.setApplicationName(QStringLiteral("totm"));
    app.setApplicationVersion(QStringLiteral("0.1.0"));
    app.setOrganizationName(QStringLiteral("tot"));
    // Window/taskbar icon (X11, Wayland, Windows).
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/totm.png")));
    // The desktop id drives portal registration (Wayland app-id
    // matching, notifications). Claim it only when totm.desktop is
    // actually installed: dev builds run straight from the build tree,
    // where the portal lookup fails and Qt warns on every launch.
    if (!QStandardPaths::locateAll(QStandardPaths::ApplicationsLocation,
                                   QStringLiteral("totm.desktop"))
             .isEmpty()) {
        app.setDesktopFileName(QStringLiteral("totm"));
    }

    QQmlApplicationEngine engine;

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.loadFromModule(QStringLiteral("Totm"), QStringLiteral("Main"));

    return app.exec();
}
