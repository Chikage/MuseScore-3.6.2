# Xen Tuner dependency

MuseScore packages Xen Tuner from the Git submodule at
`plugins/musescore-xen-tuner`. The dependency is pinned to commit
`ebbeb1763af3a4bb4562e1a653731d19dfe6bfab`; the build exports that commit
rather than the submodule worktree, applies `qt6-runtime.patch`, copies only the
runtime allowlist, and verifies the staged tree checksum.

Bundling defaults to ON for Qt 6 builds and OFF for legacy Qt 5 builds. The
overlay uses the packaged tree only as a read-only resource root; logs, helper
cache files, and the editable user configuration live below MuseScore's
cross-platform `AppDataLocation`.

Initialize it while online:

```sh
git submodule update --init --depth 1 plugins/musescore-xen-tuner
```

For an offline build, point CMake at any local Git checkout that contains the
pinned commit:

```sh
cmake -S . -B build \
  -DMUSESCORE_XEN_TUNER_SOURCE_DIR=/path/to/musescore-xen-tuner
```

The staging script always exports the pinned commit, so uncommitted changes in
a local checkout are preserved but are not silently included in release
packages. To intentionally update the dependency, update the submodule gitlink,
the revision and checksum in `StageXenTuner.cmake`, and regenerate the overlay
against the new commit.
