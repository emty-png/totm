#include <QDebug>
#include <QGuiApplication>
#include <QQmlApplicationEngine>

// Drops known-benign third-party theme noise: KDE Breeze styling of the
// stock FileDialog (null ButtonBackground, SideBar binding loops) and
// missing desktop icon themes. Scoped to those sources only, so warnings
// from Totm QML and the backends still reach the console.
void totMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    const QString file = QString::fromUtf8(context.file ? context.file : "");
    if (file.contains(QStringLiteral("org/kde/breeze"))
        || file.contains(QStringLiteral("Dialogs/quickimpl/qml/SideBar.qml"))
        || msg.contains(QStringLiteral("kf.iconthemes"))) {
        return;
    }
    // Default-handler formatting (bare message); aborts on fatal like it.
    fprintf(stderr, "%s\n", qPrintable(msg));
    if (type == QtFatalMsg)
        abort();
}

int main(int argc, char *argv[])
{
    qInstallMessageHandler(totMessageHandler);

    QGuiApplication app(argc, argv);
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
