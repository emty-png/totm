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
* Animate with presets plus custom from-to properties (scale, rotate, move, opacity, color, hide/show, resize, corner radius, stroke) and drawable motion paths with full point editing, easing graphs and a timeline.

## Install

No releases yet, so you gotta build it yourself for now. You need CMake 3.21+, Qt 6.8+ with the `Quick` module, a C++17 compiler and Ninja.

### Arch / CachyOS (btw i use cachy)

```sh
sudo pacman -S --needed base-devel cmake ninja qt6-base qt6-declarative
cmake --preset dev
cmake --build --preset dev
./build/dev/src/totm
```

### Ubuntu / Debian

Heads up: apt's Qt is too old (6.4, we need 6.8+), so grab Qt 6.8 from the online installer at <https://www.qt.io/download-qt-installer> (tick Qt 6.8 Desktop + CMake + Ninja) or via `pip install aqtinstall`. Then:

```sh
sudo apt install build-essential ninja-build libgl1 libxkbcommon0 libdbus-1-3
export CMAKE_PREFIX_PATH=~/Qt/6.8.3/gcc_64
cmake --preset dev
cmake --build --preset dev
./build/dev/src/totm
```

### macOS (apple silicon)

```sh
xcode-select --install
brew install cmake ninja qt@6
export CMAKE_PREFIX_PATH=$(brew --prefix qt@6)
cmake --preset dev
cmake --build --preset dev
open build/dev/src/totm.app
```

### Windows

Grab Visual Studio 2022 (or just the Build Tools) with the C++ workload, and Qt 6.8 MSVC 2022 64-bit from the online installer at <https://www.qt.io/download-qt-installer>. Then in `pwsh`:

```ps1
winget install Kitware.CMake Ninja-build.Ninja-build
$env:CMAKE_PREFIX_PATH = "C:\Qt\6.8.3\msvc2022_64"
cmake --preset dev
cmake --build --preset dev
.\build\dev\src\totm.exe
```

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
