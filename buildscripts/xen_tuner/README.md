# Xen Tuner runtime

`plugins/musescore-xen-tuner` is a vendored, ordinary directory in the
MuseScore repository.  It is part of the parent repository's source tree; no
Git submodule, nested repository, remote checkout, or fixed external revision
is required to configure or build MuseScore.

Qt 6 builds bundle Xen Tuner by default.  The staging script copies a reviewed
runtime allowlist into the build directory and writes a companion manifest
with one SHA-256 entry per staged file.  Documentation, tests, generators,
development metadata, and the MuseScore 4-only entry point are intentionally
not copied by the staging step.  The install and platform verification scripts
compare the installed tree with that manifest so an extra or modified file is
detected.

The normal source directory is selected automatically:

```text
plugins/musescore-xen-tuner
```

For an offline build or a packaging test, an alternate ordinary directory with
the same layout may be supplied:

```sh
cmake -S . -B build \
  -DMUSESCORE_XEN_TUNER_SOURCE_DIR=/path/to/musescore-xen-tuner
```

The override is useful for testing a local change, but it is not downloaded or
validated against a commit by the build.  Any source change that should ship
must be committed to the parent MuseScore repository.  `StageXenTuner.cmake`
fails early when the source directory or an allowlisted runtime file is
missing.

To omit Xen Tuner from a build explicitly, use:

```sh
cmake -S . -B build -DMUSESCORE_BUNDLE_XEN_TUNER=OFF
```

When the plugin is bundled, packaged resources are read-only.  Runtime logs,
cache files, and the editable user configuration are redirected to a
per-user directory below Qt's `AppDataLocation`; this keeps AppImage,
Windows-installed, and macOS-bundled applications from writing into their
installation image.
