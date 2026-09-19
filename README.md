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

* Shapes: rectangle, ellipse, triangle, star, pen paths, text and images — with solid / linear-gradient fill, stroke, opacity, radius + independent corners, flip
* Effects: stackable outer / inner shadows and glows, layer + background blur, animated film grain (canvas and video export share one painter, so they match)
* Home library: workspaces, starring, drag-move between workspaces, live card previews, inline rename
* Layers: groups, drill-in, reorder, rename, eye / lock, context menu (copy / paste / duplicate / group / arrange / delete)
* Smart snapping: edges, centers, scene, ruler guides, equal gaps (Alt suspends)
* Persistent guides (drag from the canvas edges to create, drag to move, release home or double-click to remove) with a zoom pill and zoom-to-fit (Ctrl+0)
* Design panel with mixed-value handling, typography controls and a Figma-style color picker
* Dark / light theme, custom frameless titlebar with draggable tabs (titles follow design names)
* General settings: new-design defaults (canvas size presets, background, timeline length), video-export defaults and storage footprint
* Animate with presets plus custom from-to properties (scale, rotate, move, opacity, color, hide/show, resize, corner radius, stroke) and drawable motion paths with full point editing, easing graphs and a timeline (zoom slider + fit, multi-clip joint drag).
* Audio: import MP3 / WAV / OGG / FLAC onto timeline lanes with live preview, mixed into the export
* Video export: SD / HD / 4K at 30 / 60fps mp4 through system ffmpeg, with progress + cancel
* Component export: per-selection PNGs at 1x / 2x / 3x plus resolution-independent SVG vectors on transparency from the design panel, multi-file packs as `{Design}.zip`

## Install

Grab the version you want from the [Releases page](https://github.com/emty-png/totm/releases):

* **Ubuntu / Debian:** `totm-x86_64.AppImage` — `chmod +x` and run. On Ubuntu 24.04+ install FUSE first (`sudo apt install libfuse2t64`). `ffmpeg` is bundled inside, video export works out of the box.
* **Arch:** build `packaging/arch/PKGBUILD` with `makepkg -si` (deps: `qt6-base qt6-declarative qt6-svg qt6-multimedia qt6-multimedia-ffmpeg qt6-shadertools ffmpeg`).
* **macOS (apple silicon):** `totm-arm64.dmg` — drag to Applications. It is unsigned, so first launch needs right-click > Open. `ffmpeg` via `brew install ffmpeg` for video export.
* **Windows:** the `totm-*-win64.exe` installer. `ffmpeg` via `winget install -e --id Gyan.FFmpeg` for video export.

Or build from source. You need CMake 3.21+, Qt 6.8+ with the `Quick`, `Svg`, `Multimedia`, `ShaderTools` and `Network` modules, a C++17 compiler and Ninja. Video export shells out to a system `ffmpeg`, so have it on your `PATH` too (check with `ffmpeg -version`) — the app runs fine without it, export just tells you how to install it.

### Arch / CachyOS (btw i use cachy)

```sh
sudo pacman -S --needed base-devel cmake ninja qt6-base qt6-declarative qt6-svg qt6-multimedia qt6-multimedia-ffmpeg qt6-shadertools ffmpeg
cmake --preset dev
cmake --build --preset dev
./build/dev/src/totm
```

### Ubuntu / Debian

Heads up: apt's Qt is too old (6.4, we need 6.8+), so grab Qt 6.8 from the online installer at <https://www.qt.io/download-qt-installer> (tick Qt 6.8 Desktop — it bundles all required modules — plus CMake + Ninja), or via aqtinstall:

```sh
pip install aqtinstall
aqt install-qt linux desktop 6.8.3 linux_gcc_64 --outputdir ~/Qt -m qtmultimedia qtshadertools
```

Then:

```sh
sudo apt install build-essential ninja-build libgl1 libxkbcommon0 libdbus-1-3 ffmpeg
export CMAKE_PREFIX_PATH=~/Qt/6.8.3/gcc_64 # match the version you installed
cmake --preset dev
cmake --build --preset dev
./build/dev/src/totm
```

### macOS (apple silicon)

```sh
xcode-select --install
brew install cmake ninja qt@6 ffmpeg
export CMAKE_PREFIX_PATH=$(brew --prefix qt@6)
cmake --preset dev
cmake --build --preset dev
open build/dev/src/totm.app
```

### Windows

Grab Visual Studio 2022 (or just the Build Tools) with the C++ workload, and Qt 6.8 MSVC 2022 64-bit from the online installer at <https://www.qt.io/download-qt-installer>. Then in `pwsh`:

```ps1
winget install Kitware.CMake Ninja-build.Ninja-build Gyan.FFmpeg
$env:CMAKE_PREFIX_PATH = "C:\Qt\6.8.3\msvc2022_64" # match the version you installed
cmake --preset dev
cmake --build --preset dev
.\build\dev\src\totm.exe
```

No winget? Grab a build at <https://www.gyan.dev/ffmpeg/builds/>, unzip it and add its `bin` folder to `PATH`. Either way, close + reopen the terminal and check `ffmpeg -version`.

### Desktop integration (Linux)

`cmake --install build/dev` installs `totm` with its hicolor icons and desktop entry, so it shows up in your launcher with the proper logo on both X11 and Wayland. The install also registers the `.totm` bundle type (`application/x-totm-design`) and makes totm its default handler, so double-clicking a `.totm` file imports it into the running window instead of spawning a second one (same on Windows via the installer association and macOS via the bundle document type).

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
