#include "ScriptRunner.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJSValue>
#include <QProcess>
#include <QRegularExpression>
#include <QStringList>
#include <QTemporaryFile>
#include <QUrl>
#include <QVariant>
#include <cmath>

namespace {

bool isCreateHandle(int handle)
{
    return handle >= 0 && handle < ScriptBridge::kFindBit;
}

} // namespace

ScriptBridge::ScriptBridge(QJSEngine *engine, const QVariantMap &pickResults, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
    , m_pickResults(pickResults)
{
}

void ScriptBridge::fail(const QString &message)
{
    if (m_engine)
        m_engine->throwError(message);
}

double ScriptBridge::optNum(const QVariantMap &opts, const char *key, double fallback) const
{
    bool ok = false;
    const double v = opts.value(QString::fromLatin1(key)).toDouble(&ok);
    return ok ? v : fallback;
}

int ScriptBridge::addShape(const QString &kind, const QVariantMap &opts)
{
    if (m_creates.size() >= kMaxCreates) {
        fail(QStringLiteral("too many shapes (max %1)").arg(kMaxCreates));
        return -1;
    }
    const QString name = opts.value(QStringLiteral("name")).toString();
    if (name.size() > kMaxNameLen) {
        fail(QStringLiteral("name too long (max %1 characters)").arg(kMaxNameLen));
        return -1;
    }
    // Absent fills fall back per kind (text reads black like the HTML
    // path); a present-but-empty fill is a typo worth throwing on.
    QString fill = opts.value(QStringLiteral("fill")).toString().trimmed();
    if (opts.contains(QStringLiteral("fill")) && fill.isEmpty()) {
        fail(QStringLiteral("fill must be a non-empty color string"));
        return -1;
    }
    if (fill.size() > kMaxFillLen) {
        fail(QStringLiteral("fill too long (max %1 characters)").arg(kMaxFillLen));
        return -1;
    }
    if (fill.isEmpty())
        fill = (kind == QStringLiteral("text")) ? QStringLiteral("#000000") : QStringLiteral("#d9d9d9");
    QVariantMap el;
    el[QStringLiteral("kind")] = kind;
    el[QStringLiteral("x")] = qRound(optNum(opts, "x", 0.0));
    el[QStringLiteral("y")] = qRound(optNum(opts, "y", 0.0));
    el[QStringLiteral("w")] = qMax(1, qRound(optNum(opts, "w", 100.0)));
    el[QStringLiteral("h")] = qMax(1, qRound(optNum(opts, "h", 100.0)));
    el[QStringLiteral("fill")] = fill;
    el[QStringLiteral("name")] = opts.value(QStringLiteral("name")).toString();
    el[QStringLiteral("rotation")] = optNum(opts, "rotation", optNum(opts, "rotate", 0.0));
    // Style parity with the CSS subset: captured raw here, validated
    // at apply time in DocScript._createElement (same warnings path).
    // Absent keys stay absent so defaults apply untouched.
    if (opts.contains(QStringLiteral("opacity")))
        el[QStringLiteral("opacity")] = optNum(opts, "opacity", 1.0);
    if (opts.contains(QStringLiteral("radius")))
        el[QStringLiteral("radius")] = optNum(opts, "radius", 0.0);
    if (opts.contains(QStringLiteral("fillOpacity")))
        el[QStringLiteral("fillOpacity")] = optNum(opts, "fillOpacity", 1.0);
    if (opts.contains(QStringLiteral("stroke")))
        el[QStringLiteral("stroke")] = opts.value(QStringLiteral("stroke")).toString();
    if (opts.contains(QStringLiteral("strokeWidth")))
        el[QStringLiteral("strokeWidth")] = optNum(opts, "strokeWidth", 1.0);
    if (opts.contains(QStringLiteral("strokePosition")))
        el[QStringLiteral("strokePosition")] = opts.value(QStringLiteral("strokePosition")).toString();
    if (opts.contains(QStringLiteral("strokeOpacity")))
        el[QStringLiteral("strokeOpacity")] = optNum(opts, "strokeOpacity", 1.0);
    // Effects parity with CSS: raw values ride through (number,
    // string, or {...} map); validated at apply time in QML.
    for (const QString &key : {QStringLiteral("layerBlur"), QStringLiteral("backgroundBlur"), QStringLiteral("grain"), QStringLiteral("shadow"), QStringLiteral("glow"), QStringLiteral("shader"), QStringLiteral("shaderMode")}) {
        if (opts.contains(key))
            el[key] = opts.value(key);
    }
    // Class list for forward-compat with the CSS cascade (JS creates
    // keep their own style; the sheet stays HTML-only for now).
    // Accepts `classes` (string or array), `class` or `className`.
    {
        QStringList classes;
        const QVariant vClasses = opts.value(QStringLiteral("classes"));
        const QVariant vClass = opts.value(QStringLiteral("class"));
        const QVariant vClassName = opts.value(QStringLiteral("className"));
        if (vClasses.typeId() == QMetaType::QString)
            classes = vClasses.toString().split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
        else if (vClasses.canConvert<QVariantList>()) {
            const QVariantList classList = vClasses.toList();
            if (classList.size() > kMaxClasses) {
                fail(QStringLiteral("too many classes (max %1)").arg(kMaxClasses));
                return -1;
            }
            for (const QVariant &c : classList) {
                const QString s = c.toString().trimmed();
                if (!s.isEmpty())
                    classes.append(s.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts));
            }
        }
        if (classes.isEmpty() && vClass.typeId() == QMetaType::QString)
            classes = vClass.toString().split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
        if (classes.isEmpty() && vClassName.typeId() == QMetaType::QString)
            classes = vClassName.toString().split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
        if (classes.size() > kMaxClasses) {
            fail(QStringLiteral("too many classes (max %1)").arg(kMaxClasses));
            return -1;
        }
        for (const QString &c : classes) {
            if (c.size() > kMaxClassLen) {
                fail(QStringLiteral("class name too long (max %1 characters)").arg(kMaxClassLen));
                return -1;
            }
        }
        if (!classes.isEmpty())
            el[QStringLiteral("classes")] = classes;
    }
    // Media blob rides the create so QML apply can tag the node and
    // validate library membership (missing = hard error there).
    if (kind == QStringLiteral("image") || kind == QStringLiteral("video"))
        el[QStringLiteral("blob")] = opts.value(QStringLiteral("blob")).toString();
    if (kind == QStringLiteral("text")) {
        const QString content = opts.value(QStringLiteral("content")).toString();
        if (content.size() > kMaxTextLen) {
            fail(QStringLiteral("text content too long (max %1 characters)").arg(kMaxTextLen));
            return -1;
        }
        el[QStringLiteral("content")] = content;
        const double fs = optNum(opts, "fontSize", 16.0);
        el[QStringLiteral("fontSize")] = std::isfinite(fs) ? qBound(1.0, fs, 1000.0) : 16.0;
        if (opts.contains(QStringLiteral("fontFamily")))
            el[QStringLiteral("fontFamily")] = opts.value(QStringLiteral("fontFamily")).toString();
        if (opts.contains(QStringLiteral("fontWeight")))
            el[QStringLiteral("fontWeight")] = opts.value(QStringLiteral("fontWeight")).toString();
        if (opts.contains(QStringLiteral("fontStyle")))
            el[QStringLiteral("fontStyle")] = opts.value(QStringLiteral("fontStyle")).toString();
        if (opts.contains(QStringLiteral("textDecoration")))
            el[QStringLiteral("textDecoration")] = opts.value(QStringLiteral("textDecoration")).toString();
        if (opts.contains(QStringLiteral("textTransform")))
            el[QStringLiteral("textTransform")] = opts.value(QStringLiteral("textTransform")).toString();
        if (opts.contains(QStringLiteral("textAlign")))
            el[QStringLiteral("textAlign")] = opts.value(QStringLiteral("textAlign")).toString();
    }
    m_creates.append(el);
    return m_creates.size() - 1;
}

int ScriptBridge::rect(const QVariantMap &opts)
{
    return addShape(QStringLiteral("rectangle"), opts);
}

int ScriptBridge::ellipse(const QVariantMap &opts)
{
    return addShape(QStringLiteral("ellipse"), opts);
}

int ScriptBridge::triangle(const QVariantMap &opts)
{
    return addShape(QStringLiteral("triangle"), opts);
}

int ScriptBridge::star(const QVariantMap &opts)
{
    return addShape(QStringLiteral("star"), opts);
}

int ScriptBridge::text(const QVariantMap &opts)
{
    return addShape(QStringLiteral("text"), opts);
}

int ScriptBridge::pen(const QVariantMap &opts)
{
    // Points accept [{x,y}] or [[x,y]]; closed is a bool flag.
    // Normalized here so QML apply shares one pathData shape.
    // Capped up front: iterating a 1M-point array would spike the
    // helper before the creates cap ever trips.
    const QVariantList raw = opts.value(QStringLiteral("points")).toList();
    if (raw.size() > kMaxPenPoints) {
        fail(QStringLiteral("too many pen points (max %1)").arg(kMaxPenPoints));
        return -1;
    }
    QVariantList pts;
    for (const QVariant &p : raw) {
        double px = 0.0, py = 0.0;
        bool ok = false;
        if (p.typeId() == QMetaType::QVariantMap || p.canConvert<QVariantMap>()) {
            const QVariantMap m = p.toMap();
            bool ox = false, oy = false;
            px = m.value(QStringLiteral("x")).toDouble(&ox);
            py = m.value(QStringLiteral("y")).toDouble(&oy);
            ok = ox && oy;
        } else if (p.canConvert<QVariantList>()) {
            const QVariantList pair = p.toList();
            if (pair.size() >= 2) {
                bool ox = false, oy = false;
                px = pair.at(0).toDouble(&ox);
                py = pair.at(1).toDouble(&oy);
                ok = ox && oy;
            }
        }
        if (!ok || !std::isfinite(px) || !std::isfinite(py)) {
            fail(QStringLiteral("pen points must be [{x,y}] or [[x,y]] numbers"));
            return -1;
        }
        QVariantMap pt;
        pt[QStringLiteral("x")] = px;
        pt[QStringLiteral("y")] = py;
        pts.append(pt);
    }
    if (pts.size() < 2) {
        fail(QStringLiteral("pen needs at least 2 points"));
        return -1;
    }
    const int handle = addShape(QStringLiteral("pen"), opts);
    if (handle < 0 || handle >= m_creates.size())
        return -1;
    QVariantMap el = m_creates.at(handle).toMap();
    el[QStringLiteral("points")] = pts;
    el[QStringLiteral("closed")] = opts.value(QStringLiteral("closed")).toBool();
    m_creates[handle] = el;
    return handle;
}

int ScriptBridge::image(const QString &blob, const QVariantMap &opts)
{
    if (blob.trimmed().isEmpty()) {
        fail(QStringLiteral("image blob name must be a non-empty string"));
        return -1;
    }
    if (blob.trimmed().size() > kMaxBlobLen) {
        fail(QStringLiteral("blob name too long (max %1 characters)").arg(kMaxBlobLen));
        return -1;
    }
    return addMedia(QStringLiteral("image"), blob.trimmed(), opts);
}

int ScriptBridge::video(const QString &blob, const QVariantMap &opts)
{
    if (blob.trimmed().isEmpty()) {
        fail(QStringLiteral("video blob name must be a non-empty string"));
        return -1;
    }
    if (blob.trimmed().size() > kMaxBlobLen) {
        fail(QStringLiteral("blob name too long (max %1 characters)").arg(kMaxBlobLen));
        return -1;
    }
    return addMedia(QStringLiteral("video"), blob.trimmed(), opts);
}

int ScriptBridge::addMedia(const QString &kind, const QString &blob, const QVariantMap &opts)
{
    QVariantMap full = opts;
    full[QStringLiteral("blob")] = blob;
    if (!full.contains(QStringLiteral("fill")))
        full[QStringLiteral("fill")] = (kind == QStringLiteral("video")) ? QStringLiteral("#000000") : QStringLiteral("#d9d9d9");
    return addShape(kind, full);
}

int ScriptBridge::audio(const QString &blob, const QVariantMap &opts)
{
    if (blob.trimmed().isEmpty()) {
        fail(QStringLiteral("audio blob name must be a non-empty string"));
        return -1;
    }
    if (blob.trimmed().size() > kMaxBlobLen) {
        fail(QStringLiteral("blob name too long (max %1 characters)").arg(kMaxBlobLen));
        return -1;
    }
    if (m_audio.size() >= kMaxAudio) {
        fail(QStringLiteral("too many audio clips (max %1)").arg(kMaxAudio));
        return kNoHandle;
    }
    QVariantMap op;
    op[QStringLiteral("blob")] = blob.trimmed();
    op[QStringLiteral("t0")] = optNum(opts, "t0", 0.0);
    op[QStringLiteral("duration")] = optNum(opts, "duration", 0.0);
    m_audio.append(op);
    return kNoHandle;
}

int ScriptBridge::pickMedia(const QString &kind, const QVariantMap &opts)
{
    if (m_picks.size() >= kMaxPicks) {
        fail(QStringLiteral("too many file picks (max %1)").arg(kMaxPicks));
        return (kind == QStringLiteral("audio")) ? kNoHandle : -1;
    }
    const QString preloaded = m_pickResults.value(QString::number(m_pickCursor)).toString().trimmed();
    const int cursor = m_pickCursor++;
    QVariantMap entry;
    entry[QStringLiteral("kind")] = kind;
    entry[QStringLiteral("resolved")] = !preloaded.isEmpty();
    m_picks.append(entry);
    if (!preloaded.isEmpty()) {
        // Replay with a chosen file: behave exactly like the direct call.
        if (kind == QStringLiteral("audio")) {
            if (m_audio.size() >= kMaxAudio) {
                fail(QStringLiteral("too many audio clips (max %1)").arg(kMaxAudio));
                return kNoHandle;
            }
            QVariantMap op;
            op[QStringLiteral("blob")] = preloaded;
            op[QStringLiteral("t0")] = optNum(opts, "t0", 0.0);
            op[QStringLiteral("duration")] = optNum(opts, "duration", 0.0);
            m_audio.append(op);
            return kNoHandle;
        }
        return addMedia(kind, preloaded, opts);
    }
    if (kind == QStringLiteral("audio"))
        return kNoHandle;
    // Placeholder create keeps handles stable across the replay; the
    // empty blob never applies (phase 1 never touches the scene).
    QVariantMap full = opts;
    full[QStringLiteral("blob")] = QString();
    if (!full.contains(QStringLiteral("fill")))
        full[QStringLiteral("fill")] = QStringLiteral("#d9d9d9");
    return addShape(kind, full);
}

int ScriptBridge::pickImage(const QVariantMap &opts)
{
    return pickMedia(QStringLiteral("image"), opts);
}

int ScriptBridge::pickVideo(const QVariantMap &opts)
{
    return pickMedia(QStringLiteral("video"), opts);
}

int ScriptBridge::pickAudio(const QVariantMap &opts)
{
    return pickMedia(QStringLiteral("audio"), opts);
}

int ScriptBridge::group(const QString &name, const QVariantList &handles)
{
    if (m_groups.size() >= kMaxGroups) {
        fail(QStringLiteral("too many groups (max %1)").arg(kMaxGroups));
        return -1;
    }
    if (handles.isEmpty()) {
        fail(QStringLiteral("group needs at least one shape handle"));
        return -1;
    }
    if (handles.size() > kMaxGroupMembers) {
        fail(QStringLiteral("too many group members (max %1)").arg(kMaxGroupMembers));
        return -1;
    }
    QVariantList members;
    for (const QVariant &h : handles) {
        bool ok = false;
        const int idx = h.toInt(&ok);
        if (!ok || !isCreateHandle(idx) || idx >= m_creates.size()) {
            fail(QStringLiteral("group members must be shape handles from totm.rect/... (find results cannot be grouped)"));
            return -1;
        }
        if (m_grouped.contains(idx)) {
            fail(QStringLiteral("shape handle is already grouped"));
            return -1;
        }
        // Claim immediately: a handle listed twice must trip the
        // check above on its second occurrence.
        m_grouped.insert(idx);
        members.append(idx);
    }
    QVariantMap op;
    op[QStringLiteral("name")] = name.trimmed().isEmpty() ? QStringLiteral("Group") : name.trimmed();
    op[QStringLiteral("members")] = members;
    m_groups.append(op);
    return m_groups.size() - 1;
}

int ScriptBridge::find(const QString &name)
{
    if (name.trimmed().isEmpty()) {
        fail(QStringLiteral("find needs a non-empty node name"));
        return -1;
    }
    if (name.trimmed().size() > kMaxNameLen) {
        fail(QStringLiteral("name too long (max %1 characters)").arg(kMaxNameLen));
        return -1;
    }
    if (m_finds.size() >= kMaxFinds) {
        fail(QStringLiteral("too many finds (max %1)").arg(kMaxFinds));
        return -1;
    }
    m_finds.append(name.trimmed());
    return kFindBit + (m_finds.size() - 1);
}

void ScriptBridge::set(int handle, const QVariantMap &props)
{
    if (m_sets.size() >= kMaxSets) {
        fail(QStringLiteral("too many set calls (max %1)").arg(kMaxSets));
        return;
    }
    const bool known = (isCreateHandle(handle) && handle < m_creates.size())
        || (!isCreateHandle(handle) && (handle - kFindBit) >= 0 && (handle - kFindBit) < m_finds.size());
    if (!known) {
        fail(QStringLiteral("set needs a handle from totm.rect/... or totm.find"));
        return;
    }
    static const char *keys[] = {"fill", "opacity", "radius", "fillOpacity", "x", "y", "w", "h", "rotation", "rotate", "name"};
    QVariantMap kept;
    for (const char *k : keys) {
        const QString key = QString::fromLatin1(k);
        if (props.contains(key))
            kept[key] = props.value(key);
    }
    if (kept.isEmpty()) {
        fail(QStringLiteral("set needs at least one of: fill, opacity, radius, x, y, w, h, rotation, name"));
        return;
    }
    if (kept.contains(QStringLiteral("name"))
        && kept.value(QStringLiteral("name")).toString().size() > kMaxNameLen) {
        fail(QStringLiteral("name too long (max %1 characters)").arg(kMaxNameLen));
        return;
    }
    if (kept.contains(QStringLiteral("fill"))
        && kept.value(QStringLiteral("fill")).toString().size() > kMaxFillLen) {
        fail(QStringLiteral("fill too long (max %1 characters)").arg(kMaxFillLen));
        return;
    }
    QVariantMap op;
    op[QStringLiteral("target")] = handle;
    op[QStringLiteral("props")] = kept;
    m_sets.append(op);
}

void ScriptBridge::remove(int handle)
{
    if (m_removes.size() >= kMaxRemoves) {
        fail(QStringLiteral("too many remove calls (max %1)").arg(kMaxRemoves));
        return;
    }
    const bool known = (isCreateHandle(handle) && handle < m_creates.size())
        || (!isCreateHandle(handle) && (handle - kFindBit) >= 0 && (handle - kFindBit) < m_finds.size());
    if (!known) {
        fail(QStringLiteral("remove needs a handle from totm.rect/... or totm.find"));
        return;
    }
    m_removes.append(handle);
}

void ScriptBridge::animate(int handle, const QString &preset, const QVariantMap &opts){
    if (m_animates.size() >= kMaxAnimates) {
        fail(QStringLiteral("too many animations (max %1)").arg(kMaxAnimates));
        return;
    }
    const bool known = (isCreateHandle(handle) && handle < m_creates.size())
        || (!isCreateHandle(handle) && (handle - kFindBit) >= 0 && (handle - kFindBit) < m_finds.size());
    if (!known) {
        fail(QStringLiteral("animate needs a handle from totm.rect/... or totm.find"));
        return;
    }
    if (preset.trimmed().isEmpty()) {
        fail(QStringLiteral("animate needs a preset id string"));
        return;
    }
    if (preset.trimmed().size() > kMaxPresetLen) {
        fail(QStringLiteral("preset id too long (max %1 characters)").arg(kMaxPresetLen));
        return;
    }
    const double duration = optNum(opts, "duration", 1.0);
    if (!std::isfinite(duration) || duration <= 0.0) {
        fail(QStringLiteral("duration must be a positive number of seconds"));
        return;
    }
    // One call must not smuggle megabytes (e.g. a giant options array):
    // the whole op list has to fit the parent's output budget.
    const QVariantMap options = opts.value(QStringLiteral("options"), QVariantMap()).toMap();
    const QVariantMap easing = opts.value(QStringLiteral("easing"), QVariantMap()).toMap();
    if (QJsonDocument::fromVariant(options).toJson(QJsonDocument::Compact).size()
            + QJsonDocument::fromVariant(easing).toJson(QJsonDocument::Compact).size()
        > kMaxAnimateOptsBytes) {
        fail(QStringLiteral("animation options too large (max %1 bytes)").arg(kMaxAnimateOptsBytes));
        return;
    }
    QVariantMap op;
    op[QStringLiteral("target")] = handle;
    op[QStringLiteral("preset")] = preset.trimmed();
    op[QStringLiteral("t0")] = optNum(opts, "t0", -1.0);
    op[QStringLiteral("duration")] = duration;
    op[QStringLiteral("mode")] = opts.value(QStringLiteral("mode")).toString().trimmed().left(kMaxPresetLen);
    op[QStringLiteral("options")] = options;
    op[QStringLiteral("easing")] = easing;
    m_animates.append(op);
}

void ScriptBridge::setDuration(double seconds)
{
    if (!std::isfinite(seconds) || seconds <= 0.0) {
        fail(QStringLiteral("setDuration needs a positive number of seconds"));
        return;
    }
    m_duration = seconds;
}

QVariantMap ScriptBridge::takeResult() const
{
    QVariantMap ops;
    ops[QStringLiteral("creates")] = m_creates;
    ops[QStringLiteral("groups")] = m_groups;
    ops[QStringLiteral("animates")] = m_animates;
    ops[QStringLiteral("finds")] = m_finds;
    ops[QStringLiteral("picks")] = m_picks;
    ops[QStringLiteral("audio")] = m_audio;
    ops[QStringLiteral("sets")] = m_sets;
    ops[QStringLiteral("removes")] = m_removes;
    ops[QStringLiteral("duration")] = m_duration;
    QVariantMap result;
    result[QStringLiteral("ok")] = true;
    result[QStringLiteral("ops")] = ops;
    return result;
}

QVariantMap evaluateScriptSource(const QString &code, const QVariantMap &pickResults)
{
    // Bound the evaluation before the engine ever sees it: parsing
    // megabytes of source spikes the helper, and the parent must parse
    // the resulting JSON on the main thread. Oversize input fails fast
    // with a readable error instead of OOMing either process.
    if (code.size() > ScriptBridge::kMaxSourceChars) {
        QVariantMap tooBig;
        tooBig[QStringLiteral("ok")] = false;
        tooBig[QStringLiteral("error")] = QStringLiteral("script too large (max %1 characters)")
                                              .arg(ScriptBridge::kMaxSourceChars);
        tooBig[QStringLiteral("line")] = 0;
        return tooBig;
    }
    // Heap engine, explicitly deleted before the stack bridge dies:
    // engine teardown finalizes the totm wrapper, which must not
    // outlive the bridge object it points at. newQObject defaults to
    // JavaScriptOwnership, so claim CppOwnership or the GC deletes the
    // stack bridge on teardown (heap corruption).
    auto *engine = new QJSEngine;
    ScriptBridge bridge(engine, pickResults);
    QJSEngine::setObjectOwnership(&bridge, QJSEngine::CppOwnership);
    engine->globalObject().setProperty(QStringLiteral("totm"), engine->newQObject(&bridge));
    const QJSValue ret = engine->evaluate(code, QStringLiteral("script.js"), 1);
    QVariantMap result;
    if (ret.isError()) {
        const QString message = ret.property(QStringLiteral("message")).toString();
        result[QStringLiteral("ok")] = false;
        result[QStringLiteral("error")] = message.isEmpty() ? ret.toString() : message;
        result[QStringLiteral("line")] = ret.property(QStringLiteral("lineNumber")).toInt();
    } else {
        result = bridge.takeResult();
        // Backstop for combinations the per-call caps miss (e.g. 2000
        // creates each with a max-length text blob): the parent parses
        // this JSON on the main thread, so it must stay small.
        if (QJsonDocument::fromVariant(result).toJson(QJsonDocument::Compact).size()
            > ScriptBridge::kMaxOutputBytes) {
            result.clear();
            result[QStringLiteral("ok")] = false;
            result[QStringLiteral("error")] = QStringLiteral("script output too large (max %1 bytes)")
                                                  .arg(ScriptBridge::kMaxOutputBytes);
            result[QStringLiteral("line")] = 0;
        }
    }
    delete engine;
    return result;
}

ScriptRunner *ScriptRunner::create(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(scriptEngine);
    auto *runner = new ScriptRunner(engine);
    QJSEngine::setObjectOwnership(runner, QJSEngine::CppOwnership);
    return runner;
}

ScriptRunner::ScriptRunner(QObject *parent)
    : QObject(parent)
{
}

ScriptRunner::~ScriptRunner()
{
    for (auto it = m_active.begin(); it != m_active.end(); ++it) {
        if (it->process) {
            it->process->blockSignals(true);
            it->process->kill();
            it->process->waitForFinished(2000);
            delete it->process;
        }
        delete it->source;
        delete it->picks;
    }
    m_active.clear();
}

int ScriptRunner::run(const QString &code, const QVariantMap &pickResults)
{
    const int runId = m_nextId++;
    // Fail fast without spawning a helper: staging + evaluating
    // megabytes would spike both processes for nothing.
    if (code.size() > ScriptBridge::kMaxSourceChars || pickResults.size() > ScriptBridge::kMaxPicks) {
        QVariantMap result;
        result[QStringLiteral("ok")] = false;
        result[QStringLiteral("error")] = code.size() > ScriptBridge::kMaxSourceChars
            ? tr("Script too large (max %1 characters)").arg(ScriptBridge::kMaxSourceChars)
            : tr("Too many file picks (max %1)").arg(ScriptBridge::kMaxPicks);
        result[QStringLiteral("line")] = 0;
        // Resolve async like every other path so callers share one flow.
        // (Not tracked in m_active: abort() before delivery is a no-op
        // and the queued emit still resolves exactly once.)
        QMetaObject::invokeMethod(this, [this, runId, result]() { emit finished(runId, result); },
            Qt::QueuedConnection);
        return runId;
    }
    auto *source = new QTemporaryFile(this);
    source->setFileTemplate(QDir::tempPath() + QStringLiteral("/totm-script-XXXXXX.js"));
    auto *picks = new QTemporaryFile(this);
    picks->setFileTemplate(QDir::tempPath() + QStringLiteral("/totm-picks-XXXXXX.json"));
    if (!source->open() || !picks->open()) {
        delete source;
        delete picks;
        QVariantMap result;
        result[QStringLiteral("ok")] = false;
        result[QStringLiteral("error")] = tr("Could not stage the script for evaluation");
        result[QStringLiteral("line")] = 0;
        // Resolve async like every other path so callers share one flow.
        // (Not tracked in m_active: abort() before delivery is a no-op
        // and the queued emit still resolves exactly once.)
        QMetaObject::invokeMethod(this, [this, runId, result]() { emit finished(runId, result); },
            Qt::QueuedConnection);
        return runId;
    }
    source->write(code.toUtf8());
    source->flush();
    picks->write(QJsonDocument::fromVariant(pickResults).toJson(QJsonDocument::Compact));
    picks->flush();
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, runId]() { onProcessFinished(runId); });
    m_active.insert(runId, Active{process, source, picks});
    process->start(QCoreApplication::applicationFilePath(),
        {QStringLiteral("--script-eval"), source->fileName(),
            QStringLiteral("--picks"), picks->fileName()});
    return runId;
}

void ScriptRunner::onProcessFinished(int runId)
{
    auto it = m_active.find(runId);
    if (it == m_active.end())
        return;
    QProcess *process = it->process;
    QTemporaryFile *source = it->source;
    QTemporaryFile *picks = it->picks;
    m_active.erase(it);
    QVariantMap result;
    if (!process || process->exitStatus() != QProcess::NormalExit || process->exitCode() != 0) {
        result[QStringLiteral("ok")] = false;
        result[QStringLiteral("error")] = tr("Script process exited unexpectedly");
        result[QStringLiteral("line")] = 0;
    } else {
        bool parsed = false;
        const QByteArray out = process->readAllStandardOutput();
        // The helper is capped, but never parse unbounded IPC on the
        // main thread: a compromised or future helper must not OOM us.
        if (out.size() <= ScriptBridge::kMaxOutputBytes) {
            const QVariantMap decoded = QJsonDocument::fromJson(out).toVariant().toMap();
            if (!decoded.isEmpty()) {
                result = decoded;
                parsed = true;
            }
        }
        if (!parsed) {
            result[QStringLiteral("ok")] = false;
            result[QStringLiteral("error")] = out.size() > ScriptBridge::kMaxOutputBytes
                ? tr("Script output too large (max %1 bytes)").arg(ScriptBridge::kMaxOutputBytes)
                : tr("Script process returned invalid output");
            result[QStringLiteral("line")] = 0;
        }
    }
    delete process;
    delete source;
    delete picks;
    emit finished(runId, result);
}

void ScriptRunner::abort(int runId)
{
    auto it = m_active.find(runId);
    if (it == m_active.end())
        return;
    if (it->process) {
        // SIGKILL always lands (unlike thread termination, which cannot
        // stop JIT-spun engine evaluation). The helper touches only its
        // own engine plus the op list, so nothing shared needs cleanup.
        it->process->blockSignals(true);
        it->process->kill();
        it->process->waitForFinished(2000);
        delete it->process;
    }
    delete it->source;
    delete it->picks;
    m_active.erase(it);
    finishAborted(runId);
}

void ScriptRunner::finishAborted(int runId)
{
    QVariantMap result;
    result[QStringLiteral("ok")] = false;
    result[QStringLiteral("aborted")] = true;
    emit finished(runId, result);
}

bool ScriptRunner::openGuide()
{
    // Candidates mirror PluginStore::openGuide (installed doc dir
    // first, then the dev-checkout file).
    const QString exeDir = QCoreApplication::applicationDirPath();
    const QStringList candidates = {
        exeDir + QStringLiteral("/../share/doc/totm/DEV_SCRIPT.html"),
        exeDir + QStringLiteral("/../Resources/DEV_SCRIPT.html"),
        exeDir + QStringLiteral("/../../../src/docs/DEV_SCRIPT.html"),
    };
    for (const QString &candidate : candidates) {
        const QString path = QDir::cleanPath(candidate);
        if (QFile::exists(path))
            return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    }
    return false;
}
