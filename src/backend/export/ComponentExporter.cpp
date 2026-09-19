#include "ComponentExporter.h"

#include "FramePaint.h"
#include "SvgPaint.h"

#include <QBuffer>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QSaveFile>
#include <QSet>

#include <algorithm>

namespace {

// Max tops per export (64 x 3 scales stays instant).
constexpr int kMaxTops = 64;
// Max file stem length (zip-safe on every desktop FS).
constexpr int kMaxStem = 80;

// CRC32 (ISO 3309) for the stored-zip entries. Table builds once.
quint32 crc32Table[256];
bool crcReady = false;

void ensureCrc() {
    if (crcReady)
        return;
    for (quint32 i = 0; i < 256; ++i) {
        quint32 c = i;
        for (int k = 0; k < 8; ++k)
            c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
        crc32Table[i] = c;
    }
    crcReady = true;
}

quint32 crc32(const QByteArray &data) {
    ensureCrc();
    quint32 c = 0xFFFFFFFFu;
    for (char b : data)
        c = crc32Table[(c ^ quint8(b)) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}

void putU16(QByteArray &out, quint16 v) {
    out.append(char(v & 0xFF));
    out.append(char((v >> 8) & 0xFF));
}

void putU32(QByteArray &out, quint32 v) {
    out.append(char(v & 0xFF));
    out.append(char((v >> 8) & 0xFF));
    out.append(char((v >> 16) & 0xFF));
    out.append(char((v >> 24) & 0xFF));
}

// Minimal stored (method 0) zip: PNG payloads are already compressed,
// so deflate would only burn CPU. Universally readable, no dependency.
QByteArray buildZip(const QList<QPair<QString, QByteArray>> &entries) {
    QByteArray out;
    struct Central {
        QByteArray name;
        quint32 crc = 0;
        quint32 size = 0;
        quint32 offset = 0;
        quint16 time = 0;
        quint16 date = 0;
    };
    QList<Central> central;
    const QDateTime now = QDateTime::currentDateTime();
    const QDate d = now.date();
    const QTime t = now.time();
    const quint16 dosTime = quint16((t.hour() << 11) | (t.minute() << 5) | (t.second() / 2));
    const quint16 dosDate = quint16(((qMax(1980, d.year()) - 1980) << 9) | (d.month() << 5) | d.day());
    for (const auto &e : entries) {
        const QByteArray name = e.first.toUtf8();
        const quint32 crc = crc32(e.second);
        const quint32 size = quint32(e.second.size());
        Central c{name, crc, size, quint32(out.size()), dosTime, dosDate};
        central.append(c);
        out.append("PK\x03\x04", 4);
        putU16(out, 20); // version needed
        putU16(out, 0x0800); // UTF-8 names
        putU16(out, 0); // stored
        putU16(out, dosTime);
        putU16(out, dosDate);
        putU32(out, crc);
        putU32(out, size);
        putU32(out, size);
        putU16(out, quint16(name.size()));
        putU16(out, 0); // no extra
        out.append(name);
        out.append(e.second);
    }
    const quint32 cdOffset = quint32(out.size());
    for (const Central &c : central) {
        out.append("PK\x01\x02", 4);
        putU16(out, 20); // version made by
        putU16(out, 20); // version needed
        putU16(out, 0x0800);
        putU16(out, 0);
        putU16(out, c.time);
        putU16(out, c.date);
        putU32(out, c.crc);
        putU32(out, c.size);
        putU32(out, c.size);
        putU16(out, quint16(c.name.size()));
        putU16(out, 0); // no extra
        putU16(out, 0); // no comment
        putU16(out, 0); // disk
        putU16(out, 0); // internal attrs
        putU32(out, 0); // external attrs
        putU32(out, c.offset);
        out.append(c.name);
    }
    const quint32 cdSize = quint32(out.size()) - cdOffset;
    out.append("PK\x05\x06", 4);
    putU16(out, 0); // disk
    putU16(out, 0); // cd disk
    putU16(out, quint16(central.size()));
    putU16(out, quint16(central.size()));
    putU32(out, cdSize);
    putU32(out, cdOffset);
    putU16(out, 0); // no comment
    return out;
}

// Filename-safe stem: word chars, space, dot and dash survive;
// anything else becomes _. Dots/whitespace trimmed at the edges so
// ".." traversals and double extensions can never form.
QString sanitizeStem(const QString &raw, const QString &fallback) {
    QString out;
    out.reserve(raw.size());
    for (QChar c : raw) {
        const uint u = c.unicode();
        const bool ok = (u >= 'a' && u <= 'z') || (u >= 'A' && u <= 'Z') || (u >= '0' && u <= '9') || c == ' '
            || c == '_' || c == '-' || (u > 127 && c.isLetterOrNumber());
        out.append(ok ? c : QLatin1Char('_'));
    }
    out = out.trimmed();
    while (!out.isEmpty() && (out.endsWith(QLatin1Char('.')) || out.endsWith(QLatin1Char(' '))))
        out.chop(1);
    while (!out.isEmpty() && (out.startsWith(QLatin1Char('.')) || out.startsWith(QLatin1Char(' '))))
        out.remove(0, 1);
    if (out.isEmpty())
        out = fallback;
    static const QSet<QString> reserved = {QStringLiteral("con"), QStringLiteral("prn"), QStringLiteral("aux"),
        QStringLiteral("nul"), QStringLiteral("com1"), QStringLiteral("com2"), QStringLiteral("com3"),
        QStringLiteral("com4"), QStringLiteral("lpt1"), QStringLiteral("lpt2"), QStringLiteral("lpt3")};
    if (reserved.contains(out.toLower()))
        out += QLatin1Char('_');
    return out.left(kMaxStem);
}

// Resolved destination: local path with the suffix appended when
// missing ("", when no usable path). Shared by the write and the QML
// overwrite probe so the two can never disagree on the target file.
QString resolvedPath(const QUrl &destination, const QString &suffix) {
    QString local = destination.isLocalFile() ? destination.toLocalFile() : destination.toString();
    if (local.isEmpty())
        return {};
    const QString want = QStringLiteral(".") + suffix.toLower();
    if (!local.endsWith(want, Qt::CaseInsensitive))
        local += want;
    return local;
}

} // namespace

ComponentExporter *ComponentExporter::create(QQmlEngine *engine, QJSEngine *scriptEngine) {
    Q_UNUSED(scriptEngine);
    auto *store = new ComponentExporter(engine);
    QJSEngine::setObjectOwnership(store, QJSEngine::CppOwnership);
    return store;
}

ComponentExporter::ComponentExporter(QObject *parent)
    : QObject(parent) {
}

QString ComponentExporter::lastError() const {
    return m_lastError;
}

void ComponentExporter::clearError() {
    if (m_lastError.isEmpty())
        return;
    m_lastError.clear();
    emit lastErrorChanged();
}

void ComponentExporter::setLastError(const QString &message) {
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}

ComponentExporter::Plan ComponentExporter::makePlan(
    const QStringList &names, const QVariantList &scales, const QString &designName, const QString &format) const {
    Plan plan;
    const bool svg = format.toLower() == QStringLiteral("svg");
    const QString ext = svg ? QStringLiteral(".svg") : QStringLiteral(".png");
    QList<int> kept;
    if (!svg) {
        for (const QVariant &v : scales) {
            const int s = qRound(v.toDouble());
            if ((s == 1 || s == 2 || s == 3) && !kept.contains(s))
                kept.append(s);
        }
        if (kept.isEmpty())
            kept.append(1);
        std::sort(kept.begin(), kept.end());
    }
    QSet<QString> used;
    const int n = qMin(names.size(), kMaxTops);
    for (int i = 0; i < n; ++i) {
        QString stem = sanitizeStem(names.at(i), tr("Component"));
        if (svg) {
            QString file = stem + ext;
            int dup = 1;
            while (used.contains(file.toLower())) {
                file = QStringLiteral("%1-%2%3").arg(stem).arg(dup).arg(ext);
                ++dup;
            }
            used.insert(file.toLower());
            plan.files.append(file);
            continue;
        }
        for (int s : kept) {
            const QString tagged = s == 1 ? stem : QStringLiteral("%1@%2x").arg(stem).arg(s);
            QString file = tagged + ext;
            int dup = 1;
            while (used.contains(file.toLower())) {
                file = QStringLiteral("%1-%2%3").arg(tagged).arg(dup).arg(ext);
                ++dup;
            }
            used.insert(file.toLower());
            plan.files.append(file);
        }
    }
    plan.zip = plan.files.size() > 1;
    if (plan.zip) {
        plan.suffix = QStringLiteral("zip");
    } else if (svg) {
        plan.suffix = QStringLiteral("svg");
    } else {
        plan.suffix = QStringLiteral("png");
    }
    plan.defaultName = plan.files.isEmpty()
        ? (svg ? QStringLiteral("Component.svg") : QStringLiteral("Component.png"))
        : (plan.zip ? sanitizeStem(designName, tr("Design")) + QStringLiteral(".zip") : plan.files.first());
    return plan;
}

QVariantMap ComponentExporter::planExport(
    const QStringList &names, const QVariantList &scales, const QString &designName, const QString &format) {
    const Plan plan = makePlan(names, scales, designName, format);
    QVariantMap out;
    out[QStringLiteral("fileCount")] = plan.files.size();
    out[QStringLiteral("suffix")] = plan.suffix;
    out[QStringLiteral("defaultName")] = plan.defaultName;
    QVariantList files;
    for (const QString &f : plan.files)
        files.append(f);
    out[QStringLiteral("files")] = files;
    return out;
}

bool ComponentExporter::destinationExists(const QUrl &destination, const QString &suffix) const {
    const QString path = resolvedPath(destination, suffix);
    return !path.isEmpty() && QFile::exists(path);
}

bool ComponentExporter::exportSelection(const QVariantList &topNodes, const QStringList &names,
    const QVariantList &scales, const QString &designName, const QUrl &destination, bool overwrite, int frameNo,
    const QString &format) {
    clearError();
    const bool svg = format.toLower() == QStringLiteral("svg");
    if (topNodes.isEmpty() || names.isEmpty()) {
        setLastError(tr("Nothing selected to export."));
        return false;
    }
    if (topNodes.size() > kMaxTops || names.size() > kMaxTops) {
        setLastError(tr("Too many components selected (max %1).").arg(kMaxTops));
        return false;
    }
    const Plan plan = makePlan(names, scales, designName, svg ? QStringLiteral("svg") : QStringLiteral("png"));
    if (plan.files.isEmpty() || topNodes.size() != names.size()) {
        setLastError(tr("Nothing selected to export."));
        return false;
    }
    const QString path = resolvedPath(destination, plan.suffix);
    if (path.isEmpty()) {
        setLastError(tr("Pick a destination first."));
        return false;
    }
    if (!overwrite && QFile::exists(path)) {
        setLastError(tr("“%1” already exists. Overwriting replaces it.").arg(QFileInfo(path).fileName()));
        return false;
    }

    // Scales resolved the same way as the plan (dedupe + sort).
    // PNG-only: SVG writes one file per top further down.
    QList<int> kept;
    for (const QVariant &v : scales) {
        const int s = qRound(v.toDouble());
        if ((s == 1 || s == 2 || s == 3) && !kept.contains(s))
            kept.append(s);
    }
    if (kept.isEmpty())
        kept.append(1);
    std::sort(kept.begin(), kept.end());

    QList<QPair<QString, QByteArray>> payloads;
    int fileAt = 0;
    for (int i = 0; i < topNodes.size(); ++i) {
        const QVariantMap node = topNodes.at(i).toMap();
        if (node.isEmpty()) {
            setLastError(tr("Nothing selected to export."));
            return false;
        }
        // SVG is resolution-independent: one file per top, scales ignored.
        if (svg) {
            QString error;
            const QString doc = SvgPaint::renderNodes({node}, &error);
            if (doc.isEmpty()) {
                setLastError(error.isEmpty() ? tr("Could not render the selection.") : error);
                return false;
            }
            payloads.append({plan.files.value(fileAt), doc.toUtf8()});
            ++fileAt;
            continue;
        }
        for (int s : kept) {
            QString error;
            const QImage img = FramePaint::renderNodes({node}, double(s), frameNo, &error);
            if (img.isNull()) {
                setLastError(error.isEmpty() ? tr("Could not render the selection.") : error);
                return false;
            }
            QByteArray bytes;
            QBuffer buf(&bytes);
            buf.open(QIODevice::WriteOnly);
            if (!img.save(&buf, "PNG")) {
                setLastError(tr("Could not encode “%1”.").arg(plan.files.value(fileAt)));
                return false;
            }
            payloads.append({plan.files.value(fileAt), bytes});
            ++fileAt;
        }
    }

    QByteArray out;
    if (plan.zip) {
        out = buildZip(payloads);
    } else {
        out = payloads.first().second;
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        setLastError(tr("Could not write “%1”.").arg(QFileInfo(path).fileName()));
        return false;
    }
    if (file.write(out) != out.size() || !file.commit()) {
        setLastError(tr("Could not write “%1”.").arg(QFileInfo(path).fileName()));
        return false;
    }
    return true;
}

#include "ComponentExporter.moc"
