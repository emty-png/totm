# qml-conventions

Follow Qt6 QML coding conventions plus these project rules.

## Layout of a file

Imports, then root with `id`, then declared props, signals, layout, visuals, inputs, functions. Blank line between groups.

```qml
import QtQuick
import Totm

Rectangle {
    id: card

    property bool active: false

    signal clicked

    width: 184
    color: AppTheme.surface
}
```

## Rules

* Colors and spacing come from `AppTheme`. No inline hex except selection accents.
* External data uses `required property`. Delegates receive explicit props, never outer ids.
* Repeater delegates use injected `index` / `modelData` directly — do not redeclare them as `required`.
* Drive one-way updates with policy callbacks (`pressPolicy`, `clickPolicy`, …) assigned in `onItemAdded`.
* Structural arrays are reassigned wholesale (`slice()` → edit → assign). Geometry mutates in place.
* Prefer static items over `Repeater` for ≤ 8 handles/guides so `qmllint` stays resolvable.
* Measure drags in global coords (`mapToGlobal`), forward whole screen pixels; snap resting values on release.
* All user strings via `qsTr()`.
* Keep files ≤ 200 lines with one job. Add a helper instead of growing a facade.

## Tooling

```sh
/usr/lib/qt6/bin/qmlformat -i <changed.qml>
/usr/lib/qt6/bin/qmllint <changed.qml>
```

`qmlformat` owns layout. Use `// qmlformat off/on` sparingly for hand-tuned pools only.
