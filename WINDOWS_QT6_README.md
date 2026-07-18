# Windows Qt 6 x64 build

The Windows Qt 6 migration target is Microsoft Visual Studio 2022 with a
64-bit Qt installation. Windows x86 remains a Qt 5 legacy target and is
intentionally rejected by the Qt 6 scripts.

## Prerequisites

- Visual Studio 2022 with the Desktop development with C++ workload.
- CMake available on `PATH`.
- A 64-bit Windows PowerShell 5.1+ or PowerShell 7 process (the scripts reject
  32-bit PowerShell for the x64 dependency checks).
- Qt 6.5 or newer for `win64_msvc2022_64` (CI pins Qt 6.8.3), including Qt 5 Compatibility,
  Qt Image Formats, Qt SCXML/StateMachine, Qt WebEngine, Qt WebChannel,
  Qt Positioning, Qt Shader Tools, and Qt Tools. Qt Tools supplies Qt Help,
  Linguist Tools, and the deployment scanner used by this build.
- The existing MuseScore Windows dependency bundle staged as
  `dependencies/include` and `dependencies/libx64`.
- OpenSSL 3 runtime DLLs are recommended for Qt network TLS support.

Set `QT_ROOT_DIR` to the selected Qt installation, then run:

```powershell
.\scripts\build_windows_qt6.ps1 -Configuration Release
```

The command configures, builds, installs, runs `windeployqt`, verifies the
self-contained result, and executes isolated runtime smoke tests under:

```text
build.artifacts/windows/qt6/x64/release
```

The batch entry point now defaults to Qt 6, so `build-windows.bat all` runs this
complete pipeline. Pass `build-windows.bat all 64 5` explicitly for the legacy
Qt 5 build. Build-only modes remain available through `release`,
`relwithdebinfo`, and `debug`.

## Xen Tuner staging

Xen Tuner is vendored as an ordinary directory at
`plugins/musescore-xen-tuner`; the Windows build does not initialize a
Xen Tuner submodule or download plugin sources. To test an alternate already
available ordinary source tree, forward it through either:

```powershell
$env:MUSESCORE_XEN_TUNER_SOURCE_DIR = "C:\staging\musescore-xen-tuner"
.\scripts\build_windows_qt6.ps1
```

or the `-XenTunerSourceDir` parameter. The value is passed to CMake as
`MUSESCORE_XEN_TUNER_SOURCE_DIR`; when omitted, CMake stages the vendored tree.
Verification requires the packaged Xen Tuner runtime by default.

## Individual stages

Deployment and verification can also be rerun separately:

```powershell
.\scripts\deploy_windows_qt6.ps1 `
  -InstallRoot build.artifacts\windows\qt6\x64\release `
  -QtRoot $env:QT_ROOT_DIR `
  -Configuration Release

.\scripts\verify_windows_qt6.ps1 `
  -InstallRoot build.artifacts\windows\qt6\x64\release `
  -Configuration Release `
  -ExpectedXenTunerRoot build.windows-qt6-x64-release\share\xen-tuner-runtime `
  -RunSmokeTests
```

Verification checks required Qt/QML/WebEngine resources, x64 PE architecture,
relative `qt.conf` paths, and recursively resolves DLL imports with Visual
Studio's `dumpbin`. It validates that the packaged Xen Tuner manifest is
non-empty and internally consistent, verifies every listed SHA-256 hash, and
requires the installed tree and manifest to match the allowlisted CMake staging
output exactly. The default build then uses the deployed offscreen platform
plugin to export a score, verifies first-start Xen Tuner discovery with
`load=1`, and invokes the plugin entry point through `-p` while checking for QML
load errors. Pass `-SkipSmoke` only when a build-only environment cannot launch
the deployed executable.

The GitHub Actions workflow is defined in
`.github/workflows/ci_windows_qt6.yml` and publishes the verified directory as
an artifact.
