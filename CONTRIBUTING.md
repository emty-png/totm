# Contributing to totm

Thanks for picking up `totm` (that one tool for motion, part of `tot`).

## Ground rules

* QML-only for app logic in v1. Heavy math lives in small `QtObject` helpers under `models/document/`, `canvas/`, `snap/`, `layers/`, `properties/design/` — no `.js` libraries, no new C++ unless discussed.
* One responsibility per file, aim ≤ 200 lines. `Document.qml` / `EditorCanvas.qml` are thin facades that delegate.
* Follow `docs/qml-conventions.md` and Qt6 QML coding conventions: ordered attributes with blank-line groups, `required` props for external data, explicit `id` access, no outer-id leaks into delegates (use policy callbacks wired in `onItemAdded`).
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
* Don't grow `Document.qml` / `EditorCanvas.qml` back into god files — add a helper instead.
* Don't commit `build/`, `.qt/`, `*.user`.
