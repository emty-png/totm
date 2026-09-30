#include "TextRuns.h"
#include "VariableFonts.h"

#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>
#include <QTextFragment>

namespace {

struct Run {
    int start = 0;
    int len = 0;
    bool bold = false;
    bool italic = false;
    bool underline = false;
    bool strike = false;
    QString color; // "" = unset

    bool styled() const { return bold || italic || underline || strike || !color.isEmpty(); }
    bool sameStyle(const Run &o) const {
        return bold == o.bold && italic == o.italic && underline == o.underline && strike == o.strike
            && color.compare(o.color, Qt::CaseInsensitive) == 0;
    }
};

Run runFromMap(const QVariantMap &m) {
    Run r;
    r.start = qMax(0, m.value(QStringLiteral("start"), 0).toInt());
    r.len = qMax(0, m.value(QStringLiteral("len"), 0).toInt());
    r.bold = m.value(QStringLiteral("bold"), false).toBool();
    r.italic = m.value(QStringLiteral("italic"), false).toBool();
    r.underline = m.value(QStringLiteral("underline"), false).toBool();
    r.strike = m.value(QStringLiteral("strike"), false).toBool();
    r.color = m.value(QStringLiteral("color")).toString();
    return r;
}

QVariantMap runToMap(const Run &r) {
    QVariantMap m;
    m[QStringLiteral("start")] = r.start;
    m[QStringLiteral("len")] = r.len;
    m[QStringLiteral("bold")] = r.bold;
    m[QStringLiteral("italic")] = r.italic;
    m[QStringLiteral("underline")] = r.underline;
    m[QStringLiteral("strike")] = r.strike;
    m[QStringLiteral("color")] = r.color;
    return m;
}

QList<Run> normalize(int contentLen, QList<Run> runs) {
    QList<Run> out;
    std::sort(runs.begin(), runs.end(), [](const Run &a, const Run &b) {
        return a.start < b.start || (a.start == b.start && a.len < b.len);
    });
    for (Run r : runs) {
        r.start = qBound(0, r.start, contentLen);
        r.len = qBound(0, r.len, contentLen - r.start);
        if (r.len <= 0 || !r.styled())
            continue;
        // Later runs win overlaps: trim the previous tail.
        if (!out.isEmpty()) {
            Run &prev = out.last();
            const int prevEnd = prev.start + prev.len;
            if (r.start < prevEnd) {
                if (r.start + r.len <= prevEnd) {
                    // Fully covered: drop unless styles differ, in which
                    // case split prev around r.
                    if (prev.sameStyle(r))
                        continue;
                    Run tail = prev;
                    tail.start = r.start + r.len;
                    tail.len = prevEnd - tail.start;
                    prev.len = r.start - prev.start;
                    if (prev.len <= 0) {
                        out.last() = r;
                    } else {
                        out.append(r);
                    }
                    if (tail.len > 0)
                        out.append(tail);
                    continue;
                }
                prev.len = r.start - prev.start;
                if (prev.len <= 0)
                    out.removeLast();
            }
            if (!out.isEmpty() && out.last().sameStyle(r)) {
                out.last().len = r.start + r.len - out.last().start;
                continue;
            }
        }
        out.append(r);
    }
    // Merge pass for adjacent identical styles (overlap trimming above
    // can leave mergeable neighbors around splits).
    QList<Run> merged;
    for (const Run &r : out) {
        if (!merged.isEmpty() && merged.last().sameStyle(r)
            && merged.last().start + merged.last().len == r.start) {
            merged.last().len += r.len;
        } else {
            merged.append(r);
        }
    }
    return merged;
}

QString escaped(const QString &s) {
    QString o = s;
    o.replace(QLatin1Char('&'), QStringLiteral("&amp;"));
    o.replace(QLatin1Char('<'), QStringLiteral("&lt;"));
    o.replace(QLatin1Char('>'), QStringLiteral("&gt;"));
    return o;
}

} // namespace

TextRuns *TextRuns::create(QQmlEngine *engine, QJSEngine *scriptEngine) {
    Q_UNUSED(engine);
    Q_UNUSED(scriptEngine);
    return new TextRuns();
}

TextRuns::TextRuns(QObject *parent)
    : QObject(parent) {
}

QString TextRuns::htmlFromRuns(const QString &content, const QVariantList &runs) const {
    QList<Run> rl;
    for (const QVariant &v : runs)
        rl.append(runFromMap(v.toMap()));
    rl = normalize(content.size(), rl);
    QString html;
    int pos = 0;
    auto flushPlain = [&](int from, int to) {
        if (to <= from)
            return;
        html += escaped(content.mid(from, to - from));
    };
    for (const Run &r : rl) {
        flushPlain(pos, r.start);
        QString open, close;
        if (!r.color.isEmpty()) {
            open += QStringLiteral("<font color=\"%1\">").arg(r.color);
            close = QStringLiteral("</font>") + close;
        }
        if (r.bold) {
            open += QStringLiteral("<b>");
            close = QStringLiteral("</b>") + close;
        }
        if (r.italic) {
            open += QStringLiteral("<i>");
            close = QStringLiteral("</i>") + close;
        }
        if (r.underline) {
            open += QStringLiteral("<u>");
            close = QStringLiteral("</u>") + close;
        }
        if (r.strike) {
            open += QStringLiteral("<s>");
            close = QStringLiteral("</s>") + close;
        }
        html += open + escaped(content.mid(r.start, r.len)) + close;
        pos = r.start + r.len;
    }
    flushPlain(pos, content.size());
    html.replace(QLatin1Char('\n'), QStringLiteral("<br/>"));
    return html;
}

QVariantMap TextRuns::runsFromHtml(const QString &html, const QString &defaultColor) const {
    QTextDocument doc;
    doc.setHtml(html);
    QString text;
    QList<Run> runs;
    const QColor def(defaultColor);
    for (QTextBlock block = doc.begin(); block.isValid(); block = block.next()) {
        if (!text.isEmpty())
            text += QLatin1Char('\n');
        for (QTextBlock::iterator it = block.begin(); !it.atEnd(); ++it) {
            const QTextFragment frag = it.fragment();
            if (!frag.isValid())
                continue;
            const QString ft = frag.text();
            if (ft.isEmpty())
                continue;
            // Qt splits fragments at block ends with U+2029 paragraph
            // separators, breaks <br/> with U+2028 line separators inside
            // a single block, and wraps HTML-imported inline elements in
            // bidi embeddings (U+202A-U+202E, U+2066-U+2069). Fold the
            // separators back to newlines (the block loop already emits
            // block breaks; U+2028 becomes an in-run newline) and drop
            // the zero-width embeddings (layout-neutral).
            QString clean;
            clean.reserve(ft.size());
            for (QChar ch : ft) {
                const uint u = ch.unicode();
                if (u == 0x2029)
                    continue;
                if (u == 0x2028) {
                    clean += QLatin1Char('\n');
                    continue;
                }
                if ((u >= 0x202Au && u <= 0x202Eu) || (u >= 0x2066u && u <= 0x2069u))
                    continue;
                clean += ch;
            }
            if (clean.isEmpty())
                continue;
            const int start = text.size();
            text += clean;
            const QTextCharFormat fmt = frag.charFormat();
            Run r;
            r.start = start;
            r.len = clean.size();
            r.bold = fmt.fontWeight() >= 600;
            r.italic = fmt.fontItalic();
            r.underline = fmt.fontUnderline();
            r.strike = fmt.fontStrikeOut();
            const QColor fg = fmt.foreground().color();
            if (fg.isValid() && (!def.isValid() || fg.rgba() != def.rgba()))
                r.color = fg.name();
            if (r.styled())
                runs.append(r);
        }
    }
    runs = normalize(text.size(), runs);
    QVariantMap out;
    out[QStringLiteral("text")] = text;
    QVariantList rl;
    for (const Run &r : runs)
        rl.append(runToMap(r));
    out[QStringLiteral("runs")] = rl;
    return out;
}

QVariantList TextRuns::toggleRunFlag(
    const QString &content, const QVariantList &runs, int selStart, int selEnd, const QString &flag) const {
    const int n = content.size();
    const int a = qBound(0, qMin(selStart, selEnd), n);
    const int b = qBound(0, qMax(selStart, selEnd), n);
    QVariantList untouched;
    if (b <= a || (flag != QStringLiteral("bold") && flag != QStringLiteral("italic")
            && flag != QStringLiteral("underline") && flag != QStringLiteral("strike"))) {
        for (const QVariant &v : runs)
            untouched.append(v);
        return normalizeRuns(content, untouched);
    }
    QList<Run> rl;
    for (const QVariant &v : runs)
        rl.append(runFromMap(v.toMap()));
    rl = normalize(n, rl);
    // Covered runs decide the direction: any styled-covered run clears.
    bool anySet = false;
    for (const Run &r : rl) {
        if (r.start < b && r.start + r.len > a) {
            const bool s = flag == QStringLiteral("bold") ? r.bold
                : flag == QStringLiteral("italic")        ? r.italic
                : flag == QStringLiteral("underline")     ? r.underline
                                                         : r.strike;
            if (s) {
                anySet = true;
                break;
            }
        }
    }
    const bool want = !anySet;
    // Split runs at the selection edges, then flip the covered middle.
    QList<Run> split;
    for (const Run &r : rl) {
        const int rs = r.start, re = r.start + r.len;
        if (re <= a || rs >= b) {
            split.append(r);
            continue;
        }
        if (rs < a)
            split.append(Run{rs, a - rs, r.bold, r.italic, r.underline, r.strike, r.color});
        Run mid{qMax(rs, a), qMin(re, b) - qMax(rs, a), r.bold, r.italic, r.underline, r.strike, r.color};
        if (flag == QStringLiteral("bold"))
            mid.bold = want;
        else if (flag == QStringLiteral("italic"))
            mid.italic = want;
        else if (flag == QStringLiteral("underline"))
            mid.underline = want;
        else
            mid.strike = want;
        split.append(mid);
        if (re > b)
            split.append(Run{b, re - b, r.bold, r.italic, r.underline, r.strike, r.color});
    }
    // Bare stretches inside the selection gain a fresh run when enabling.
    if (want) {
        int pos = a;
        for (const Run &r : split) {
            if (r.start + r.len <= a || r.start >= b)
                continue;
            if (r.start > pos) {
                Run fresh{pos, r.start - pos, false, false, false, false, QString()};
                if (flag == QStringLiteral("bold"))
                    fresh.bold = true;
                else if (flag == QStringLiteral("italic"))
                    fresh.italic = true;
                else if (flag == QStringLiteral("underline"))
                    fresh.underline = true;
                else
                    fresh.strike = true;
                split.append(fresh);
            }
            pos = qMax(pos, r.start + r.len);
        }
        if (pos < b) {
            Run fresh{pos, b - pos, false, false, false, false, QString()};
            if (flag == QStringLiteral("bold"))
                fresh.bold = true;
            else if (flag == QStringLiteral("italic"))
                fresh.italic = true;
            else if (flag == QStringLiteral("underline"))
                fresh.underline = true;
            else
                fresh.strike = true;
            split.append(fresh);
        }
    }
    QList<Run> norm = normalize(n, split);
    QVariantList out;
    for (const Run &r : norm)
        out.append(runToMap(r));
    return out;
}

QVariantList TextRuns::setRunColor(
    const QString &content, const QVariantList &runs, int selStart, int selEnd, const QString &color) const {
    const int n = content.size();
    const int a = qBound(0, qMin(selStart, selEnd), n);
    const int b = qBound(0, qMax(selStart, selEnd), n);
    if (b <= a)
        return normalizeRuns(content, runs);
    const QString c = QColor(color).isValid() ? QColor(color).name() : QString();
    QList<Run> rl;
    for (const QVariant &v : runs)
        rl.append(runFromMap(v.toMap()));
    rl = normalize(n, rl);
    QList<Run> split;
    for (const Run &r : rl) {
        const int rs = r.start, re = r.start + r.len;
        if (re <= a || rs >= b) {
            split.append(r);
            continue;
        }
        if (rs < a)
            split.append(Run{rs, a - rs, r.bold, r.italic, r.underline, r.strike, r.color});
        Run mid{qMax(rs, a), qMin(re, b) - qMax(rs, a), r.bold, r.italic, r.underline, r.strike, r.color};
        mid.color = c;
        split.append(mid);
        if (re > b)
            split.append(Run{b, re - b, r.bold, r.italic, r.underline, r.strike, r.color});
    }
    if (!c.isEmpty()) {
        int pos = a;
        for (const Run &r : split) {
            if (r.start + r.len <= a || r.start >= b)
                continue;
            if (r.start > pos)
                split.append(Run{pos, r.start - pos, false, false, false, false, c});
            pos = qMax(pos, r.start + r.len);
        }
        if (pos < b)
            split.append(Run{pos, b - pos, false, false, false, false, c});
    }
    QList<Run> norm = normalize(n, split);
    QVariantList out;
    for (const Run &r : norm)
        out.append(runToMap(r));
    return out;
}

QVariantList TextRuns::normalizeRuns(const QString &content, const QVariantList &runs) const {
    QList<Run> rl;
    for (const QVariant &v : runs)
        rl.append(runFromMap(v.toMap()));
    rl = normalize(content.size(), rl);
    QVariantList out;
    for (const Run &r : rl)
        out.append(runToMap(r));
    return out;
}

QFont TextRuns::textFont(const QString &family, int weight, double pixelSize, bool italic, bool underline,
    bool strike, const QString &caps, double letterSpacing) const {
    // Display font for QML text items: variable families interpolate
    // the wght axis (plain setWeight renders their default instance at
    // every weight), static families behave exactly as before.
    QFont font(family.isEmpty() ? QStringLiteral("Inter") : family);
    font.setPixelSize(qMax(1, qRound(pixelSize)));
    VariableFonts::applyTextWeight(font, font.family(), weight);
    font.setItalic(italic);
    font.setUnderline(underline);
    font.setStrikeOut(strike);
    if (caps == QStringLiteral("upper"))
        font.setCapitalization(QFont::AllUppercase);
    else if (caps == QLatin1String("lower"))
        font.setCapitalization(QFont::AllLowercase);
    font.setLetterSpacing(QFont::AbsoluteSpacing, letterSpacing);
    return font;
}
