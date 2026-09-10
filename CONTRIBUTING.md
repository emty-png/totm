# Contributing to totm

Thanks for picking up `totm` (that one tool for motion, part of `tot`).

## Project layout

```text
src/
  main.cpp               # minimal boot, loads Totm/Main
  backend/
    library/             # LibraryStore (library.json, QSaveFile, lockfile)
    settings/            # SettingsStore (theme + window state, QSettings)
  qml/
    Main.qml             # frameless window + TitleBar + view switch, restores window state
    theme/               # AppTheme singleton (only hex colors live here)
    stores/              # TabState, ToolState singletons
    models/              # Document facade + DocNode
    models/document/     # focused helpers (tree, selection, history, anim, geometry…)
    views/               # home/, editor/ screen compositions
    components/
      icons/             # AppIcon global glyph set
      titlebar/          # TitleBar, tabs, controls (+ mac traffic lights)
      window/            # frameless resize handles
      toolbar/           # floating canvas toolbar
      fields/            # NumberField, HexField, RenameField
      selection/         # marquee selection
      editor/            # canvas/, snap/, layers/, properties/, shapes/, timeline/
```

## Ground rules

* QML for UI + app logic in v1. Heavy math lives in small `QtObject` helpers under `models/document/`, `canvas/`, `snap/`, `layers/`, `properties/` — no `.js` libraries. All storing/persistence lives in the C++ backend (`backend/library/`, `backend/settings/`) — no QML-side file IO, no new C++ stores unless discussed.
* One responsibility per file, aim ≤ 200 lines. `Document.qml` / `EditorCanvas.qml` are thin facades that delegate.
* Follow Qt6 QML coding conventions: ordered attributes with blank-line groups, `required` props for external data, explicit `id` access, no outer-id leaks into delegates (use policy callbacks wired in `onItemAdded`).
* Custom clips reuse the preset pipeline: new types get `presetIds` + `defaultsFor` + `normalizeOptions` in `DocAnimPresets`, frame math in `AnimSample.presetOverlay` (+ writeback in `applySample`, capture in `DocAnim.captureBase`), and from-to editors under `properties/` grouped like the gallery (Transform/Style/Other/Path).
* Human comments only: explain *why* and contracts (units, invariants). Delete what-the-code-says and lint war stories.

## Workflow

1. Fork, branch from `main`: `feat/<short>`, `fix/<short>`.
2. Format + lint changed QML:
   ```sh
   /usr/lib/qt6/bin/qmlformat -i <files>
   /usr/lib/qt6/bin/qmllint <files>
   ```
3. Build: `cmake --preset dev && cmake --build --preset dev`, smoke-test (new tab, draw, move/resize/snap, group/drill, layers reorder/rename, theme toggle).
4. Commit with clear scope (`feat(canvas): …`, `fix(layers): …`). Keep public `Document` API compatible; removing a shim needs a note in the PR.
5. Open a PR against `main` with what changed, how you tested, screenshots for visual changes.

## What not to do

* Don't add hex colors outside `AppTheme` (except `selection`/`snapGuide` accents).
* Don't persist from QML — all storing goes through the backend (`LibraryStore`, `SettingsStore`).
* Don't grow `Document.qml` / `EditorCanvas.qml` back into god files — add a helper instead.
* Don't commit `build/`, `.qt/`, `*.user`.
