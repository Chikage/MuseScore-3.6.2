#!/usr/bin/env bash
set -Eeuo pipefail

APPDIR=""
EXPECTED_ARCH=""
EXPECTED_QT_MAJOR=""
MAX_GLIBC=""
EXECUTABLE=""
REQUIRE_XEN_TUNER=0
REQUIRE_FUSE2=0

usage() {
  cat <<'EOF'
Usage: scripts/verify_linux_appdir.sh --appdir DIR [options]

Options:
  --appdir DIR           Installed/deployed AppDir to verify.
  --arch ARCH            Expected architecture: x86_64 or aarch64.
  --qt-major VERSION     Expected Qt major version: 5 or 6.
  --max-glibc VERSION    Reject ELF files requiring a newer GLIBC version.
  --executable FILE      Main executable relative to AppDir or absolute.
  --require-xen-tuner    Require the staged Xen Tuner runtime.
  --require-fuse2        Require bundled libfuse.so.2 for FUSE-less extraction.
  -h, --help             Show this help.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --appdir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      APPDIR="$2"
      shift 2
      ;;
    --arch)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      EXPECTED_ARCH="$2"
      shift 2
      ;;
    --qt-major)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      EXPECTED_QT_MAJOR="$2"
      shift 2
      ;;
    --max-glibc)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      MAX_GLIBC="$2"
      shift 2
      ;;
    --executable)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      EXECUTABLE="$2"
      shift 2
      ;;
    --require-xen-tuner)
      REQUIRE_XEN_TUNER=1
      shift
      ;;
    --require-fuse2)
      REQUIRE_FUSE2=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || die "this verifier must run on Linux"
[[ -n "$APPDIR" ]] || die "--appdir is required"
[[ -d "$APPDIR" ]] || die "AppDir does not exist: $APPDIR"

for command_name in cmp file find ldd readelf sha256sum sort; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command is missing: $command_name"
done

APPDIR="$(cd "$APPDIR" && pwd)"
case "$EXPECTED_ARCH" in
  ""|x86_64|aarch64|arm64) ;;
  *) die "unsupported expected architecture: $EXPECTED_ARCH" ;;
esac
case "$EXPECTED_QT_MAJOR" in
  ""|5|6) ;;
  *) die "Qt major version must be 5 or 6" ;;
esac

if [[ -n "$EXECUTABLE" ]]; then
  [[ "$EXECUTABLE" == /* ]] || EXECUTABLE="$APPDIR/$EXECUTABLE"
else
  for candidate in "$APPDIR"/bin/mscore-portable* "$APPDIR"/bin/mscore*; do
    if [[ -x "$candidate" && -f "$candidate" ]]; then
      EXECUTABLE="$candidate"
      break
    fi
  done
fi
[[ -n "$EXECUTABLE" && -x "$EXECUTABLE" ]] || die "could not locate the MuseScore executable under $APPDIR/bin"

FAILURES=0
ELF_COUNT=0
UNRESOLVED_COUNT=0
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/musescore-linux-verify.XXXXXX")"
GLIBC_VERSIONS="$TMP_DIR/glibc-versions.txt"
trap 'rm -rf "$TMP_DIR"' EXIT

report_failure() {
  echo "error: $*" >&2
  FAILURES=$((FAILURES + 1))
}

is_elf() {
  file -b "$1" | grep -q '^ELF '
}

arch_matches() {
  local description=""
  description="$(file -b "$1")"
  case "$EXPECTED_ARCH" in
    "") return 0 ;;
    x86_64) [[ "$description" == *"x86-64"* ]] ;;
    aarch64|arm64) [[ "$description" == *"ARM aarch64"* || "$description" == *"aarch64"* ]] ;;
  esac
}

while IFS= read -r -d '' link_path; do
  link_target="$(readlink "$link_path")"
  if [[ "$link_target" == /* ]]; then
    report_failure "$link_path is an absolute symbolic link to $link_target"
  elif [[ ! -e "$link_path" ]]; then
    report_failure "$link_path is a broken symbolic link to $link_target"
  fi
done < <(find "$APPDIR" -type l -print0)

while IFS= read -r -d '' file_path; do
  is_elf "$file_path" || continue
  ELF_COUNT=$((ELF_COUNT + 1))

  if ! arch_matches "$file_path"; then
    report_failure "$file_path has the wrong architecture: $(file -b "$file_path")"
  fi

  dynamic_info="$(readelf -d "$file_path" 2>/dev/null || true)"
  while IFS= read -r runpath; do
    [[ -n "$runpath" ]] || continue
    IFS=: read -r -a runpath_entries <<< "$runpath"
    for entry in "${runpath_entries[@]}"; do
      case "$entry" in
        ""|'$ORIGIN'|'$ORIGIN/'*|\$ORIGIN|\$ORIGIN/*) ;;
        /*) report_failure "$file_path contains an absolute RPATH/RUNPATH entry: $entry" ;;
      esac
    done
  done < <(printf '%s\n' "$dynamic_info" | sed -n 's/.*(RPATH).*\[\(.*\)\].*/\1/p; s/.*(RUNPATH).*\[\(.*\)\].*/\1/p')

  while IFS= read -r needed; do
    [[ -n "$needed" ]] || continue
    [[ "$needed" != /* ]] || report_failure "$file_path has an absolute DT_NEEDED entry: $needed"
    case "$needed" in
      libQt5*.so*)
        [[ -z "$EXPECTED_QT_MAJOR" || "$EXPECTED_QT_MAJOR" == "5" ]] \
          || report_failure "$file_path contains a Qt 5 dependency in a Qt ${EXPECTED_QT_MAJOR:-unknown} AppDir: $needed"
        ;;
      libQt6*.so*)
        [[ -z "$EXPECTED_QT_MAJOR" || "$EXPECTED_QT_MAJOR" == "6" ]] \
          || report_failure "$file_path contains a Qt 6 dependency in a Qt ${EXPECTED_QT_MAJOR:-unknown} AppDir: $needed"
        ;;
    esac
  done < <(printf '%s\n' "$dynamic_info" | sed -n 's/.*Shared library: \[\(.*\)\].*/\1/p')

  readelf --version-info "$file_path" 2>/dev/null \
    | sed -n 's/.*Name: GLIBC_\([0-9][0-9.]*\).*/\1/p' >> "$GLIBC_VERSIONS" || true

  if printf '%s\n' "$dynamic_info" | grep -q '(NEEDED)'; then
    # linuxdeploy is expected to give every ELF object an origin-relative
    # RUNPATH. Clear the host's LD_LIBRARY_PATH so the check cannot pass by
    # accidentally finding the build SDK.
    ldd_output="$(env -u LD_LIBRARY_PATH ldd "$file_path" 2>&1 || true)"
    while IFS= read -r missing; do
      [[ -n "$missing" ]] || continue
      report_failure "$file_path has an unresolved dependency: $missing"
      UNRESOLVED_COUNT=$((UNRESOLVED_COUNT + 1))
    done < <(printf '%s\n' "$ldd_output" | sed -n 's/^[[:space:]]*\([^[:space:]]*\)[[:space:]]*=>[[:space:]]*not found.*/\1/p')

    while read -r dependency arrow resolved rest; do
      [[ "$arrow" == "=>" && "$resolved" == /* ]] || continue
      case "$resolved" in
        "$APPDIR"/*) ;;
        /opt/*|/home/*|/work/*|/usr/local/*)
          report_failure "$file_path resolves $dependency through a build-host path: $resolved"
          ;;
      esac
      case "$dependency" in
        libQt*.so*|libicu*.so*|libssl.so*|libcrypto.so*|libportaudio.so*|libsndfile.so*|libvorbis*.so*|libogg.so*|libFLAC.so*|libmpg123.so*|libopus.so*)
          [[ "$resolved" == "$APPDIR"/* ]] || report_failure "$file_path resolves bundled dependency $dependency outside the AppDir: $resolved"
          ;;
      esac
    done <<< "$ldd_output"
  fi
done < <(find "$APPDIR" -type f -print0)

# Also reject an unused Qt major left in the payload. This catches stale
# libraries copied by a previous deployment even when no ELF currently links
# them, which would otherwise make a Qt 5/Qt 6 package appear self-contained
# while still shipping a mixed runtime.
while IFS= read -r qt_file; do
  qt_name="$(basename "$qt_file")"
  case "$qt_name" in
    libQt5*.so*)
      [[ -z "$EXPECTED_QT_MAJOR" || "$EXPECTED_QT_MAJOR" == "5" ]] \
        || report_failure "the AppDir contains a stale Qt 5 library in a Qt ${EXPECTED_QT_MAJOR:-unknown} package: $qt_file"
      ;;
    libQt6*.so*)
      [[ -z "$EXPECTED_QT_MAJOR" || "$EXPECTED_QT_MAJOR" == "6" ]] \
        || report_failure "the AppDir contains a stale Qt 6 library in a Qt ${EXPECTED_QT_MAJOR:-unknown} package: $qt_file"
      ;;
  esac
done < <(find "$APPDIR" \( -type f -o -type l \) \
  \( -name 'libQt5*.so*' -o -name 'libQt6*.so*' \) -print)

[[ "$ELF_COUNT" -gt 0 ]] || report_failure "no ELF files were found in $APPDIR"

main_dynamic_info="$(readelf -d "$EXECUTABLE" 2>/dev/null || true)"
if [[ -n "$EXPECTED_QT_MAJOR" ]]; then
  if ! printf '%s\n' "$main_dynamic_info" | grep -q "Shared library: \[libQt${EXPECTED_QT_MAJOR}Core\.so"; then
    report_failure "$EXECUTABLE does not link the expected Qt $EXPECTED_QT_MAJOR Core library"
  fi
  if ! find "$APPDIR" \( -type f -o -type l \) -name "libQt${EXPECTED_QT_MAJOR}Core.so*" -print -quit | grep -q .; then
    report_failure "the AppDir does not contain libQt${EXPECTED_QT_MAJOR}Core"
  fi
fi

find "$APPDIR" \( -type f -o -type l \) -name libqxcb.so -print -quit | grep -q . \
  || report_failure "the AppDir is missing the Qt XCB platform plugin"
find "$APPDIR" \( -type f -o -type l \) -name libqoffscreen.so -print -quit | grep -q . \
  || report_failure "the AppDir is missing the Qt offscreen platform plugin required by headless smoke tests"

if [[ "$REQUIRE_FUSE2" == "1" ]]; then
  find "$APPDIR" \( -type f -o -type l \) -name 'libfuse.so.2' -print -quit | grep -q . \
    || report_failure "the AppDir is missing bundled libfuse.so.2 for FUSE-less extraction"
fi

if printf '%s\n' "$main_dynamic_info" | grep -q 'Shared library: \[libQt[56]WebEngineCore\.so'; then
  find "$APPDIR" -type f -name QtWebEngineProcess -print -quit | grep -q . \
    || report_failure "QtWebEngine is linked but QtWebEngineProcess is missing"
  find "$APPDIR" -type f \( -name qtwebengine_resources.pak -o -name icudtl.dat \) -print -quit | grep -q . \
    || report_failure "QtWebEngine is linked but its runtime resources are missing"
fi

if [[ "$REQUIRE_XEN_TUNER" == "1" ]]; then
  xen_tuner_config="$(find "$APPDIR" -type f -name xen-tuner.config.json -path '*/plugins/musescore-xen-tuner/*' -print -quit)"
  xen_tuner_root=""
  if [[ -z "$xen_tuner_config" ]]; then
    report_failure "the staged Xen Tuner runtime is missing"
  else
    xen_tuner_root="$(dirname "$xen_tuner_config")"
  fi

  if [[ -n "$xen_tuner_root" ]]; then
    xen_tuner_manifest="$(dirname "$xen_tuner_root")/musescore-xen-tuner.runtime.manifest"
    if [[ ! -f "$xen_tuner_manifest" ]]; then
      report_failure "the packaged Xen Tuner runtime manifest is missing"
    else
      xen_tuner_expected_files="$TMP_DIR/xen-tuner-expected-files.txt"
      xen_tuner_actual_files="$TMP_DIR/xen-tuner-actual-files.txt"
      xen_tuner_checksum_output="$TMP_DIR/xen-tuner-checksums.txt"
      sed -n 's/^[[:xdigit:]]\{64\}  //p' "$xen_tuner_manifest" \
        | LC_ALL=C sort > "$xen_tuner_expected_files"
      (
        cd "$xen_tuner_root"
        find . -type f -printf '%P\n' | LC_ALL=C sort
      ) > "$xen_tuner_actual_files"
      if ! cmp -s "$xen_tuner_expected_files" "$xen_tuner_actual_files"; then
        report_failure "the packaged Xen Tuner runtime file list differs from its staging manifest"
        diff -u "$xen_tuner_expected_files" "$xen_tuner_actual_files" >&2 || true
      fi
      if ! (
        cd "$xen_tuner_root"
        sha256sum --strict --check "$xen_tuner_manifest"
      ) > "$xen_tuner_checksum_output" 2>&1; then
        report_failure "the packaged Xen Tuner runtime content differs from its staging manifest"
        sed -n '1,200p' "$xen_tuner_checksum_output" >&2
      fi
    fi

    [[ -f "$xen_tuner_root/Xen Tuner/xen tuner.qml" ]] \
      || report_failure "the Xen Tuner MuseScore 3 entry point is missing"
    for helper in \
      "Xen Tuner/midx_pitch_bend_converter.py" \
      "Xen Tuner/midx_python_writer.py" \
      "Xen Tuner/midx_shell_writer.sh"; do
      [[ -f "$xen_tuner_root/$helper" ]] \
        || report_failure "the Xen Tuner helper is missing: $helper"
      [[ -x "$xen_tuner_root/$helper" ]] \
        || report_failure "the Xen Tuner helper is not executable: $helper"
    done
  fi

  for qml_module in \
    QtQuick/qmldir \
    QtQuick/Controls/qmldir \
    QtQuick/Dialogs/qmldir \
    QtQuick/Layouts/qmldir \
    QtQuick/Window/qmldir \
    Qt/labs/settings/qmldir; do
    find "$APPDIR" -type f -path "*/qml/$qml_module" -print -quit | grep -q . \
      || report_failure "Xen Tuner runtime QML module is missing: $qml_module"
  done
fi

MAX_REQUIRED_GLIBC=""
if [[ -s "$GLIBC_VERSIONS" ]]; then
  MAX_REQUIRED_GLIBC="$(LC_ALL=C sort -Vu "$GLIBC_VERSIONS" | tail -n 1)"
fi
if [[ -n "$MAX_GLIBC" && -n "$MAX_REQUIRED_GLIBC" ]]; then
  highest="$(printf '%s\n%s\n' "$MAX_GLIBC" "$MAX_REQUIRED_GLIBC" | LC_ALL=C sort -V | tail -n 1)"
  if [[ "$highest" != "$MAX_GLIBC" ]]; then
    report_failure "AppDir requires GLIBC_$MAX_REQUIRED_GLIBC, newer than the allowed GLIBC_$MAX_GLIBC baseline"
  fi
fi

if [[ "$FAILURES" -ne 0 ]]; then
  die "Linux AppDir verification failed with $FAILURES problem(s)"
fi

echo "Main executable: $EXECUTABLE"
echo "Verified ELF files: $ELF_COUNT"
echo "Unresolved dependencies: $UNRESOLVED_COUNT"
echo "Maximum required GLIBC: ${MAX_REQUIRED_GLIBC:-unknown}"
echo "Linux AppDir verification passed: $APPDIR"
