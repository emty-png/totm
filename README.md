# totm

> that one tool for motion — part of the [tot](https://github.com) series (that one tool).

`totm` is a cross-platform desktop motion-graphics editor. Draw vector shapes on an infinite canvas, arrange them in layers and groups, snap with Figma-like guides, and tune properties in the design panel.

![Linux](https://img.shields.io/badge/Linux-supported-success)
![Windows](https://img.shields.io/badge/Windows-supported-success)
![macOS](https://img.shields.io/badge/macOS-supported-success)
![Qt](https://img.shields.io/badge/Qt-6.8_LTS%2B-blue)
![License](https://img.shields.io/badge/License-Apache--2.0-green)

## Features

* Infinite canvas: pan, cursor-zoom, per-tab camera memory
* Shapes: rectangle, ellipse, triangle, diamond, polygon with fill / stroke / opacity / radius
* Layers: groups, drill-in, reorder, rename, eye / lock, context menu (copy / paste / duplicate / group / arrange / delete)
* Smart snapping: edges, centers, scene, equal gaps (Alt suspends)
* Design panel with mixed-value handling
* Dark / light theme, custom frameless titlebar with tabs

## Quickstart

Requirements: CMake 3.21+, Qt 6.8+ with `Quick` module, a C++17 compiler, Ninja or Make.

```sh
cmake -B build
cmake --build build
./build/src/totm
```

Presets (see `CMakePresets.json`):

```sh
cmake --preset dev
cmake --build --preset dev
```

## Project layout

```text
src/
  main.cpp               # minimal boot, loads Totm/Main
  qml/
    Main.qml             # frameless window + TitleBar + view switch
    theme/               # AppTheme singleton
    stores/              # TabStore, ToolStore singletons
    models/document/     # Document facade + focused helpers (tree, selection, geometry…)
    views/               # home/, editor/ screen compositions
    components/          # titlebar/, window/, toolbar/, fields/, selection/, editor/
docs/                    # arch, qml-conventions, canvas-interactions
```

QML conventions live in [`docs/qml-conventions.md`](docs/qml-conventions.md). Read it before contributing.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Run before pushing:

```sh
/usr/lib/qt6/bin/qmlformat -i $(git diff --name-only | grep '\.qml$')
/usr/lib/qt6/bin/qmllint src/qml/**/*.qml
cmake --preset ci && cmake --build --preset ci
```

## License

Apache-2.0 — see [`LICENSE`](LICENSE).
