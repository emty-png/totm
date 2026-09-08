# totm

`totm` stands for "That one tool for motion" and is a part of an open-source app series named `tot` which stads for "That one tool".

`totm` is a cross-platform desktop motion-graphics editor. Draw vector shapes on an canvas, arrange them in layers and groups, snap with guides, tune properties in the design panel, group components to manage large designs and now even animate them with animations.

I am trying to make apps that are better, smoother, offline and easy for new users to work with and just better overall experience. I encorage you to report all issues you find as i can't test it on every single platform solo. I need your help to improve this app. You can also help by recommending features as i am not the most creative person, if you couldn't tell. 

I was originally making this app in tauri v2 but i crashed out in the middle of making it (i couldn't get it to work properly in front-end and didn't wanna touch rust) and switched to linux (cachy). I know that doesnt explain anything but yesh.



![Linux](https://img.shields.io/badge/Linux-supported-success)
![Windows](https://img.shields.io/badge/Windows-supported-success)
![macOS](https://img.shields.io/badge/macOS-supported-success)
![Qt](https://img.shields.io/badge/Qt-6.8_LTS%2B-blue)
![License](https://img.shields.io/badge/License-Apache--2.0-green)

## Features

* Shapes: rectangle, ellipse, triangle, star with fill / stroke / opacity / radius
* Layers: groups, drill-in, reorder, rename, eye / lock, context menu (copy / paste / duplicate / group / arrange / delete)
* Smart snapping: edges, centers, scene, equal gaps (Alt suspends)
* Design panel with mixed-value handling
* Dark / light theme, custom frameless titlebar with tabs
* Group and manage components
* Animate with custom and wide range of preset animations, etc.

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

While the stack is not the most inviting for people to contribute in but if you still want to do it-

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and Run before pushing:

```sh
/usr/lib/qt6/bin/qmlformat -i $(git diff --name-only | grep '\.qml$')
/usr/lib/qt6/bin/qmllint src/qml/**/*.qml
cmake --preset ci && cmake --build --preset ci
```

## License

Every single app in `tot` series will be open-source and Apache 2.0 license. So yeah, enjoy.

Apache-2.0 — see [`LICENSE`](LICENSE).
