# Cross-platform build guide

This source tree combines the MuseScore 3.6.2 codebase with the retained
MuseScore 4.7 backports from the sibling Linux and macOS projects.

## Backports retained

- MuseScore 4 score archive compatibility through MSC version 470
- `score_style.mss`, `chordlist.xml`, and `audiosettings.json` loading
- MS Basic soundfont installation and FluidSynth compatibility
- plugin `FileIO` binary helpers
- MuseScore 4 element, connector, harmony, and legacy score-reading compatibility
- cross-staff ottava and text-line layout fixes
- macOS Apple Silicon support and Linux AppImage packaging fixes

## Linux

Requirements: Bash and either Docker or an Ubuntu-compatible build host.

```bash
./build-linux.sh
```

The default build targets the host architecture and creates a `tbz2` artifact
under `build.artifacts/linux`. Build all supported architectures and package
formats with:

```bash
./build-linux.sh --arch all --format all
```

## macOS

Requirements: Xcode command line tools, CMake, and Qt 5. Homebrew users can
install the expected Qt package with `brew install qt@5`.

```bash
./build-macos.sh
```

The script builds the host architecture. Explicit architecture examples:

```bash
./build-macos.sh --arch arm64
./build-macos.sh --arch x86_64
```

The installed app is written below `build.artifacts/macos`.

## Windows

Requirements: Visual Studio 2017, 2019, or 2022 with the Desktop C++ workload,
CMake, and a compatible Qt 5 `qmake` in `PATH`.

Run from Command Prompt:

```bat
build-windows.bat
```

The default is a 64-bit Release build. Other examples:

```bat
build-windows.bat debug 64
build-windows.bat release 32
build-windows.bat all 64
```

`all` builds Release and then installs it into the existing
`msvc.install_x64` or `msvc.install_x86` layout.
