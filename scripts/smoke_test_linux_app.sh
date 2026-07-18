#!/usr/bin/env bash
set -Eeuo pipefail

APPDIR=""
APPIMAGE=""
SCORE=""
TIMEOUT_SECONDS=90
USE_XVFB=0
REQUIRE_XEN_TUNER=0
XEN_TUNER_QML=""

usage() {
  cat <<'EOF'
Usage: scripts/smoke_test_linux_app.sh (--appdir DIR | --appimage FILE) [options]

Runs an isolated --version check without a display, then opens and exports a
small score through the packaged runtime. The export can optionally run under
Xvfb to exercise the XCB platform plugin as well as the default offscreen path.

Options:
  --appdir DIR           Deployed AppDir.
  --appimage FILE        AppImage to extract and test without FUSE.
  --score FILE           Score used for the export smoke test.
  --timeout SECONDS      Per-command timeout. Default: 90.
  --xvfb                 Run the score export through xvfb-run.
  --require-xen-tuner    Require the staged Xen Tuner runtime.
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
    --appimage)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      APPIMAGE="$2"
      shift 2
      ;;
    --score)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      SCORE="$2"
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --xvfb)
      USE_XVFB=1
      shift
      ;;
    --require-xen-tuner)
      REQUIRE_XEN_TUNER=1
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

[[ "$(uname -s)" == "Linux" ]] || die "this smoke test must run on Linux"
[[ -n "$APPDIR" || -n "$APPIMAGE" ]] || die "--appdir or --appimage is required"
[[ -z "$APPDIR" || -z "$APPIMAGE" ]] || die "use only one of --appdir and --appimage"
[[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || die "--timeout must be a positive integer"
command -v timeout >/dev/null 2>&1 || die "timeout is required"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/musescore-linux-smoke.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "$APPIMAGE" ]]; then
  [[ "$APPIMAGE" == /* ]] || APPIMAGE="$(cd "$(dirname "$APPIMAGE")" && pwd)/$(basename "$APPIMAGE")"
  [[ -x "$APPIMAGE" ]] || die "AppImage is not executable: $APPIMAGE"
  if command -v unsquashfs >/dev/null 2>&1; then
    extracted=0
    while IFS=: read -r squashfs_offset _; do
      rm -rf "$TMP_DIR/squashfs-root"
      if unsquashfs -q -o "$squashfs_offset" -d "$TMP_DIR/squashfs-root" \
        "$APPIMAGE" >/dev/null 2>&1 && [[ -x "$TMP_DIR/squashfs-root/AppRun" ]]; then
        extracted=1
        break
      fi
    done < <(LC_ALL=C grep -abo 'hsqs' "$APPIMAGE")
    [[ "$extracted" == "1" ]] \
      || die "unsquashfs could not locate a valid AppImage filesystem in $APPIMAGE"
  else
    # Native Linux hosts can use the embedded AppImage runtime. Cross-arch
    # Docker/QEMU builders should install unsquashfs because the static runtime
    # may not be handled by binfmt even when ordinary target ELFs are.
    (
      cd "$TMP_DIR"
      "$APPIMAGE" --appimage-extract >/dev/null
    )
  fi
  APPDIR="$TMP_DIR/squashfs-root"
fi

APPDIR="$(cd "$APPDIR" && pwd)"
RUNNER="$APPDIR/AppRun"
[[ -x "$RUNNER" ]] || die "AppRun is missing or not executable: $RUNNER"

if [[ -z "$SCORE" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # test/testsmall.mscx predates the file format accepted by this Qt 6 port.
  # Use a compact repository fixture that is known to load and export.
  SCORE="$SCRIPT_DIR/../mtest/libmscore/unrollrepeats/pickup-measure-test.mscx"
fi
[[ "$SCORE" == /* ]] || SCORE="$(cd "$(dirname "$SCORE")" && pwd)/$(basename "$SCORE")"
[[ -f "$SCORE" ]] || die "smoke-test score does not exist: $SCORE"

if [[ "$REQUIRE_XEN_TUNER" == "1" ]]; then
  XEN_TUNER_CONFIG="$(find "$APPDIR" -type f -name xen-tuner.config.json -path '*/plugins/musescore-xen-tuner/*' -print -quit)"
  XEN_TUNER_QML="$(find "$APPDIR" -type f -path '*/plugins/musescore-xen-tuner/Xen Tuner/xen tuner.qml' -print -quit)"
  [[ -n "$XEN_TUNER_CONFIG" && -n "$XEN_TUNER_QML" ]] || die "the staged Xen Tuner runtime is incomplete"
  XEN_TUNER_ROOT="$(dirname "$XEN_TUNER_CONFIG")"
  XEN_TUNER_MANIFEST="$(dirname "$XEN_TUNER_ROOT")/musescore-xen-tuner.runtime.manifest"
  [[ -f "$XEN_TUNER_MANIFEST" ]] || die "the packaged Xen Tuner runtime manifest is missing"
  for command_name in cmp sha256sum sort; do
    command -v "$command_name" >/dev/null 2>&1 \
      || die "required Xen Tuner verification command is missing: $command_name"
  done
  XEN_TUNER_EXPECTED_FILES="$TMP_DIR/xen-tuner-expected-files.txt"
  XEN_TUNER_ACTUAL_FILES="$TMP_DIR/xen-tuner-actual-files.txt"
  XEN_TUNER_CHECKSUM_OUTPUT="$TMP_DIR/xen-tuner-checksums.txt"
  sed -n 's/^[[:xdigit:]]\{64\}  //p' "$XEN_TUNER_MANIFEST" \
    | LC_ALL=C sort > "$XEN_TUNER_EXPECTED_FILES"
  (
    cd "$XEN_TUNER_ROOT"
    find . -type f -printf '%P\n' | LC_ALL=C sort
  ) > "$XEN_TUNER_ACTUAL_FILES"
  if ! cmp -s "$XEN_TUNER_EXPECTED_FILES" "$XEN_TUNER_ACTUAL_FILES"; then
    diff -u "$XEN_TUNER_EXPECTED_FILES" "$XEN_TUNER_ACTUAL_FILES" >&2 || true
    die "the packaged Xen Tuner runtime file list differs from its pinned manifest"
  fi
  if ! (
    cd "$XEN_TUNER_ROOT"
    sha256sum --strict --check "$XEN_TUNER_MANIFEST"
  ) > "$XEN_TUNER_CHECKSUM_OUTPUT" 2>&1; then
    sed -n '1,200p' "$XEN_TUNER_CHECKSUM_OUTPUT" >&2
    die "the packaged Xen Tuner runtime content differs from its pinned manifest"
  fi
  for helper in \
    "Xen Tuner/midx_pitch_bend_converter.py" \
    "Xen Tuner/midx_python_writer.py" \
    "Xen Tuner/midx_shell_writer.sh"; do
    [[ -x "$XEN_TUNER_ROOT/$helper" ]] \
      || die "the packaged Xen Tuner helper is missing or not executable: $helper"
  done
  echo "Xen Tuner resource check passed: $XEN_TUNER_QML"
fi

SMOKE_HOME="$TMP_DIR/home"
CONFIG_DIR="$TMP_DIR/config"
OUTPUT_PDF="$TMP_DIR/export.pdf"
mkdir -p "$SMOKE_HOME" "$CONFIG_DIR" "$TMP_DIR/cache" "$TMP_DIR/runtime"
chmod 700 "$TMP_DIR/runtime"

COMMON_ENV=(
  HOME="$SMOKE_HOME"
  XDG_CACHE_HOME="$TMP_DIR/cache"
  XDG_CONFIG_HOME="$CONFIG_DIR"
  XDG_RUNTIME_DIR="$TMP_DIR/runtime"
  QT_QUICK_BACKEND=software
  QTWEBENGINE_DISABLE_SANDBOX=1
  MUSESCORE_DIAGNOSTIC_LOG="$TMP_DIR/musescore.log"
)

echo "Running display-free version smoke test"
env "${COMMON_ENV[@]}" QT_QPA_PLATFORM=offscreen \
  timeout "$TIMEOUT_SECONDS" "$RUNNER" --version > "$TMP_DIR/version.txt" 2>&1
grep -Eq '[0-9]+\.[0-9]+' "$TMP_DIR/version.txt" \
  || die "MuseScore --version did not produce a recognizable version"

SMOKE_COMMAND=(
  timeout "$TIMEOUT_SECONDS"
  "$RUNNER"
  -F
  -s
  -m
  -w
  -c "$CONFIG_DIR"
  -o "$OUTPUT_PDF"
  "$SCORE"
)

if [[ "$USE_XVFB" == "1" ]]; then
  command -v xvfb-run >/dev/null 2>&1 || die "--xvfb was requested but xvfb-run is unavailable"
  echo "Running score export smoke test through Xvfb"
  env "${COMMON_ENV[@]}" xvfb-run -a -s '-screen 0 1280x800x24' "${SMOKE_COMMAND[@]}"
else
  echo "Running display-free score export smoke test"
  env "${COMMON_ENV[@]}" QT_QPA_PLATFORM=offscreen "${SMOKE_COMMAND[@]}"
fi

[[ -s "$OUTPUT_PDF" ]] || die "score export did not produce a non-empty PDF"
if command -v file >/dev/null 2>&1; then
  file "$OUTPUT_PDF" | grep -q 'PDF document' || die "score export output is not a PDF"
fi

if [[ "$REQUIRE_XEN_TUNER" == "1" ]]; then
  # The GUI discovery run must reach PluginManager. A fresh configuration has
  # firstStart=true and opens a modal startup wizard, so seed the same QSettings
  # keys the wizard would set before starting the headless/Xvfb process. The
  # export smoke above uses -F and clears the config, so this belongs here.
  SMOKE_SETTINGS_DIR="$CONFIG_DIR/MuseScore"
  SMOKE_SETTINGS_FILE="$SMOKE_SETTINGS_DIR/MuseScore3.ini"
  mkdir -p "$SMOKE_SETTINGS_DIR"
  printf '%s\n' \
    '[application]' \
    'startup\firstStart=false' \
    '[ui]' \
    'application\startup\showTours=false' \
    'application\startup\showStartCenter=false' \
    > "$SMOKE_SETTINGS_FILE"

  PLUGIN_DISCOVERY_TIMEOUT="${MUSESCORE_PLUGIN_DISCOVERY_TIMEOUT:-20}"
  [[ "$PLUGIN_DISCOVERY_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "MUSESCORE_PLUGIN_DISCOVERY_TIMEOUT must be a positive integer"
  PLUGIN_STARTUP_OUTPUT="$TMP_DIR/plugin-startup.txt"
  PLUGIN_RUN_OUTPUT="$TMP_DIR/plugin-run.txt"
  PLUGIN_RELATIVE_PATH="musescore-xen-tuner/Xen Tuner/xen tuner.qml"

  # In MuseScore 3, <load> means that the plugin is enabled and registered in
  # the Plugins menu. It does not by itself invoke a dock plugin or show its
  # panel; the explicit plugin-mode run below exercises the entry point.
  echo "Checking Xen Tuner discovery and first-start default enablement"
  set +e
  if [[ "$USE_XVFB" == "1" ]]; then
    env "${COMMON_ENV[@]}" xvfb-run -a -s '-screen 0 1280x800x24' \
      timeout "$PLUGIN_DISCOVERY_TIMEOUT" "$RUNNER" -s -m -w -c "$CONFIG_DIR" "$SCORE" \
      > "$PLUGIN_STARTUP_OUTPUT" 2>&1
  else
    env "${COMMON_ENV[@]}" QT_QPA_PLATFORM=offscreen \
      timeout "$PLUGIN_DISCOVERY_TIMEOUT" "$RUNNER" -s -m -w -c "$CONFIG_DIR" "$SCORE" \
      > "$PLUGIN_STARTUP_OUTPUT" 2>&1
  fi
  plugin_startup_status=$?
  set -e
  case "$plugin_startup_status" in
    0|124|143) ;;
    *)
      sed -n '1,160p' "$PLUGIN_STARTUP_OUTPUT" >&2
      die "MuseScore exited unexpectedly while discovering the default Xen Tuner plugin (status $plugin_startup_status)"
      ;;
  esac

  PLUGIN_LIST="$(find "$CONFIG_DIR" -type f -name plugins.xml -print -quit)"
  [[ -n "$PLUGIN_LIST" ]] || die "MuseScore did not persist plugins.xml during the Xen Tuner discovery smoke test"
  awk '
    /<Plugin>/ { in_plugin=1; block="" }
    in_plugin { block=block $0 "\n" }
    /<\/Plugin>/ {
      if (block ~ /musescore-xen-tuner\/Xen Tuner\/xen tuner\.qml/ && block ~ /<load>1<\/load>/)
        found=1
      in_plugin=0
    }
    END { exit(found ? 0 : 1) }
  ' "$PLUGIN_LIST" || die "Xen Tuner was not discovered and marked load=1 in $PLUGIN_LIST"
  echo "Xen Tuner discovery/default-enable check passed: $PLUGIN_LIST"

  echo "Invoking the Xen Tuner QML entry point through MuseScore plugin mode"
  set +e
  if [[ "$USE_XVFB" == "1" ]]; then
    env "${COMMON_ENV[@]}" xvfb-run -a -s '-screen 0 1280x800x24' \
      timeout "$TIMEOUT_SECONDS" "$RUNNER" -s -m -w -c "$CONFIG_DIR" -p "$PLUGIN_RELATIVE_PATH" "$SCORE" \
      > "$PLUGIN_RUN_OUTPUT" 2>&1
  else
    env "${COMMON_ENV[@]}" QT_QPA_PLATFORM=offscreen \
      timeout "$TIMEOUT_SECONDS" "$RUNNER" -s -m -w -c "$CONFIG_DIR" -p "$PLUGIN_RELATIVE_PATH" "$SCORE" \
      > "$PLUGIN_RUN_OUTPUT" 2>&1
  fi
  plugin_run_status=$?
  set -e

  if grep -Eiq \
    'module ".*" is not installed|Type .* unavailable|QQmlComponent: Component is not ready|creating component .* failed|invalid QML root|Cannot load library' \
    "$PLUGIN_RUN_OUTPUT" "$TMP_DIR/musescore.log" 2>/dev/null; then
    sed -n '1,200p' "$PLUGIN_RUN_OUTPUT" >&2
    grep -Ein \
      'module ".*" is not installed|Type .* unavailable|QQmlComponent: Component is not ready|creating component .* failed|invalid QML root|Cannot load library' \
      "$TMP_DIR/musescore.log" >&2 2>/dev/null || true
    die "Xen Tuner produced a QML load error"
  fi
  if [[ "$plugin_run_status" -ne 0 ]]; then
    sed -n '1,200p' "$PLUGIN_RUN_OUTPUT" >&2
    die "MuseScore could not invoke the Xen Tuner entry point (status $plugin_run_status)"
  fi
  echo "Xen Tuner runtime QML load check passed"
fi

echo "Version: $(tr '\n' ' ' < "$TMP_DIR/version.txt")"
echo "Exported smoke-test PDF: $OUTPUT_PDF"
echo "Linux packaged smoke test passed: $APPDIR"
