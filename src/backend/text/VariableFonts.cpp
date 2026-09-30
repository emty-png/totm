#include "VariableFonts.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>

namespace VariableFonts {
namespace {

const QSet<QString> &variableFamilies() {
    // Lowercased family names shipping a variable file. Parsed once
    // from the embedded installer catalog.
    static const QSet<QString> families = [] {
        QSet<QString> out;
        QFile f(QStringLiteral(":/fonts/catalog.json"));
        if (!f.open(QIODevice::ReadOnly))
            return out;
        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
        if (err.error != QJsonParseError::NoError || !doc.isObject())
            return out;
        const QJsonArray list = doc.object().value(QStringLiteral("families")).toArray();
        for (const QJsonValue &v : list) {
            if (!v.isObject())
                continue;
            const QJsonObject o = v.toObject();
            const QString family = o.value(QStringLiteral("family")).toString().trimmed();
            if (family.isEmpty())
                continue;
            const QJsonArray files = o.value(QStringLiteral("files")).toArray();
            for (const QJsonValue &fv : files) {
                if (fv.toString().contains(QLatin1Char('['))) {
                    out.insert(family.toLower());
                    break;
                }
            }
        }
        return out;
    }();
    return families;
}

} // namespace

bool isVariableFamily(const QString &family) {
    return variableFamilies().contains(family.trimmed().toLower());
}

void applyTextWeight(QFont &font, const QString &family, int weight) {
    const int w = qBound(100, weight, 900);
    font.setWeight(QFont::Weight(w));
    if (isVariableFamily(family))
        font.setVariableAxis(QFont::Tag("wght"), float(qBound(1, weight, 1000)));
}

} // namespace VariableFonts
