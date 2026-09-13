#pragma once

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QQmlEngine>
#include <QQmlNetworkAccessManagerFactory>

// PluginNetworkGuard: defense-in-depth for QML-only plugins.
//
// The manifest scan already rejects XHR/fetch/Remote imports by text, but
// text scans can be dodged (dynamic strings, aliases). This factory makes
// dodging pointless: the QML engine cannot open http/https at all, so a
// plugin cannot exfiltrate or fetch remote code even with a hand-built
// request. The app itself loads nothing remote (all scenes, blobs, and
// icons are local files), so blocking remote transport changes no
// built-in behavior. QtMultimedia uses its own backend, unaffected.
// Installed once in main() before the engine loads.
class PluginBlockingNam : public QNetworkAccessManager {
    Q_OBJECT
public:
    explicit PluginBlockingNam(QObject *parent = nullptr)
        : QNetworkAccessManager(parent) {
    }

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request, QIODevice *outgoingData) override {
        const QString scheme = request.url().scheme().toLower();
        // Local files, data URIs, and qrc resources keep working; remote
        // transport is replaced with an invalid URL, which fails closed
        // with ProtocolUnknownError instead of leaving the sandbox.
        if (scheme == QStringLiteral("http") || scheme == QStringLiteral("https") || scheme == QStringLiteral("ftp")) {
            QNetworkRequest denied(request);
            denied.setUrl(QUrl());
            return QNetworkAccessManager::createRequest(op, denied, outgoingData);
        }
        return QNetworkAccessManager::createRequest(op, request, outgoingData);
    }
};

class PluginNetworkFactory : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager *create(QObject *parent) override {
        return new PluginBlockingNam(parent);
    }
};
