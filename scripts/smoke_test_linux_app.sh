#!/usr/bin/env bash
set -Eeuo pipefail

APPDIR=""
APPIMAGE=""
SCORE=""
TIMEOUT_SECONDS=90
USE_XVFB=0

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
cleanup() {
  chmod -R u+w "$TMP_DIR" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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

SMOKE_HOME="$TMP_DIR/home"
CONFIG_DIR="$TMP_DIR/config"
OUTPUT_PDF="$TMP_DIR/export.pdf"
DATA_DIR="$TMP_DIR/data"
mkdir -p "$SMOKE_HOME" "$CONFIG_DIR" "$TMP_DIR/cache" "$DATA_DIR" "$TMP_DIR/runtime"
chmod 700 "$TMP_DIR/runtime"

COMMON_ENV=(
  HOME="$SMOKE_HOME"
  XDG_CACHE_HOME="$TMP_DIR/cache"
  XDG_CONFIG_HOME="$CONFIG_DIR"
  XDG_DATA_HOME="$DATA_DIR"
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

echo "Version: $(tr '\n' ' ' < "$TMP_DIR/version.txt")"
echo "Exported smoke-test PDF: $OUTPUT_PDF"
echo "Linux packaged smoke test passed: $APPDIR"
