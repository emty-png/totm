#include <QDebug>
#include <QGuiApplication>
#include <QQmlApplicationEngine>

// Message filter for known-benign third-party theme noise: KDE Breeze
// styling of stock FileDialogs and missing desktop icon themes. Scoped to
// those sources only; Totm QML and backend warnings still reach stderr.
void totMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    const QString file = QString::fromUtf8(context.file ? context.file : "");
    if (file.contains(QStringLiteral("org/kde/breeze"))
        || file.contains(QStringLiteral("Dialogs/quickimpl/qml/SideBar.qml"))
        || msg.contains(QStringLiteral("kf.iconthemes"))) {
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

    QQmlApplicationEngine engine;

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.loadFromModule(QStringLiteral("Totm"), QStringLiteral("Main"));

    return app.exec();
}
