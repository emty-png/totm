# arch

`totm` is Qt6 Quick, QML-first. `src/main.cpp` only boots `Totm/Main`.

* `theme/` — `AppTheme` singleton, the only place with hex colors.
* `stores/` — `TabStore` (tabs + per-tab `Document` + clipboard), `ToolStore` (active tool).
* `models/document/` — one `Document` per tab. Thin `Document.qml` facade owns state (`rootChildren`, `leafList`, `rev`/`structRev`, `drillPath`, camera); helpers own logic:
  `DocTree` (navigation), `DocEffective` (visible/locked inheritance),
  `DocLayersModel` (row list, gaps, z), `DocSelection` (select/range/flags/rename),
  `DocDrill` (active container, press resolve), `DocClipboard` (make/snapshot/copy/paste/duplicate/delete),
  `DocGroup`, `DocReorder`, `DocGeometry` (bbox, move/scale, props).
  Geometry mutates in place; structure reassigns arrays wholesale so `var` bindings fire.
  `rev` bumps every mutation, `structRev` only on tree shape (layers list binds that).
* `views/` — screen compositions (`home/`, `editor/`). No logic.
* `components/` — reusable UI: `titlebar/`, `window/`, `toolbar/`, `fields/`, `selection/`, `editor/canvas/`, `editor/snap/`, `editor/layers/`, `editor/properties/design/`, `editor/shapes/`.
* Canvas input flows one way: `ShapeItem` / handles report press-move-release → canvas policies → `Document` mutates → `rev` re-renders. Delegates never reach into outer ids; parents wire policy callbacks in `onItemAdded`.
