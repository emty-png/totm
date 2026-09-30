#pragma once

#include <QFont>
#include <QString>

// VariableFonts: wght-axis weight application for variable families.
//
// Most catalog families ship a single variable ([axes]) file, for which
// QFontDatabase reports only the default instance (e.g. Space Grotesk
// reads as Light/300) and plain setWeight() renders identically at any
// requested weight. Driving the wght axis explicitly interpolates for
// real (verified on the pinned Qt). Detection reads the same
// src/fonts/catalog.json the installer ships: any [axes] file marks
// the family variable. Main-thread callers today; the cache itself is
// a threadsafe function-local static.
namespace VariableFonts {
// True when the family ships a variable file in the catalog.
bool isVariableFamily(const QString &family);
// Weight with wght-axis interpolation for variable families, plain
// setWeight otherwise. Always sets the weight first (shaping and
// fallback), then the axis, so static families behave exactly as
// before and variable ones track the requested weight.
void applyTextWeight(QFont &font, const QString &family, int weight);
} // namespace VariableFonts
